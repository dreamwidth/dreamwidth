# t/cleaner-tables.t
#
# Test LJ::CleanHTML::clean_event with tables.
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

use Test::More tests => 9;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

my $orig_post;
my $clean_post;

my $clean = sub {
    $clean_post = $orig_post;
    LJ::CleanHTML::clean_event(\$clean_post, {tablecheck => 1});
};

# VALID: standard table
$orig_post = "<table><tr><td>Cell 1</td><td>Cell 2</td></tr><tr><td>Cell 3</td><td>Cell 4</td></tr></table>";
$clean->();
ok($orig_post eq $clean_post, "Table okay if all tags are closed");

# VALID: table without closing tr/td tags
$orig_post = "<table><tr><td>Cell 1<td>Cell 2<tr><td>Cell 3<td>Cell 4</table>";
$clean->();
ok($orig_post eq $clean_post, "Table okay if td and tr tags aren't closed");

# INVALID: table without opening table tag, should escape all tags
$orig_post = "<tr><td>Cell 1</td><td>Cell 2</td></tr><tr><td>Cell 3</td><td>Cell 4</td></tr></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<td></td></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<tr></tr></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<td></td>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<tr></tr>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

# INVALID: table without opening tr tags, should escape all td tags
$orig_post = "<table><td>Cell 1</td><td>Cell 2</td><td>Cell 3</td><td>Cell 4</td></table>";
$clean->();
ok($clean_post !~ '<td' && $clean_post =~ '<table', "All td tags escaped");

$orig_post = "<table><tbody><tr><td>foo</td></tr></table>";
$clean->();
ok($clean_post eq "<table><tbody><tr><td>foo</td></tr></table>"
   || $clean_post eq  "<table><tbody><tr><td>foo</td></tr></tbody></table>", "Fixed tbody -- optional");
