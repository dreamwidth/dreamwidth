#!/usr/bin/perl
#
# t/plack-customize-mutations.t
#
# Per-widget mutation contracts for the customize page's option groups.
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
use HTML::Form;
use Plack::Test;
use URI;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

plan skip_all => 'Customization integration requires a development server'
    unless $LJ::IS_DEV_SERVER;
my $public = LJ::S2::get_public_layers();
plan skip_all => 'Install the ciel/indil S2 theme for customization integration tests'
    unless $public->{'ciel/indil'};
local $LJ::DEFAULT_STYLE = { core => 'core2', layout => 'ciel/layout', theme => 'ciel/indil' };
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'customizeMutation';
my $owner    = temp_user();
my $comm     = temp_comm();
my $stranger = temp_user();
LJ::set_rel( $comm, $owner, 'A' );

sub query_for {
    my ($target) = @_;
    return '?as=' . $owner->user . '&authas=' . $target->user;
}

sub token_for {
    my ($content) = @_;
    my ($token)   = $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    ok( $token, 'rendered form supplies a CSRF token' );
    return $token;
}

sub current_theme_key {
    my ($target) = @_;
    my $theme = LJ::Customize->get_current_theme( LJ::load_user( $target->user, 'force' ) );
    return join ':', $theme->layoutid || 0, $theme->themeid || 0;
}

sub form_value {
    my ( $form, $name ) = @_;
    my ($input) = grep { defined $_->name && $_->name eq $name } $form->inputs;
    return $input ? $input->value : undef;
}

sub forms_from {
    my ($content) = @_;
    return HTML::Form->parse( $content, URI->new('http://customize.test/') );
}

test_psgi $app, sub {
    my $cb = shift;

    for my $target ( $owner, $comm ) {
        my $query = query_for($target);
        my $root  = '/customize/' . $query;
        my $opts  = '/customize/options' . $query;
        my $res   = $cb->( GET $root . '&cat=all&show=all' );
        is( $res->code, 200, 'theme page renders for ' . $target->user );
        my $before_theme = current_theme_key($target);

        # Theme preview must never apply the previewed theme, distinct from
        # (and easy to conflate with) an actual apply.
        my @theme_items = $res->content =~ m{(<li class='theme-item[^>]*>.*?</li>)}gs;
        my ($theme_item) = grep { /class=["']theme-form["']/ } @theme_items;
        ok( $theme_item, 'theme chooser renders an alternate theme form' );
        my ($preview) = $theme_item =~ /href=['"]([^'"]+)['"][^>]*class=['"]theme-preview-link/;
        ok( $preview, 'alternate theme has a preview URL' );
        $preview =~ s!^https?://[^/]+!!;
        $preview .=
            ( $preview =~ /\?/ ? '&' : '?' ) . 'as=' . $owner->user . '&authas=' . $target->user;
        my $preview_res = $cb->( GET $preview );
        ok( $preview_res->is_redirect, 'theme preview redirects to a preview style' );
        my ($preview_styleid) = ( $preview_res->header('Location') || '' ) =~ /[?&]s2id=(\d+)/;
        ok( $preview_styleid, 'preview URL selects an S2 preview style' );
        is( current_theme_key($target), $before_theme, 'preview does not apply a theme' );

        # Representative group 1: modules, via the CustomTextModule widget --
        # a distinct widget class from the generic S2PropGroup mechanism below.
        $res = $cb->( GET $opts . '&group=modules' );
        my $module_token = token_for( $res->content );
        my $marker       = 'module marker ' . $target->user;
        $res = $cb->(
            POST $opts . '&group=modules',
            Content => [
                lj_form_auth                                       => $module_token,
                'Widget[CustomTextModule]_module_customtext_title' => $marker,
                'Widget[CustomTextModule]_module_customtext_url'   => 'https://example.invalid/'
                    . $target->user,
                'Widget[CustomTextModule]_module_customtext_content' => $marker . ' content',
            ]
        );
        is( LJ::load_user( $target->user, 'force' )->prop('customtext_title'),
            $marker, 'custom text title persists' );
        is(
            LJ::load_user( $target->user, 'force' )->prop('customtext_content'),
            $marker . ' content',
            'custom text content persists'
        );

        # Representative group 2: customcss, via the generic S2PropGroup
        # widget -- also carries the file's one CSRF-denial case.
        $res = $cb->( GET $opts . '&group=customcss' );
        my $css_token  = token_for( $res->content );
        my $css_marker = 'custom CSS marker ' . $target->user;
        $res = $cb->(
            POST $opts . '&group=customcss',
            Content => [
                lj_form_auth                     => $css_token,
                'Widget[S2PropGroup]_custom_css' => $css_marker,
            ]
        );
        my $style = LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
        my %css   = LJ::Customize->get_s2_prop_values( 'custom_css', $target, $style );
        is( $css{override}, $css_marker, 'S2 property-group custom CSS persists' );
        $res = $cb->(
            POST $opts . '&group=customcss',
            Content => [
                lj_form_auth                     => 'invalid',
                'Widget[S2PropGroup]_custom_css' => 'denied CSS',
            ]
        );
        $style = LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
        %css   = LJ::Customize->get_s2_prop_values( 'custom_css', $target, $style );
        is( $css{override}, $css_marker, 'invalid options CSRF leaves CSS unchanged' );
    }

    # Unauthorized actor: a stranger's forged POST, using the theme-apply
    # mechanism (already set up above), must not create or mutate a style.
    my $denied_before = current_theme_key($stranger);
    my $denied        = '/customize/?as=' . $owner->user . '&authas=' . $stranger->user;
    my $owner_page    = $cb->(
        GET '/customize/?as=' . $owner->user . '&authas=' . $owner->user . '&cat=all&show=all' );
    my ($denied_form) = grep {
               defined form_value( $_, 'Widget[ThemeChooser]_apply_themeid' )
            && defined form_value( $_, 'Widget[ThemeChooser]_apply_layoutid' )
            && defined form_value( $_, 'Widget[ThemeChooser]_action_apply' )
            && defined form_value( $_, 'lj_form_auth' )
    } forms_from( $owner_page->content );
    ok( $denied_form, 'unauthorized request uses a rendered valid alternate theme form' );
    my $owner_token     = form_value( $denied_form, 'lj_form_auth' );
    my $denied_themeid  = form_value( $denied_form, 'Widget[ThemeChooser]_apply_themeid' );
    my $denied_layoutid = form_value( $denied_form, 'Widget[ThemeChooser]_apply_layoutid' );
    ok( $owner_token,             'unauthorized alternate form has a valid owner CSRF token' );
    ok( defined $denied_layoutid, 'unauthorized alternate form has a valid layout ID' );
    my $res = $cb->(
        POST $denied,
        Content => [
            lj_form_auth                          => $owner_token,
            'Widget[ThemeChooser]_apply_themeid'  => $denied_themeid,
            'Widget[ThemeChooser]_apply_layoutid' => $denied_layoutid,
            'Widget[ThemeChooser]_action_apply'   => 'Apply',
        ]
    );
    is( current_theme_key($stranger),
        $denied_before, 'unauthorized actor cannot create or mutate a style' );
};

done_testing;
