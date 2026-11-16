# t/plack-controlstrip-style.t
#
# The control strip's "Reload page in style" links must reflect the style the
# page is actually shown in. A journal's recent page has an empty view, which
# is rendered with the viewer's journal page preference, not the entry page one.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use JSON;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# form auth for the login POST binds to a fixed browser uniq
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'ctlStripStyle01';

my $journal = temp_user();

# viewers whose entry and journal page preferences disagree
my $entry_mine = temp_user();
$entry_mine->set_prop( opt_viewentrystyle   => 'M' );
$entry_mine->set_prop( opt_viewjournalstyle => 'O' );

my $journal_mine = temp_user();
$journal_mine->set_prop( opt_viewentrystyle   => 'O' );
$journal_mine->set_prop( opt_viewjournalstyle => 'M' );

$_->set_password('controlstrip-password') foreach $entry_mine, $journal_mine;

test_psgi $app, sub {
    my $cb = shift;

    # log in through /login and return the session cookies it sets
    my $login = sub {
        my ($u)     = @_;
        my $form    = $cb->( GET 'http://localhost/login' );
        my ($token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        my $res     = $cb->(
            POST 'http://localhost/login',
            [
                user         => $u->user,
                password     => 'controlstrip-password',
                lj_form_auth => $token
            ]
        );
        my @cookies = grep { /^lj(?:mastersession|loggedin)=/ }
            map { ( split /;/ )[0] } $res->header('Set-Cookie');
        is( $res->code,      200, 'login succeeds' );
        is( scalar @cookies, 2,   'viewer is logged in' );
        return join '; ', @cookies;
    };

    # the styles offered by the control strip's reload links, for a logged-in viewer
    my $offered = sub {
        my ( $viewer, $view ) = @_;
        my $res = $cb->(
            GET 'http://localhost/__rpc_controlstrip?host=localhost&uri=/&args=&user='
                . $journal->user
                . "&view=$view",
            Cookie => $login->($viewer)
        );
        is( $res->code, 200, "control strip for view '$view' loads" );
        my $strip = decode_json( $res->content )->{control_strip} // '';
        like( $strip, qr/lj_controlstrip/, "control strip for view '$view' is shown" );
        my %styles = map { $_ => 1 } $strip =~ /[?&;]style=(mine|site|light|original)\b/g;
        return [ sort keys %styles ];
    };

    is_deeply( $offered->( $entry_mine, '' ),
        [qw( light mine )], 'recent page shown in original style offers mine, not original' );
    is_deeply(
        $offered->( $entry_mine, 'entry' ),
        [qw( light original site )],
        'entry page shown in own style offers original, not mine'
    );
    is_deeply( $offered->( $journal_mine, '' ),
        [qw( light original )], 'recent page shown in own style offers original, not mine' );
};

done_testing();
