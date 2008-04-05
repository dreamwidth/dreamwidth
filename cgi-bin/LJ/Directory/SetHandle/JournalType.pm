package LJ::Directory::SetHandle::JournalType;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ($class, $type) = @_;
    return bless {
        type => $type,
    }, $class;
}

sub filter_search {
    my $sh = shift;
    my $num = {
        P => 0,
        I => 1,
        C => 2,
        Y => 3,
    }->{$sh->{type}};
    die "Bogus type" unless defined $num;
    LJ::UserSearch::isect_journal_type($num);
}

1;
