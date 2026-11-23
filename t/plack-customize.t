#!/usr/bin/perl
#
# t/plack-customize.t
#
# Customize page target and style-ownership contracts.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
my $u    = temp_user();
my $comm = temp_comm();
LJ::set_rel( $comm, $u, 'A' );

sub form_token {
    my ($content) = @_;
    my ($token)   = $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return $token;
}

sub current_theme_key {
    my ($target) = @_;
    my $theme = LJ::Customize->get_current_theme( LJ::load_user( $target->user, 'force' ) );
    return join ':', $theme->layoutid || 0, $theme->themeid || 0;
}

test_psgi $app, sub {
    my $cb = shift;

    my $comm_url = '/customize/?as=' . $u->user . '&authas=' . $comm->user;
    my $res      = $cb->( GET $comm_url );
    my $token    = form_token( $res->content );
    $res = $cb->( POST $comm_url, Content => [ nextpage => 1, lj_form_auth => $token ] );
    like(
        $res->header('Location') || '',
        qr{/customize/options.*authas=},
        'next page keeps the community as the target'
    );

    # Preview and apply share the theme chooser; a preview must never apply.
    my $own_url = '/customize/?as=' . $u->user . '&authas=' . $u->user;
    $res = $cb->( GET $own_url . '&cat=all&show=all' );
    my $before_theme = current_theme_key($u);
    my @theme_items  = $res->content =~ m{(<li class='theme-item[^>]*>.*?</li>)}gs;
    my ($theme_item) = grep { /class=["']theme-form["']/ } @theme_items;
    my ($preview) =
        ( $theme_item || '' ) =~ /href=['"]([^'"]+)['"][^>]*class=['"]theme-preview-link/;
    ok( $preview, 'an alternate theme has a preview URL' );
    $preview =~ s!^https?://[^/]+!!;
    $preview .= ( $preview =~ /\?/ ? '&' : '?' ) . 'as=' . $u->user . '&authas=' . $u->user;
    $res = $cb->( GET $preview );
    like( $res->header('Location') || '', qr/[?&]s2id=\d+/,
        'preview redirects to a preview style' );
    is( current_theme_key($u), $before_theme, 'preview does not apply a theme' );

    # Saving an options control creates a user layer owned by the journal.
    my $layer_options =
        '/customize/options?as=' . $u->user . '&authas=' . $u->user . '&group=customcss';
    $res = $cb->( GET $layer_options );
    $cb->(
        POST $layer_options,
        Content => [
            lj_form_auth                     => form_token( $res->content ),
            'Widget[S2PropGroup]_custom_css' => '/* ownership fixture */',
        ]
    );
    my $foreign_styleid      = LJ::load_user( $u->user, 'force' )->prop('s2_style');
    my $foreign_style        = LJ::S2::load_style($foreign_styleid);
    my $foreign_user_layerid = $foreign_style->{layer}{user};
    ok( $foreign_user_layerid, 'options save creates a user layer' );
    my $foreign_layers = join ':',
        map { $foreign_style->{layer}{$_} || 0 } qw(core layout theme user);

    # A managed community pointing at the owner's style must get its own copy
    # before any customization is written.
    $comm->set_prop( s2_style => $foreign_styleid );
    $res = $cb->( GET $comm_url );
    like( $res->content, qr/id="journaltitle"/, 'community customization page renders' );
    my $target_style = LJ::S2::load_style( LJ::load_userid( $comm->id, 1 )->prop('s2_style') );
    isnt( $target_style->{styleid}, $foreign_styleid, 'foreign style reference is replaced' );
    is( $target_style->{userid}, $comm->id, 'replacement style belongs to the community' );

    my $target_options =
        '/customize/options?as=' . $u->user . '&authas=' . $comm->user . '&group=customcss';
    $res = $cb->( GET $target_options );
    $cb->(
        POST $target_options,
        Content => [
            lj_form_auth                     => form_token( $res->content ),
            'Widget[S2PropGroup]_custom_css' => '/* repaired target layer */',
        ]
    );
    $target_style = LJ::S2::load_style( LJ::load_userid( $comm->id, 1 )->prop('s2_style') );
    my $target_user_layer = LJ::S2::load_layer( LJ::get_db_writer(), $target_style->{layer}{user} );
    is( $target_user_layer->{userid}, $comm->id, 'community options save writes its own layer' );

    $foreign_style = LJ::S2::load_style($foreign_styleid);
    is( $foreign_style->{userid}, $u->id, 'owner style ownership is unchanged' );
    is( join( ':', map { $foreign_style->{layer}{$_} || 0 } qw(core layout theme user) ),
        $foreign_layers, 'owner style layers are unchanged' );
    is( LJ::S2::load_layer( LJ::get_db_writer(), $foreign_user_layerid )->{userid},
        $u->id, 'owner user layer ownership is unchanged' );
    is( LJ::load_user( $u->user, 'force' )->prop('s2_style'),
        $foreign_styleid, 'owner keeps its style reference' );
};
done_testing;
