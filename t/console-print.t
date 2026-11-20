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

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Protocol;
use LJ::User;
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
            <li\ class='alert-box\ secondary'><strong>Info:</strong>
                <div\ class='console-response-text'>[^<]+</div></li>\s*
            <li\ class='alert-box\ success'><strong>Success:</strong>
                <div\ class='console-response-text'>\Q$escaped_arg\E</div></li>\s*
            <li\ class='alert-box\ alert'><strong>Error:</strong>
                <div\ class='console-response-text'>!failed</div></li>\s*
            </ul>
        }x,
        'the list preserves response order, distinguishes statuses, and escapes output'
    );
    unlike( $html, qr{<example\b|<table\b|\bstyle=}, 'no injected tags or legacy presentation' );
};

LJ::set_remote(
    LJ::User->new_from_row( { userid => 1, user => 'console_tester', statusvis => 'V' } ) );

subtest 'unknown commands use the same HTML and escape their name once' => sub {
    my $html = LJ::Console->run_commands_html('<unknown& sample');
    like(
        $html,
        qr{<h2\b[^>]*><code><strong>&lt;unknown&amp;</strong> sample</code></h2>},
        'the heading shows the submitted command name as text'
    );
    like(
        $html,
        qr{<li class='alert-box alert'>[^\n]*There is no such command &#39;&lt;unknown&amp;&#39;\.},
        'the error also shows the literal command name, not entity codes'
    );
};

subtest 'unknown commands retain legacy text and protocol output' => sub {
    local $LJ::T_NO_COMMAND_PRINT = 0;
    my $input = '<unknown& sample';
    my $error = "There is no such command '&lt;unknown&amp;'.";
    is( $run->($input), "&lt;unknown&amp; sample\nerror: $error", 'plain-text output' );

    my $protocol_error;
    my $result =
        LJ::Protocol::do_request( 'consolecommand', { commands => [$input] }, \$protocol_error );
    is_deeply( $result->{results}[0]{output}, [ [ error => $error ] ], 'XML-RPC command output' );

    my %flat;
    LJ::consolecommand( { command => $input }, \%flat );
    is( $flat{cmd_line_1_type}, 'error', 'flat protocol status' );
    is( $flat{cmd_line_1},      $error,  'flat protocol output' );
};
