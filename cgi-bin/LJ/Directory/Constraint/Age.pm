package LJ::Directory::Constraint::Age;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

use LJ::Directory::SetHandle::Age;

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(from to);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{age_min} || $args->{age_max};

    # only want to validate age in the case where constraint is user-generated
    # (that is, we don't want/need to do this in the 'new' ctor above)
    $args->{age_min} = 14 if $args->{age_min} && $args->{age_min} < 14;
    return $pkg->new(from => int($args->{age_min} || 14),
                     to   => int($args->{age_max} || 125));
}

sub cached_sethandle {
    my ($self) = @_;
    return $self->sethandle;
}

sub sethandle {
    my ($self) = @_;
    return LJ::Directory::SetHandle::Age->new($self->{from}, $self->{to});
}

sub cache_for { 86400  }

1;
