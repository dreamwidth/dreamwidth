package LJ::Directory::Constraint::JournalType;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

use LJ::Directory::SetHandle::JournalType;

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(journaltype);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{journaltype}
        && $args->{journaltype} =~ /^\w$/;
    return $pkg->new(journaltype => $args->{journaltype});
}

sub cache_for { 86400 }

sub cached_sethandle {
    my ($self) = @_;
    return $self->sethandle;
}

sub sethandle {
    my ($self) = @_;
    return LJ::Directory::SetHandle::JournalType->new($self->{journaltype});
}

1;
