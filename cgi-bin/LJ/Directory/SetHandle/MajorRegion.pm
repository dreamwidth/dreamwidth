package LJ::Directory::SetHandle::MajorRegion;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ($class, @ids) = @_;
    return bless {
        ids => \@ids,
    }, $class;
}

sub filter_search {
    my $sh = shift;
    my $reg = "\0" x 256;
    foreach my $id (@{ $sh->{ids} }) {
        next if $id > 255 || $id < 0;
        vec($reg, $id, 8) = 1;
    }
    LJ::UserSearch::isect_region_map($reg);
}

1;
