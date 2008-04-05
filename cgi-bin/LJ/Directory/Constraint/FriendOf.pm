package LJ::Directory::Constraint::FriendOf;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(userid user);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless ($args->{fro_user} xor $args->{fro_userid});
    return $pkg->new(user   => $args->{fro_user},
                     userid => $args->{fro_userid});
}

sub cache_for { 5 * 60 }

sub u {
    my $self = shift;
    return $self->{u} if $self->{u};
    $self->{u} = $self->{userid} ? LJ::load_userid($self->{userid})
        : LJ::load_user($self->{user});
}

sub matching_uids {
    my $self = shift;
    my $u = $self->u or return ();
    return $u->friend_uids;
}

1;
