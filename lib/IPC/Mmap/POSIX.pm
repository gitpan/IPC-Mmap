#/**
# Concrete implementation of the IPC::Mmap class for OS's supporting
# a POSIX mmap().
# <p>
# Permission is granted to use this software under the same terms as Perl itself.
# Refer to the <a href='http://perldoc.perl.org/perlartistic.html'>Perl Artistic License</a>
# for details.
#
# @author D. Arnold
# @since 2006-05-01
# @self $self
#*/
package IPC::Mmap::POSIX;
#
#	just bootstrap in the XS code
#
use Carp;
use Fcntl qw(:flock :mode);
use FileHandle;
use IPC::Mmap;
use IPC::Mmap qw(MAP_ANON MAP_ANONYMOUS MAP_FILE MAP_PRIVATE MAP_SHARED
	PROT_READ PROT_WRITE);
use base qw(IPC::Mmap);

use strict;
use warnings;

#use constant MAP_ANON => constant('MAP_ANON', 0);
#use constant MAP_ANONYMOUS => constant('MAP_ANONYMOUS', 0);
#use constant MAP_FILE => constant('MAP_FILE', 0);
#use constant MAP_PRIVATE  => constant('MAP_PRIVATE', 0);
#use constant MAP_SHARED => constant('MAP_SHARED', 0);
#use constant PROT_READ  => constant('PROT_READ', 0);
#use constant PROT_WRITE => constant('PROT_WRITE', 0);

our $VERSION = '0.11';
#/**
# Constructor. mmap()'s using POSIX mmap().
#
# @param $filename
# @param $length 	optional
# @param $protflags optional
# @param $mmapflags optional
#
# @return the IPC::Mmap::POSIX object on success; undef on failure
#*/
sub new {
	my ($class, $file, $length, $prot, $mmap) = @_;

	my $fh;

	croak 'No filename or filehandle provided.'
		unless defined($file) || ($mmap & MAP_ANON);

	croak 'No filename or filehandle provided.'
		if defined($file) && (ref $file) && (ref $file ne 'GLOB');

	if (ref $file) {
		$fh = $file;
	}
	elsif (! ($mmap & MAP_ANON)) {
#
#	specified a filename, we need to open (and maybe create) it
#	NOTE: POSIX doesn't seem to like mmap'ing write-only files,
#	so we'll cheat
#
		my $flags = ($prot == PROT_READ) ? O_RDONLY : O_RDWR;
		$flags |= O_CREAT
			unless -e $file;
		croak "Can't open $file: $!"
			unless sysopen($fh, $file, $flags);
	}

	my @filestats = stat $fh;
	if ($filestats[7] < $length) {
#
#	if file not big enough, expand if its writable
#	else throw error
#
		croak "IPC::Mmap::new(): specified file too small"
			unless ($prot & PROT_WRITE);
#
#	seek to end, then write NULs
#	NOTE: we need to chunk this out!!!
#
		my $tlen = $length - $filestats[7];
		seek($fh, 0, 2);
		syswrite($fh, "\0" x $tlen);
	}
	my ($mapaddr, $maxlen, $slop) = _mmap($length, $prot, $mmap, $fh);
	croak "mmap() failed"
		unless defined($mapaddr);
	my $self = {
		_fh => $fh,
		_file => $file,
		_mmap => $mmap,
		_access => $prot,
		_addr => $mapaddr,
		_maxlen => $maxlen,
		_slop => $slop,
	};

	return bless $self, $class;
}

#/**
# Locks the mmap'ed region. Implemented using flock()
# on the mmap()'ed file.
# <p>
# <b>NOTE:</b> This lock is <b><i>not</i></b> sufficient
# for multithreaded  access control, but <i>may</i> be sufficient for
# multiprocess access control.
# <p>
# <i>Also note</i> that, due to flock() restrictions on some
# platforms, the type of lock is determined by the protection flags
# with which the mmap'ed region was created: if only PROT_READ,
# then shared access is used; otherwise, an exclusive lock is used.
#*/
sub lock {
	my ($self, $offset, $len) = @_;

	my $fh = $self->{_fh};
	my $mode = ($self->{_access} & PROT_READ) ? LOCK_SH : LOCK_EX;
	return flock($fh, $mode);
}

#/**
# Unlocks the mmap'ed region. Implemented using flock()
# on the mmap()'ed file.
#*/
sub unlock {
	my ($self, $offset, $len) = @_;

	my $fh = $self->{_fh};
	return flock($fh, LOCK_UN);
}
#/**
# Unmap the mmap()ed region.
# <p>
# <b>CAUTION!!!</b> Use of this method is discouraged and
# deprecated. Unmapping from the file in one thread
# can cause segmentation in faults in other threads,
# so best practice is to just leave the mmap() in place
# and let process rundown clean things up.
#
# @deprecated
#*/
sub close {
	my $self = shift;
	_munmap($self->{_addr}, $self->{_maxlen})
		if $self->{_addr};
	CORE::close $self->{_fh} if $self->{_fh};
}
#
#	unmap and close the file
#	NOTE: do we need a ref count for multithreaded environments ?
#
sub oldDESTROY {
	my $self = shift;
print STDERR "IPC::Mmap::DESTROY: addr is $self->{_addr} len $self->{_maxlen}\n";
	_munmap($self->{_addr}, $self->{_maxlen})
		if $self->{_addr};
	CORE::close $self->{_fh} if $self->{_fh};
}

1;
