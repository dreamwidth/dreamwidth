# t/cleaner-forms.t
#
# Test LJ::CleanHTML::clean_event with forms input
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

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

my $post;
my $clean = sub {
    LJ::CleanHTML::clean_event(\$post);
};

# plain form
$post = "<form><input name='foo' value='plain'></form>";
$clean->();
ok($post =~ /<input/, "has input");

# password input
$post = "<form><input name='foo' type='password'></form>";
$clean->();
ok($post !~ /password/, "can't do password element");

$post = "<form><input name='foo' type='PASSWORD'></form>";
$clean->();
ok($post !~ /PASSWORD/, "can't do password element in uppercase");

# other types
$post = "<form><input name='foo' type='foobar'></form>";
$clean->();
ok($post =~ /foobar/, "can do foobar type");

# bad types
$post = "<form><input name='foo' type='some space'></form>";
$clean->();
ok($post !~ /some space/, "can't do spaces in input type");

# password input
$post = "raw: <input name='foo' type='this_is_raw'> end";
$clean->();
ok($post !~ /this_is_raw/, "can't do bare input");



