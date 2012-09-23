# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

{
    my $test_string = qq {
<table>
<tr>
<td>
<img />
<b>hellohellohello</b>
</td>
</tr>
</table>};

    my $test_string_trunc = $test_string;
    $test_string_trunc =~ s/hellohellohello/hello/;

    is(LJ::html_trim($test_string, 10), $test_string_trunc, "Truncating with html works");
    is(LJ::html_trim("hello", 2), "he", "Truncating normal text");

    $test_string = qq {<br><input type="button" value="button">123456789<br>};
    $test_string_trunc = qq {<br /><input type="button" value="button" />123};

    is(LJ::html_trim($test_string, 3), $test_string_trunc, "Truncating with poorly-formed HTML");
}

1;

