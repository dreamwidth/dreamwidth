package LJ::Directory::Constraint::UpdateTime;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

use LJ::Directory::SetHandle::UpdateTime;

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{days} = delete $args{days};
    $self->{since} = delete $args{since};
    croak("unknown args") if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{ut_days};
    return $pkg->new(days => $args->{ut_days});
}

sub cached_sethandle {
    my ($self) = @_;
    return $self->sethandle;
}

sub sethandle {
    my ($self) = @_;
    return LJ::Directory::SetHandle::UpdateTime->new(int($self->{since} || 0) ||
                                                     (time() - int($self->{days} || 0) * 86400));
}

sub cache_for { 5 * 60 }

1;
