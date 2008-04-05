package LJ::Widget::TagCloud;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {()}

# pass in tags => [$tag1, $tag2, ...]
# tags are of the form { tagname => { url => $url, value => $value } }
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $tagsref = delete $opts{tags};

    return '' unless $tagsref;

    return LJ::tag_cloud($tagsref, \%opts);
}

1;
