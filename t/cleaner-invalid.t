# t/cleaner-invalid.t
#
# Test LJ::CleanHTML::clean_event with valid and invalid markup.
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

use Test::More tests => 4;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

# We rely on LJ::Lang::ml
# Fake the single value we retrieve during the tests.
my $mock = Test::MockObject->new();

sub fake_lang_ml {
    my ( $code, $vars ) = @_;
    my $aopts = $vars->{'aopts'};
    if ( $code eq "cleanhtml.error.markup.extra" ) {
        return "[<strong>Error:</strong> Irreparable invalid markup ("
            . "'&lt;$aopts&gt;') in entry. Owner must fix manually. Raw contents below.]";
    }
}

$mock->fake_module(
    'LJ::Lang' => (
        ml => \&fake_lang_ml
    )
);

my $post;
my $clean_post;
my $clean = sub {
    $clean_post = $post;
    LJ::CleanHTML::clean_event( \$clean_post );
};

$post = "<b>bold text</b>";
$clean->();
is( $clean_post, $post, "Valid HTML is okay." );

$post = "<marquee><font size=\"24\"><color=\"FF0000\">blah blah";
$clean->();
is(
    $clean_post,
qq {<marquee><font size="24"></font></marquee><div class='ljparseerror'>[<strong>Error:</strong> Irreparable invalid markup ('&lt;color=&quot;ff0000&quot;&gt;') in entry. Owner must fix manually. Raw contents below.]<br /><br /><div style="width: 95%; overflow: auto">}
        . LJ::ehtml($post)
        . "</div></div>",
    "Invalid HTML is not okay."
);

my $u = LJ::Mock::temp_user();
$post = "<lj user=\"" . $u->user . "\">";
$clean->();
is( $clean_post, $u->ljuser_display, "User tag is fine." );

{
    my $u = LJ::Mock::temp_user();
    $post =
          "<lj user=\""
        . $u->user
        . "\"> and some text <marquee><font size=\"24\"><color=\"FF0000\">blah blah";
    $clean->();
    is(
        $clean_post,
        $u->ljuser_display
            . qq { and some text <marquee><font size="24"></font></marquee><div class='ljparseerror'>[<strong>Error:</strong> Irreparable invalid markup ('&lt;color=&quot;ff0000&quot;&gt;') in entry. Owner must fix manually. Raw contents below.]<br /><br /><div style="width: 95%; overflow: auto">}
            . LJ::ehtml($post)
            . "</div></div>",
        "Invalid markup with a user tag renders correctly."
    );
}

