#!/usr/bin/perl
#
# DW::Locker
#
# Named advisory locks backed by MySQL GET_LOCK(), with a hard-link file-lock
# fallback for environments without MySQL (e.g. SQLite-backed tests).  Replaces
# the inherited ddlockd daemon and DDLockClient.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Locker;
use strict;
use warnings;

use Digest::MD5 qw( md5_hex );

our $Error;

# (CONSTRUCTOR) new( %args )
#   backend => 'auto' (default), 'mysql', or 'file'
#   lockdir => directory for the file backend (defaults to $LJ::LOCKDIR)
sub new {
    my ( $class, %args ) = @_;
    my $self = bless {}, ( ref $class || $class );
    $self->{backend} = $args{backend} || 'auto';
    $self->{lockdir} = $args{lockdir} || $LJ::LOCKDIR || "$LJ::HOME/locks";
    $self->{lock_dbh} = undef;
    return $self;
}

# trylock( $name ) -> DW::Lock on success, undef (and sets $Error) on failure
sub trylock {
    my ( $self, $name ) = @_;
    $Error = undef;

    my $backend = $self->{backend};
    if ( $backend eq 'auto' ) {
        my $dbh = $self->_lock_dbh;
        $backend = ( $dbh && $dbh->{Driver}{Name} eq 'mysql' ) ? 'mysql' : 'file';
    }

    return $backend eq 'mysql'
        ? $self->_trylock_mysql($name)
        : $self->_trylock_file($name);
}

sub _trylock_file {
    my ( $self, $name ) = @_;

    my $lock = eval { DW::Lock->_new_file( $name, $self->{lockdir} ) };
    return $lock if $lock;

    $Error = $@ || "lock taken";
    return undef;
}

sub _trylock_mysql {
    my ( $self, $name ) = @_;

    my $dbh = $self->_lock_dbh
        or do { $Error = "no lock database available"; return undef; };

    my $lockname = $self->_lockname($name);
    my ($got) = $dbh->selectrow_array( "SELECT GET_LOCK(?, 0)", undef, $lockname );

    # 1 = acquired, 0 = currently held elsewhere, undef = error/killed
    unless ($got) {
        $Error = defined $got ? "lock taken" : "GET_LOCK error: " . ( $dbh->errstr || "?" );
        return undef;
    }

    return DW::Lock->_new_mysql( $dbh, $lockname );
}

# A dedicated, uncached master connection used only for locks.  GET_LOCK is
# session-scoped, so isolating it from the query pool keeps locks from being
# disturbed by ordinary traffic; auto-reconnect is forced off so a dropped
# connection (which already auto-released its locks) surfaces as an error
# rather than silently reconnecting into a lock-free session; and wait_timeout
# is raised so a long, idle hold (e.g. a multi-minute ljmaint task) is not
# closed out from under us and the lock released early.
sub _lock_dbh {
    my $self = shift;

    my $dbh = $self->{lock_dbh};
    return $dbh if $dbh && eval { $dbh->ping };

    # LJ::get_dbh can throw (not just return undef) under $LJ::THROW_ERRORS or
    # $LJ::DISABLE_MASTER; these locks are best-effort, so degrade to undef.
    $dbh = eval { LJ::get_dbh( { unshared => 1 }, "master" ) }
        or return undef;

    if ( $dbh->{Driver}{Name} eq 'mysql' ) {
        $dbh->{mysql_auto_reconnect} = 0;
        eval { $dbh->do("SET SESSION wait_timeout = 2147483") };
    }

    return $self->{lock_dbh} = $dbh;
}

# Map an arbitrary caller name to a valid GET_LOCK name: prefix "dwl:" so it can
# never collide with LJ::DB::get_lock names, and stay within MySQL's 64-char
# limit by hashing anything too long (caller names are usually short and stay
# readable in SHOW PROCESSLIST / performance_schema.metadata_locks).
sub _lockname {
    my ( $self, $name ) = @_;
    my $key = "dwl:$name";
    return $key if length($key) <= 64 && $key !~ /[^\x20-\x7e]/;
    return "dwl:" . md5_hex($name);    # 4 + 32 = 36 chars
}

#####################################################################
package DW::Lock;
use strict;
use warnings;

use Fcntl qw( :DEFAULT :flock );
use File::Spec ();
use File::Path qw( mkpath );
use IO::File ();

# _new_mysql( $dbh, $lockname ) -- wrap a GET_LOCK already held on $dbh.  Holds
# a strong reference to the dedicated connection so the lock stays alive (the
# connection stays open) for as long as this object exists.
sub _new_mysql {
    my ( $class, $dbh, $lockname ) = @_;
    return bless {
        backend  => 'mysql',
        pid      => $$,
        dbh      => $dbh,
        lockname => $lockname,
    }, $class;
}

# _new_file( $name, $lockdir ) -- atomic hard-link lock; dies if already held.
sub _new_file {
    my ( $class, $name, $lockdir ) = @_;
    my $self = bless { backend => 'file', pid => $$ }, $class;

    mkpath $lockdir unless -d $lockdir;

    my $lockfile = File::Spec->catfile( $lockdir, _eurl($name) );
    my $tmpfile  = "$lockfile.$$.tmp";
    unlink $tmpfile if -e $tmpfile;

    my $fh = IO::File->new( $tmpfile, O_WRONLY | O_CREAT | O_EXCL )
        or die "open: $tmpfile: $!";
    $fh->close;

    link( $tmpfile, $lockfile )
        or do { unlink $tmpfile; die "link: $tmpfile -> $lockfile: $!"; };
    unlink $tmpfile;

    $self->{path} = $lockfile;
    return $self;
}

sub release {
    my $self = shift;

    if ( $self->{backend} eq 'mysql' ) {
        return unless $self->{dbh} && $self->{lockname};
        my ( $dbh, $lockname ) = ( delete $self->{dbh}, delete $self->{lockname} );
        eval { $dbh->do( "SELECT RELEASE_LOCK(?)", undef, $lockname ) };
    }
    elsif ( $self->{backend} eq 'file' ) {
        return unless $self->{path};
        unlink delete $self->{path};
    }
    return 1;
}

sub DESTROY {
    my $self = shift;
    $self->release if $$ == $self->{pid};
}

# URL-encode a name for use as a lock filename.
sub _eurl {
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_,.\\: -])/sprintf( "%%%02X", ord($1) )/eg;
    $a =~ tr/ /+/;
    return $a;
}

1;
