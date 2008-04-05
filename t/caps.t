# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

{
    my $c;

    $c = eval { LJ::get_cap(undef, 'something_not_defined') };
    is($c, undef, "Undef returns undef");

    $c = eval { LJ::get_cap(undef, 'can_post') };
    is($c, 1, "Undef returns default");
}

1;

