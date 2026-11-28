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

use DW::SiteScheme;
use DW::Template;
use LJ::S2;
use LJ::S2Theme;
use LJ::Talk;
use LJ::Protocol;
use LJ::Tags;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $smoothness            = qr/jquery\.ui\.theme\.smoothness\.css/;
my $contextual            = qr/jquery\.contextualhover\.css/;
my $ajaxtip               = qr/jquery\.ajaxtip\.css/;
my $dark_hive             = qr/jquery\.ui\.theme\.dark-hive\.css/;
my $gradation_theme_order = qr/$smoothness.*$dark_hive/s;

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
$untagged->t_enter_comment( u => $owner );
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

    for my $skin ( 'blueshift', 'gradation-horizontal', 'lynx' ) {
        for my $path ( '/entry/new', '/entry/new?mode=simple', '/inbox/compose' ) {
            subtest "$skin autocomplete on $path" => sub {
                my $separator = $path =~ /\?/ ? '&' : '?';
                my $response  = $request->(
                    GET "http://localhost$path${separator}skin=$skin",
                    Cookie => "ljsession=$session"
                );
                is( $response->code, 200, 'widget page is available' );
                my $styles = stylesheets($response);
                like( $styles, qr{/$skin\.css}, "uses $skin" );
                like(
                    $styles,
                    qr/jquery\.ui\.autocomplete\.css/,
                    'includes the autocomplete widget'
                );
                if ( $skin eq 'blueshift' ) {
                    like( $styles, $smoothness, 'Smoothness styles Blueshift autocomplete' );
                }
                else {
                    unlike( $styles, $smoothness, 'Foundation skin styles autocomplete' );
                }
            };
        }
    }

    subtest 'inbox dialogs' => sub {
        my $response = $request->( GET '/inbox?skin=lynx', Cookie => "ljsession=$session" );
        is( $response->code, 200, 'inbox is available' );
        like( $response->content, qr/jquery\.esn\.js/,           'includes subscription controls' );
        like( $response->content, qr/jquery\.commentmanage\.js/, 'includes comment management' );
        like( $response->content, qr/jquery\.ui\.dialog\.js/,    'includes the dialog widget' );
        like( stylesheets($response), $smoothness, 'styles the inbox dialogs' );
    };

    subtest 'Gradation inbox uses Foundation resources' => sub {
        my $response =
            $request->( GET '/inbox?skin=gradation-horizontal', Cookie => "ljsession=$session" );
        is( $response->code, 200, 'inbox is available' );
        my $styles = stylesheets($response);
        like(
            $styles,
            qr{css/skins/gradation/gradation-horizontal\.css},
            'uses Foundation Gradation'
        );
        like( $styles, $smoothness, 'styles the inbox dialogs' );
        unlike( $styles, $dark_hive, 'legacy Dark Hive does not compete with the dialog theme' );
    };

    subtest 'site-skinned comment management dialog' => sub {
        my $entry_url = "$journal/" . $untagged->ditemid . '.html?style=site&skin=lynx';
        my $response  = $request->( GET $entry_url, Cookie => "ljsession=$session" );
        is( $response->code, 200, 'entry is available to its owner' );
        like( $response->content, qr{href="[^"]*/delcomment\?},  'can delete a comment' );
        like( $response->content, qr/jquery\.commentmanage\.js/, 'includes comment management' );
        like( stylesheets($response), qr{/lynx\.css}, 'uses the Lynx site skin' );
        like( stylesheets($response), $smoothness,    'styles the comment management dialog' );

        my $guest = $request->( GET $entry_url );
        is( $guest->code, 200, 'entry is available to guests' );
        unlike( stylesheets($guest), $smoothness, 'guests do not get a dialog theme' );
    };

    subtest 'subscription dialog on an unfiltered journal' => sub {
        my $response = $request->( GET "$journal/", Cookie => "ljsession=$session" );
        is( $response->code, 200, 'recent view is available when signed in' );
        like( $response->content,     qr/jquery\.esn\.js/, 'includes subscription controls' );
        like( stylesheets($response), $smoothness,         'styles the subscription dialog' );
    };

    subtest 'Gradation jQuery dialog theme precedence' => sub {
        local $LJ::BETA_FEATURES{nos2foundation} = { sitewide => 1 };
        my $site_style = 'style=site&skin=gradation-horizontal';

        subtest 'comment management' => sub {
            local $LJ::DISABLED{userpicselect} = 1;
            local $LJ::DISABLED{esn_ajax}      = 1;
            my $entry_url = "$journal/" . $untagged->ditemid . ".html?$site_style";
            my $response  = $request->( GET $entry_url, Cookie => "ljsession=$session" );
            is( $response->code, 200, 'entry is available' );
            like( $response->content, qr{href="[^"]*/delcomment\?}, 'can delete a comment' );
            like( stylesheets($response), $gradation_theme_order,
                'Dark Hive is applied after the comment management theme' );
            like( stylesheets($response), qr/$ajaxtip.*$dark_hive/s,
                'Dark Hive is applied after the comment feedback defaults' );
        };

        subtest 'subscription controls' => sub {
            my $response =
                $request->( GET "$journal/?$site_style", Cookie => "ljsession=$session" );
            is( $response->code, 200, 'recent view is available' );
            like( $response->content, qr/jquery\.esn\.js/, 'includes subscription controls' );
            like( stylesheets($response), $gradation_theme_order,
                'Dark Hive is applied after the subscription theme' );
            like( stylesheets($response), qr/$ajaxtip.*$dark_hive/s,
                'Dark Hive is applied after the subscription feedback defaults' );
        };

        subtest 'tag navigation' => sub {
            my $entry_url = "$journal/" . $tagged->ditemid . ".html?$site_style";
            my $response  = $request->( GET $entry_url );
            is( $response->code, 200, 'tagged entry is available to guests' );
            like(
                $response->content,
                qr/class="tag-text"\s+data-journal=/,
                'renders tag navigation'
            );
            like( stylesheets($response), $gradation_theme_order,
                'Dark Hive is applied after the tag navigation theme' );
        };
    };

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

    subtest 'Venture colors contextual menus and jQuery UI widgets' => sub {
        my $theme = LJ::S2Theme->load_by_uniq('venture/radiantaqua') or die 'Missing Radiant Aqua';
        my $styleid = LJ::S2::create_style( $owner, 'Venture contextual menu' )
            or die 'Could not create Venture style';
        my $layer = LJ::S2::create_layer( $owner, $theme->layoutid, 'user' )
            or die 'Could not create Venture customization';
        my $source = <<'S2';
layerinfo type = "user";
set color_entry_link = "#515151";
set color_entry_link_visited = "#525252";
set color_entry_link_hover = "#535353";
set color_entry_link_active = "#545454";
S2
        my $error;
        LJ::S2::layer_compile( $layer, \$error, { s2ref => \$source } ) or die $error;
        LJ::S2::set_style_layers(
            $owner, $styleid,
            core   => $theme->coreid,
            layout => $theme->layoutid,
            theme  => $theme->themeid,
            user   => $layer,
        ) or die 'Could not set Venture style layers';
        $owner->set_prop( s2_style => $styleid );

        my $stylesheet = "/res/$styleid/stylesheet";
        my $response   = $request->( GET "$journal/", Cookie => "ljsession=$session" );
        is( $response->code, 200, 'Venture journal is available' );
        like(
            stylesheets($response),
            qr/$contextual.*\Q$stylesheet\E/s,
            'Venture loads after the default contextual menu styles'
        );
        like(
            stylesheets($response),
            qr/$ajaxtip.*\Q$stylesheet\E/s,
            'Venture loads after the default feedback styles'
        );

        my $style = $request->( GET "$journal$stylesheet" );
        is( $style->code, 200, 'Venture stylesheet is available' );
        my $css = $style->content;
        $css =~ s{/\*.*?\*/}{}gs;
        my %rules;
        while ( $css =~ /([^{}]+)\{([^{}]*)\}/g ) {
            my ( $selectors, $declarations ) = ( $1, $2 );
            for my $selector ( split /,/, $selectors ) {
                $selector =~ s/^\s+|\s+$//g;
                $rules{$selector} .= ";$declarations";
            }
        }
        for my $scope ( '.ContextualPopup', '.ui-widget-content' ) {
            for my $expected (
                [ '',           background => '#e9e9e9' ],
                [ ' a',         color      => '#2a90a2' ],
                [ ' a:visited', color      => '#888888' ],
                [ ' a:hover',   color      => '#39b7cc' ],
                [ ' a:active',  color      => '#999999' ],
                )
            {
                my ( $suffix, $property, $color ) = @$expected;
                my $selector = "$scope$suffix";
                my @colors   = ( $rules{$selector} // '' ) =~ /;\s*\Q$property\E:\s*(#[0-9a-f]+)/gi;
                is( lc( $colors[-1] // '' ), $color, "$selector uses the Venture page $property" );
            }
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

    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );
    my $page = DW::Template->render_scheme( DW::SiteScheme->get('gradation-horizontal'), '', {} );
    like( $page, $gradation_theme_order,
        'Dark Hive is applied after the legacy icon dialog theme' );
    DW::Request->reset;
}

done_testing;
