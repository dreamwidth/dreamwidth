package LJ::Directory::SetHandle::UpdateTime;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ($class, $unixtime) = @_;
    return bless {
        since => $unixtime,
    }, $class;
}

sub filter_search {
    my $sh = shift;
    LJ::UserSearch::isect_updatetime_gte($sh->{since});
}

1;
