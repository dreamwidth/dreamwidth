package LJ::Directory::SetHandle::Inline;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ($class, @set) = @_;

    my $self = {
        set => \@set,
    };

    return bless $self, $class;
}

sub new_from_string {
    my ($class, $str) = @_;
    $str =~ s/^Inline:// or die;
    return $class->new(split(',', $str));
}

sub as_string {
    my $self = shift;
    return "Inline:" . join(',', @{ $self->{set} });
}

sub set_size {
    my $self = shift;
    return scalar(@{ $self->{set} });
}

sub load_matching_uids {
    my ($self, $cb) = @_;
    $cb->(@{ $self->{set} });
}


1;
