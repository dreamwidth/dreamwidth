#!/usr/bin/perl
# t/contextual-hover-resources.t
#
# Checks the stylesheets delivered for contextual menus and icon dialogs.
#
# Authors:
#      saphid <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use File::Temp qw(tempdir);
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Talk;
use LJ::Protocol;
use LJ::Tags;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $smoothness = qr/jquery\.ui\.theme\.smoothness\.css/;
my $contextual = qr/jquery\.contextualhover\.css/;
my $ajaxtip    = qr/jquery\.ajaxtip\.css/;

local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );
my $owner = temp_user();
$owner->update_self( { status => 'A', statusvis => 'V' } );
$owner->set_prop( use_journalstyle_entry_page => 'Y' );
my $untagged = $owner->t_post_fake_entry( body => 'A guest can read this untagged entry.' );
my $tagged   = $owner->t_post_fake_entry( body => 'A guest can read this tagged entry.' );

END {
    LJ::delete_entry( $owner, $_->jitemid, 0, $_->anum )
        for grep { defined } ( $untagged, $tagged );
}
LJ::Tags::update_logtags( $owner, $tagged->jitemid,
    { set_string => 'resource-test', remote => $owner } )
    or die 'Could not tag entry';
my $journal = 'http://localhost/users/' . $owner->user;

my $session = do {
    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );
    my $error;
    my $result =
        LJ::Protocol::do_request( 'sessiongenerate',
        { username => $owner->user, expiration => 'short' },
        \$error, { noauth => 1 } );
    DW::Request->reset;
    $result->{ljsession} or die "sessiongenerate: $error";
};

test_psgi $app, sub {
    my $request = shift;
    for my $skin ( 'lynx', 'gradation-horizontal', 'blueshift' ) {
        subtest "$skin contextual menu" => sub {
            my $response = $request->( GET "/manage/settings/?cat=display&skin=$skin" );
            is( $response->code, 200, 'settings page is available' );
            my $styles = stylesheets($response);
            like( $styles, qr{blueshift/blueshift\.css}, 'uses Blueshift' ) if $skin eq 'blueshift';
            like( $styles, $contextual, 'ships the contextual menu stylesheet' );
            unlike( $styles, $smoothness, 'does not ship Smoothness for the menu' );
        };
    }

    for my $path ( '/entry/new', '/entry/new?mode=simple', '/inbox/compose' ) {
        subtest "Blueshift autocomplete on $path" => sub {
            my $separator = $path =~ /\?/ ? '&' : '?';
            my $response  = $request->(
                GET "http://localhost$path${separator}skin=blueshift",
                Cookie => "ljsession=$session"
            );
            is( $response->code, 200, 'widget page is available' );
            my $styles = stylesheets($response);
            like( $styles, qr{blueshift/blueshift\.css}, 'uses Blueshift' );
            like( $styles, qr/jquery\.ui\.autocomplete\.css/, 'includes the autocomplete widget' );
            like( $styles, $smoothness, 'styles the autocomplete menu and its keyboard selection' );
        };
    }

    subtest 'guest journal tooltip and tag navigation resources' => sub {
        my $untagged_page = $request->( GET "$journal/" . $untagged->ditemid . '.html' );
        is( $untagged_page->code, 200, 'untagged entry is available' );
        my $untagged_styles = stylesheets($untagged_page);
        like( $untagged_styles, qr/foundation_minimal\.css/, 'uses the journal style' );
        like( $untagged_page->content, qr/jquery\.ajaxtip\.js/,
            'includes the AJAX tooltip widget' );
        like( $untagged_styles, $ajaxtip, 'includes the independent AJAX tooltip surface' );
        unlike( $untagged_styles, $smoothness, 'guest tooltip does not need Smoothness' );

        my $tag_nav = qr/class="tag-text"\s+data-journal=/;
        my $recent  = $request->( GET "$journal/" );
        is( $recent->code, 200, 'recent view is available' );
        like( $recent->content, qr/resource-test/, 'recent view renders the tag' );
        unlike( $recent->content, $tag_nav,
            'unfiltered recent view has no tag navigation trigger' );
        unlike( stylesheets($recent), $smoothness,
            'unfiltered recent view does not need Smoothness' );

        for my $path ( '/' . $tagged->ditemid . '.html', '/?tag=resource-test' ) {
            my $response = $request->( GET "$journal$path" );
            is( $response->code, 200, "$path is available" );
            like( $response->content,     $tag_nav,    "$path renders tag navigation" );
            like( stylesheets($response), $smoothness, "$path retains the tag navigation theme" );
        }
    };
};

sub stylesheets {
    my ($response) = @_;
    return join "\n", $response->content =~ /(<link\b[^>]*rel="stylesheet"[^>]*>)/g;
}

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP = 'jquery';

    LJ::Talk::init_s2journal_js();
    my $head = LJ::res_includes( nojs => 1, no_scripttags => 1 );
    unlike( $head, $smoothness, 'the shared journal resources do not include Smoothness' );
}

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP = 'jquery';

    LJ::Talk::init_iconbrowser_js();
    my $head = LJ::res_includes( nojs => 1, no_scripttags => 1 );
    like( $head, $smoothness, 'the legacy icon dialog still gets its theme' );
}

done_testing;
