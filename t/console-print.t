# t/console-print.t
#
# Test LJ::Console print command
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
local $LJ::T_NO_COMMAND_PRINT = 1;

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is( $run->("print one"),      "info: Welcome to 'print'!\nsuccess: one" );
is( $run->("print one !two"), "info: Welcome to 'print'!\nsuccess: one\nerror: !two" );

subtest 'HTML groups each command and styles its responses by status' => sub {
    my $html   = LJ::Console->run_commands_html(qq{print "<example x='y'>&" !failed\nprint next});
    my @groups = $html =~ m{<section\b[^>]*>(.*?)</section>}gs;
    my $escaped_arg = q{&lt;example x=&#39;y&#39;&gt;&amp;};
    is( scalar @groups, 2, 'each command has its own result section' );
    like(
        $groups[0] // '',
        qr{<h2\b[^>]*><code><strong>print</strong> \Q$escaped_arg\E !failed</code></h2>},
        'the command heading escapes arguments'
    );
    like(
        $groups[0] // '',
        qr{
            <ul\b[^>]*>\s*
            <li\ class='alert-box\ secondary'><strong>[^<]+</strong>\ [^<]+</li>\s*
            <li\ class='alert-box\ success'><strong>[^<]+</strong>\ \Q$escaped_arg\E</li>\s*
            <li\ class='alert-box\ alert'><strong>[^<]+</strong>\ !failed</li>\s*
            </ul>
        }x,
        'the list preserves response order, distinguishes statuses, and escapes output'
    );
    unlike( $html, qr{<example\b|<table\b|\bstyle=}, 'no injected tags or legacy presentation' );
};

subtest 'unknown commands use the same HTML and escape their name once' => sub {
    my $command = LJ::Console->parse_array( '<unknown&', 'sample' );
    like(
        $command->as_html,
        qr{<h2\b[^>]*><code><strong>&lt;unknown&amp;</strong> sample</code></h2>},
        'the heading shows the submitted command name as text'
    );
    $command->execute( $command->args );
    my ($error) = $command->responses;
    like(
        $error->as_html,
        qr{<li class='alert-box alert'>[^\n]*&lt;unknown&amp;},
        'the error also shows the literal command name, not entity codes'
    );
};
