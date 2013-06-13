# t/htmltrim.t
#
# Test LJ::html_trim
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 3;

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
