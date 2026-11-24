# t/plack-password-visibility-s2.t
#
# Verify password visibility assets on journal-styled reply pages.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use LJ::Test qw(temp_user);

plan skip_all => 'Journal reply integration requires a development server'
    unless $LJ::IS_DEV_SERVER;
my $layers = LJ::S2::get_public_layers();
plan skip_all => 'Install the ciel/indil S2 theme for journal reply integration tests'
    unless $layers->{'ciel/indil'};
local $LJ::DEFAULT_STYLE = { core => 'core2', layout => 'ciel/layout', theme => 'ciel/indil' };

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner = temp_user();
$owner->update_self( { status => 'A', opt_whocanreply => 'all' } );
$owner->set_prop( use_journalstyle_entry_page => 'Y' );
my $entry = $owner->t_post_fake_entry;
my $url   = 'http://localhost/users/' . $owner->user . '/' . $entry->ditemid . '.html?mode=reply';

test_psgi $app, sub {
    my $client = shift;
    for my $legacy ( 0, 1 ) {
        subtest $legacy ? 'legacy journal reply' : 'Foundation journal reply' => sub {
            local $LJ::BETA_FEATURES{nos2foundation} = { sitewide => $legacy };
            my $response = $client->( GET $url );
            is( $response->code, 200, 'reply page loads' );
            my $html        = $response->content;
            my ($head)      = $html =~ m{<head\b[^>]*>(.*?)</head>}is;
            my ($body)      = $html =~ m{<body\b[^>]*>(.*?)</body>}is;
            my $legacy_form = qr{<table\b[^>]*class=['"]talkform['"]};
            if ($legacy) {
                like( $body // '', $legacy_form, 'renders the legacy reply form' );
            }
            else {
                unlike( $body // '', $legacy_form, 'does not render the legacy reply form' );
            }
            like(
                $body // '',
                qr{<button\b[^>]*data-password-visibility[^>]*aria-controls="password"},
                'the reply password field has a visibility button'
            );
            ok(
                ( $head // '' ) =~
                    m{<link\b[^>]*href="[^"]*css/components/password-visibility\.css\b},
                'password visibility stylesheet is in the head'
            );
            my $scripts = $legacy ? $head : $body;
            ok(
                ( $scripts // '' ) =~
                    m{<script\b[^>]*src="[^"]*components/password-visibility\.js\b},
                $legacy ? 'visibility script is in the head' : 'visibility script is in the body'
            );
        };
    }
};

done_testing();
