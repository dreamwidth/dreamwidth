# t/cleaner-subject.t
#
# Test to TODO
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

use Test::More 'no_plan';    # tests => TODO;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

my $lju_sys = LJ::ljuser("system");

my $all = sub {
    my $raw = shift;
    LJ::CleanHTML::clean_subject_all( \$raw );
    return $raw;
};

is(
    $all->(
"<span class='ljuser' lj:user='burr86' style='white-space: nowrap;'><a href=''><img src='http://www.henry.lj/img/userinfo.gif' alt='[info]' width='17' height='17' style='vertical-align: bottom; border: 0;' /></a><a href='http://www.henry.lj/userinfo.bml?user=burr86'><b>burr86</b></a></span> kicks butt"
    ),
    "burr86 kicks butt",
    "only text"
);

is( $all->("This is a <b>test</b>"), "This is a test", "only text" );

my $subj = sub {
    my $raw = shift;
    LJ::CleanHTML::clean_subject( \$raw );
    return $raw;
};

# Strikeout markup in entry subjects (issue #2360).
is( $subj->("all gone! <s>milk</s>"), "all gone! <s>milk</s>", "<s> kept in subjects" );

is( $subj->("all gone! <del>milk</del>"), "all gone! <del>milk</del>", "<del> kept in subjects" );

# Archive views wrap the cleaned subject in a permalink anchor, so malformed
# strikeout must come out balanced and must not be able to close that anchor.
is( $subj->("all gone! <s>milk"), "all gone! <s>milk</s>", "unclosed <s> is closed" );

is( $subj->("all gone!</s> milk"), "all gone! milk", "stray </s> is dropped" );

is( $subj->("<s>a <b>b</s> c</b>"), "<s>a <b>b</b></s> c", "misnested <s> is rebalanced" );

is( $subj->("</a></del>x <del>y"), "x <del>y</del>", "stray closers cannot end the permalink" );

# Attributes on the new tags go through the same filtering as other tags.
is( $subj->(q{<s onmouseover="alert(1)">x</s>}), "<s>x</s>", "event handler stripped from <s>" );

is(
    $subj->(q{<del cite="javascript:alert(1)" datetime="2018-08-16">x</del>}),
    q{<del datetime="2018-08-16">x</del>},
    "script URL stripped from <del cite>"
);

# Plain-text consumers (RSS/Atom titles, email subject lines) keep the struck
# words without markup, the same as for the other allowed subject tags.
is( $all->("all gone! <s>milk</s>"), "all gone! milk", "<s> flattened in plain-text subjects" );
