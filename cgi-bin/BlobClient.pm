#!/usr/bin/perl
# vim:ts=4 sw=4 et:

use strict;

use BlobClient::Local;

# Note: BlobClient::Remote is now deprecated, in favor of MogileFS.

package BlobClient;

sub new {
    my ($class, $args) = @_;
    my $self = {};
    $self->{path} = $args->{path};
    $self->{path} =~ s!/$!!;
    $self->{backup_path} = $args->{backup_path};
    $self->{backup_path} =~ s!/$!!;
    bless $self, ref $class || $class;
    return $self;
}

sub _make_path {
    my ($cid, $uid, $domain, $fmt, $bid) = @_;
    die "bogus domain" unless $domain =~ /^\w{1,40}$/;
    die "bogus format" unless $fmt =~ /^\w{1,10}$/;

    sprintf("%07d", $uid) =~ /^(\d+)(\d\d\d)(\d\d\d)$/;
    my ($uid1, $uid2, $uid3) = ($1, $2, $3);

    sprintf("%04d", $bid) =~ /^(\d+)(\d\d\d)$/;
    my ($bid1, $bid2) = ($1, $2);
    return join('/', int($cid), $uid1, $uid2, $uid3, $domain, $bid1, $bid2) . ".$fmt";
}

sub make_path {
    my $self = shift;
    return $self->{path} . '/' . _make_path(@_);
}

sub make_backup_path {
    my $self = shift;
    my $path = $self->{backup_path};
    return undef unless $path; # if no backup_path, just return undef
    return $path . '/' . _make_path(@_);
}

# derived classes will override this.
sub is_dead {
    return 0;
}

1;
