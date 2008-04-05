package LJ::Widget::GeoSearchLocation;

use strict;
use base qw(LJ::Widget::Location);

sub render_body {
    my $class = shift;
    my %opts = (
        'skip_zip' => 1,
        'skip_timezone' => 1,
        @_
    );
    return $class->SUPER::render_body(%opts);
}

# do not call handle_post() of base class here
sub handle_post {
}

1;