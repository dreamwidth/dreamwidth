package LJ::Directory::SetHandle::Age;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ($class, $from, $to) = @_;
    return bless {
        from => $from,
        to   => $to,
    }, $class;
}

sub filter_search {
    my $sh = shift;
    LJ::UserSearch::isect_age_range($sh->{from}, $sh->{to});
}

1;
