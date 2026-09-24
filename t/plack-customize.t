# Baseline contracts for the pending customization-page migration.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

# This integration test uses the devcontainer database with compiled themes.
# All users and styles created below belong to temporary, cleaned-up users.
plan skip_all => 'Customization integration requires a development server'
    unless $LJ::IS_DEV_SERVER;
my $public = LJ::S2::get_public_layers();
plan skip_all => 'Install the ciel/indil S2 theme for customization integration tests'
    unless $public->{'ciel/indil'};
local $LJ::DEFAULT_STYLE = { core => 'core2', layout => 'ciel/layout', theme => 'ciel/indil' };
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'customizeBaseline';
my $u        = temp_user();
my $stranger = temp_user();
my $comm     = temp_comm();
LJ::set_rel( $comm, $u, 'A' );
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET '/customize/' );
    unlike( $res->content, qr/id="journaltitle"/, 'anonymous has no customization controls' );
    for my $target ( $u, $comm ) {
        my $query = '?as=' . $u->user . '&authas=' . $target->user;
        my $url   = '/customize/' . $query;
        $res = $cb->( GET $url);
        is( $res->code, 200, 'authorized personal/community theme browser' );
        like( $res->content, qr/id="journaltitle"/, 'title widget renders' );
        is( $target->prop('stylesys'), 2, 'S2 enabled' );
        for my $alias (qw(/customize /customize/ /customize/index /customize/index.bml)) {
            my $alias_res = $cb->( GET $alias . $query );
            is( $alias_res->code, 200, "$alias legacy index alias renders" );
            like( $alias_res->content, qr/id="journaltitle"/,
                "$alias retains customization controls" );
            my ($alias_token) =
                $alias_res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            my $alias_title = 'Alias ' . $alias . ' ' . $target->user;
            $alias_res = $cb->(
                POST $alias . $query,
                Content => [
                    lj_form_auth                        => $alias_token,
                    'Widget[JournalTitles]_which_title' => 'journaltitle',
                    'Widget[JournalTitles]_title_value' => $alias_title,
                ]
            );
            is( LJ::load_userid( $target->id )->prop('journaltitle'),
                $alias_title, "$alias POST retains widget body dispatch" );
        }
        my $style = LJ::S2::load_style( $target->prop('s2_style') );
        is( $style->{userid}, $target->id, 'style belongs to effective user' );
        my ($token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'form token available' );
        $res = $cb->( POST $url, Content => [ nextpage => 1, lj_form_auth => $token ] );
        like( $res->header('Location'), qr{/customize/options}, 'next-page redirect' );
        like( $res->header('Location'), qr/authas=/,            'community identity retained' )
            if $target->is_community;
        $res = $cb->( POST $url, Content => [ nextpage => 1, lj_form_auth => 'invalid' ] );
        ok( !$res->header('Location'), 'invalid next-page token does not redirect' );

        my $theme_nav_url = $url . '&page=2&show=24';
        $res = $cb->( GET $theme_nav_url );
        my ($theme_nav_token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        $res = $cb->(
            POST $theme_nav_url,
            Content => [
                lj_form_auth              => $theme_nav_token,
                'Widget[ThemeNav]_search' => 'encoded search',
            ]
        );
        is( $res->code, 302, 'ThemeNav POST produces a real redirect response' );
        is(
            $res->header('Location'),
            "$LJ::SITEROOT/customize/?search=encoded+search&authas=" . $target->user . '&show=24',
            'ThemeNav redirect carries authas and show through the BML page'
        );
        $res = $cb->(
            POST $theme_nav_url,
            Content => [
                lj_form_auth              => 'invalid',
                'Widget[ThemeNav]_search' => 'denied search',
            ]
        );
        ok( !$res->header('Location'), 'invalid ThemeNav token does not redirect' );

        for my $path ( '/customize/', '/customize/options', '/customize/options.bml' ) {
            $res = $cb->( GET $path . $query );
            my ($page_token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            my $title = 'Characterized ' . $path . ' ' . $target->user;
            $res = $cb->(
                POST $path . $query,
                Content => [
                    lj_form_auth                        => $page_token,
                    'Widget[JournalTitles]_which_title' => 'journaltitle',
                    'Widget[JournalTitles]_title_value' => $title,
                ]
            );
            is( LJ::load_userid( $target->id )->prop('journaltitle'),
                $title, 'title persists through page widget dispatch' );
            unlike(
                $res->content,
                qr/(?:LJ::Error::DieObject|ARRAY\()/,
                'successful widget POST has no object-pointer error banner'
            );
            $res = $cb->(
                POST $path . $query,
                Content => [
                    lj_form_auth                        => 'invalid',
                    'Widget[JournalTitles]_which_title' => 'journaltitle',
                    'Widget[JournalTitles]_title_value' => 'Denied title',
                ]
            );
            is( LJ::load_userid( $target->id )->prop('journaltitle'),
                $title, 'invalid token cannot change title' );
            like( $res->content, qr/Invalid form/i, 'invalid widget token shows its error message' )
                if $path eq '/customize/';
            unlike(
                $res->content,
                qr/(?:LJ::Error::DieObject|ARRAY\()/,
                'invalid widget token has no object-pointer error banner'
            );
        }
        for my $group (qw(presentation colors fonts images text modules customcss display)) {
            $res = $cb->( GET '/customize/options' . $query . '&group=' . $group );
            is( $res->code, 200, "$group options render" );
            unlike( $res->content, qr/\[Error:|BML ERROR|Invalid user\./, 'no rendering failure' );
        }
    }

    # A formerly generated current-style name must be renamed only on the
    # effective journal when the controller prepares the customization page.
    my $migration_url = '/customize/?as=' . $u->user . '&authas=' . $u->user;
    $res = $cb->( GET $migration_url );
    my $migration_style = LJ::S2::load_style( $u->prop('s2_style') );
    my $migration_theme = LJ::Customize->get_current_theme($u);
    my $old_name        = $migration_theme->old_style_name_for_theme;
    my $new_name        = $migration_theme->new_style_name_for_theme;
    isnt( $old_name, $new_name, 'fixture theme has distinct legacy and current style names' );
    LJ::S2::rename_user_style( $u, $migration_style->{styleid}, $old_name );
    is( LJ::S2::load_style( $migration_style->{styleid}, skip_layer_load => 1 )->{name},
        $old_name, 'fixture has the stale current-style name' );
    $res = $cb->( GET $migration_url );
    is( $res->code, 200, 'style-name migration page renders' );
    is( LJ::S2::load_style( $u->prop('s2_style'), skip_layer_load => 1 )->{name},
        $new_name, 'prepare migrates the stale current-style name on a fresh load' );

    # Saving a real options control creates a nonzero user layer for the
    # effective journal; ownership must remain journal-local.
    my $layer_options =
        '/customize/options?as=' . $u->user . '&authas=' . $u->user . '&group=customcss';
    $res = $cb->( GET $layer_options );
    my ($layer_token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    $res = $cb->(
        POST $layer_options,
        Content => [
            lj_form_auth                     => $layer_token,
            'Widget[S2PropGroup]_custom_css' => '/* ownership fixture */',
        ]
    );
    my $layer_style = LJ::S2::load_style( LJ::load_user( $u->user, 'force' )->prop('s2_style') );
    my $foreign_user_layerid = $layer_style->{layer}{user};
    ok( $foreign_user_layerid, 'real options save creates a nonzero foreign user layer' );
    my $foreign_user_layer = LJ::S2::load_layer( LJ::get_db_writer(), $foreign_user_layerid );
    is( $foreign_user_layer->{userid}, $u->id,
        'foreign nonzero user layer belongs to its journal' );

    # Reuse the already-authorized owner/community relationship: the controller
    # must repair a managed community pointing at the owner's foreign style.
    my $foreign_styleid = $u->prop('s2_style');
    my $foreign_style   = LJ::S2::load_style($foreign_styleid);
    my $foreign_name    = $foreign_style->{name};
    my $foreign_layers  = join ':',
        map { $foreign_style->{layer}{$_} || 0 } qw(core layout theme user);
    is( $foreign_style->{layer}{user},
        $foreign_user_layerid, 'foreign style carries the nonzero foreign user layer' );
    $comm->set_prop( s2_style => $foreign_styleid );
    my $foreign_target_url = '/customize/?as=' . $u->user . '&authas=' . $comm->user;
    $res = $cb->( GET $foreign_target_url );
    is( $res->code, 200, 'managed foreign-style target customization page renders' );
    like( $res->content, qr/id="journaltitle"/,
        'managed foreign-style request reaches customization controls' );
    my $fresh_comm   = LJ::load_userid( $comm->id, 1 );
    my $target_style = LJ::S2::load_style( $fresh_comm->prop('s2_style') );
    isnt( $target_style->{styleid}, $foreign_styleid, 'foreign style reference is replaced' );
    is( $target_style->{userid}, $comm->id, 'replacement style belongs to effective target' );
    my $target_options =
        '/customize/options?as=' . $u->user . '&authas=' . $comm->user . '&group=customcss';
    $res = $cb->( GET $target_options );
    my ($target_layer_token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    $res = $cb->(
        POST $target_options,
        Content => [
            lj_form_auth                     => $target_layer_token,
            'Widget[S2PropGroup]_custom_css' => '/* repaired target layer */',
        ]
    );
    $fresh_comm   = LJ::load_userid( $comm->id, 1 );
    $target_style = LJ::S2::load_style( $fresh_comm->prop('s2_style') );
    my $target_user_layer = LJ::S2::load_layer( LJ::get_db_writer(), $target_style->{layer}{user} );
    ok( $target_style->{layer}{user},
        'repaired effective target has a nonzero user layer after options save' );
    is( $target_user_layer->{userid},
        $comm->id, 'repaired effective target user layer belongs to the community' );
    $foreign_style = LJ::S2::load_style($foreign_styleid);
    is( $foreign_style->{userid}, $u->id,        'foreign style ownership remains unchanged' );
    is( $foreign_style->{name},   $foreign_name, 'foreign style name remains unchanged' );
    is( join( ':', map { $foreign_style->{layer}{$_} || 0 } qw(core layout theme user) ),
        $foreign_layers, 'foreign style layer state remains unchanged' );
    $foreign_user_layer = LJ::S2::load_layer( LJ::get_db_writer(), $foreign_user_layerid );
    is( $foreign_user_layer->{userid},
        $u->id, 'foreign nonzero user layer ownership remains unchanged' );
    is( LJ::load_user( $u->user, 'force' )->prop('s2_style'),
        $foreign_styleid, 'foreign journal retains its style reference after target repair' );

    $res = $cb->( GET '/customize/?as=' . $u->user . '&authas=' . $stranger->user );
    unlike( $res->content, qr/id="journaltitle"/, 'unmanaged user denied' );
    ok( !$stranger->prop('s2_style'), 'denied access does not create a style' );
};
done_testing;
