package LJ::Directory::Constraint::HasFriend;
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
    return undef unless ($args->{fr_user} xor $args->{fr_userid});
    return $pkg->new(user   => $args->{fr_user},
                     userid => $args->{fr_userid});
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
    return ($u->friendof_uids);
}

1;
