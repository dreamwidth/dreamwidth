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
my $s1_user  = temp_user();
$s1_user->set_prop( stylesys => 1 );
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

sub form_content {
    my ($form) = @_;
    my @content;
    for my $input ( $form->inputs ) {
        next unless defined $input->name;
        push @content, $input->name => $input->value;
    }
    return @content;
}

sub customize_form {
    my ($content) = @_;
    return grep { defined form_value( $_, 'Widget[CustomizeTheme]_reset' ) } forms_from($content);
}

sub links_key {
    my ($target) = @_;
    my $links = LJ::Links::load_linkobj( LJ::load_user( $target->user, 'force' ), 'master' );
    return join '|',
        map { join "\x1e", $_->{url} || '', $_->{title} || '', $_->{hover} || '' } @$links;
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

        my @theme_items = $res->content =~ m{(<li class='theme-item[^>]*>.*?</li>)}gs;
        my ($theme_item) = grep { /class=["']theme-form["']/ } @theme_items;
        ok( $theme_item, 'theme chooser renders an alternate theme form' );
        my ($preview) = $theme_item =~ /href=['"]([^'"]+)['"][^>]*class=['"]theme-preview-link/;
        ok( $preview, 'alternate theme has a preview URL' );
        my ($theme_form) = grep { defined form_value( $_, 'Widget[ThemeChooser]_apply_themeid' ) }
            forms_from($theme_item);
        ok( $theme_form, 'theme preview item exposes rendered apply controls' );
        my $themeid        = form_value( $theme_form, 'Widget[ThemeChooser]_apply_themeid' )  || 0;
        my $theme_layoutid = form_value( $theme_form, 'Widget[ThemeChooser]_apply_layoutid' ) || 0;
        isnt( join( ':', $theme_layoutid, $themeid ),
            $before_theme, 'rendered theme form chooses a distinct theme' );

        my $preview_theme =
            $themeid
            ? LJ::S2Theme->load_by_themeid( $themeid, $target )
            : LJ::S2Theme->load_custom_layoutid( $theme_layoutid, $target );
        ok( $preview_theme, 'preview URL identifies a loadable selected theme' );
        $preview =~ s!^https?://[^/]+!!;
        $preview .=
            ( $preview =~ /\?/ ? '&' : '?' ) . 'as=' . $owner->user . '&authas=' . $target->user;
        my $preview_res = $cb->( GET $preview );
        ok( $preview_res->is_redirect, 'theme preview redirects to a preview style' );
        my ($preview_styleid) = ( $preview_res->header('Location') || '' ) =~ /[?&]s2id=(\d+)/;
        ok( $preview_styleid, 'preview URL selects an S2 preview style' );
        my $preview_style = $preview_styleid && LJ::S2::load_style($preview_styleid);
        ok( $preview_style, 'preview redirect style is loadable' );
        is( $preview_style->{layer}{layout} || 0,
            $theme_layoutid, 'preview style has the selected theme layout layer' );
        is( $preview_style->{layer}{theme} || 0,
            $themeid, 'preview style has the selected theme layer' );
        is( current_theme_key($target), $before_theme, 'preview does not apply a theme' );

        my $theme_token = form_value( $theme_form, 'lj_form_auth' );
        ok( $theme_token, 'rendered theme form carries a CSRF token' );
        $res = $cb->(
            POST $root,
            Content => [
                lj_form_auth                          => $theme_token,
                'Widget[ThemeChooser]_apply_themeid'  => $themeid,
                'Widget[ThemeChooser]_apply_layoutid' => $theme_layoutid,
                'Widget[ThemeChooser]_action_apply' =>
                    form_value( $theme_form, 'Widget[ThemeChooser]_action_apply' ),
            ]
        );
        is( $res->code, 200, 'theme apply POST from rendered controls succeeds' );
        is(
            current_theme_key($target),
            join( ':', $theme_layoutid, $themeid ),
            'theme apply persists through the widget dispatch'
        );
        my $applied_theme = current_theme_key($target);
        my $applied_name  = $preview_theme->name;
        $res = $cb->( GET $root . '&cat=all&show=all' );
        like(
            $res->content,
            qr/<li class='theme-item selected'>.*?<h4>\Q$applied_name\E<\/h4>/s,
            'fresh theme page marks the applied theme selected'
        );
        my ($invalid_theme_form) = grep {
                   defined form_value( $_, 'Widget[ThemeChooser]_apply_themeid' )
                && defined form_value( $_, 'Widget[ThemeChooser]_apply_layoutid' )
                && defined form_value( $_, 'Widget[ThemeChooser]_action_apply' )
                && defined form_value( $_, 'lj_form_auth' )
                && join( ':',
                form_value( $_, 'Widget[ThemeChooser]_apply_layoutid' ) || 0,
                form_value( $_, 'Widget[ThemeChooser]_apply_themeid' )  || 0 ) ne $applied_theme
        } forms_from( $res->content );
        ok( $invalid_theme_form, 'theme page retains a valid distinct form for CSRF denial' );
        ok(
            form_value( $invalid_theme_form, 'lj_form_auth' ),
            'distinct denied theme form carries a CSRF token'
        );
        $res = $cb->(
            POST $root,
            Content => [
                lj_form_auth => 'invalid',
                'Widget[ThemeChooser]_apply_themeid' =>
                    form_value( $invalid_theme_form, 'Widget[ThemeChooser]_apply_themeid' ),
                'Widget[ThemeChooser]_apply_layoutid' =>
                    form_value( $invalid_theme_form, 'Widget[ThemeChooser]_apply_layoutid' ),
                'Widget[ThemeChooser]_action_apply' => 'Apply',
            ]
        );
        is( current_theme_key($target),
            $applied_theme, 'invalid CSRF cannot apply a distinct valid theme' );

        $res = $cb->( GET $opts . '&group=modules' );
        my $module_token = token_for( $res->content );
        my $marker       = 'BML module ' . $target->user;
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

        $res = $cb->( GET $opts . '&group=linkslist' );
        my $links_token = token_for( $res->content );
        my $link_marker = 'BML link ' . $target->user;
        $res = $cb->(
            POST $opts . '&group=linkslist',
            Content => [
                lj_form_auth                        => $links_token,
                'Widget[LinksList]_numlinks'        => 5,
                'Widget[LinksList]_link_1_ordernum' => 10,
                'Widget[LinksList]_link_1_url'   => 'https://example.invalid/link-' . $target->user,
                'Widget[LinksList]_link_1_title' => $link_marker,
                'Widget[LinksList]_link_1_hover' => $link_marker . ' hover',
            ]
        );
        like( links_key($target), qr/\Q$link_marker\E/, 'links list content persists' );
        $res = $cb->( GET $opts . '&group=linkslist' );
        like( $res->content, qr/\Q$link_marker\E/, 'links list reloads its saved content' );

        $res = $cb->( GET $opts . '&group=display' );
        my $display_token = token_for( $res->content );
        $res = $cb->(
            POST $opts . '&group=display',
            Content => [
                lj_form_auth                                  => $display_token,
                'Widget[MoodThemeChooser]_moodthemeid'        => 1,
                'Widget[MoodThemeChooser]_opt_forcemoodtheme' => 1,
            ]
        );
        my $fresh = LJ::load_user( $target->user, 'force' );
        is( $fresh->moodtheme,            1,   'mood theme choice persists' );
        is( $fresh->{opt_forcemoodtheme}, 'Y', 'forced mood theme persists' );

        $res = $cb->( GET $opts . '&group=display' );
        my $nav_token = token_for( $res->content );
        $res = $cb->(
            POST $opts . '&group=display',
            Content => [
                lj_form_auth                                    => $nav_token,
                'Widget[NavStripChooser]_control_strip_color'   => 'light',
                'Widget[NavStripChooser]_control_strip_custom'  => 'custom',
                'Widget[NavStripChooser]_control_strip_bgcolor' => '#112233',
            ]
        );
        $fresh = LJ::load_user( $target->user, 'force' );
        is( $fresh->prop('control_strip_color'), 'light', 'navstrip color choice persists' );
        my $style = LJ::S2::load_style( $fresh->prop('s2_style') );
        my %nav   = LJ::Customize->get_s2_prop_values( 'control_strip_bgcolor', $fresh, $style );
        is( $nav{override}, '#112233', 'navstrip custom color persists' );

        $res = $cb->( GET $opts . '&group=customcss' );
        my $css_token  = token_for( $res->content );
        my $css_marker = '/* BML custom CSS ' . $target->user . ' */';
        $res = $cb->(
            POST $opts . '&group=customcss',
            Content => [
                lj_form_auth                     => $css_token,
                'Widget[S2PropGroup]_custom_css' => $css_marker,
            ]
        );
        $style = LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
        my %css = LJ::Customize->get_s2_prop_values( 'custom_css', $target, $style );
        is( $css{override}, $css_marker, 'S2 property-group custom CSS persists' );
        $res = $cb->(
            POST $opts . '&group=customcss',
            Content => [
                lj_form_auth                     => 'invalid',
                'Widget[S2PropGroup]_custom_css' => '/* denied */',
            ]
        );
        $style = LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
        %css   = LJ::Customize->get_s2_prop_values( 'custom_css', $target, $style );
        is( $css{override}, $css_marker, 'invalid options CSRF leaves CSS unchanged' );

        $res = $cb->(
            POST $opts . '&group=customcss',
            Content => [ 'Widget[S2PropGroup]_custom_css' => '/* missing token */' ]
        );
        $style = LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
        %css   = LJ::Customize->get_s2_prop_values( 'custom_css', $target, $style );
        is( $css{override}, $css_marker, 'missing options CSRF leaves CSS unchanged' );

        # Exercise the actual rendered S2PropGroup control for every remaining
        # options family. Select lists provide their allowed values in the form,
        # so this does not manufacture a property name or an invalid value.
        for my $property_group (qw(presentation colors fonts images text modules)) {
            $res = $cb->( GET $opts . '&group=' . $property_group );
            my $form_token = token_for( $res->content );
            my ( $prop_name, $options ) = $res->content =~
                /<select[^>]+name=['"]Widget\[S2PropGroup\]_([^'"]+)['"][^>]*>(.*?)<\/select>/s;
            my @values      = $options =~ /<option[^>]+value=['"]([^'"]*)/g;
            my ($selected)  = $options =~ /<option[^>]+value=['"]([^'"]*)['"][^>]*selected/g;
            my ($new_value) = grep { !defined $selected || $_ ne $selected } @values;
            if ( !$prop_name && $property_group eq 'colors' ) {
                ($prop_name) = $res->content =~ /name=['"]Widget\[S2PropGroup\]_([^'"]+)/;
                $new_value = '#123456';
            }
            if ( !$prop_name && $property_group eq 'text' ) {
                ($prop_name) = $res->content =~ /name=['"]Widget\[S2PropGroup\]_([^'"]+)/;
                $new_value = 'BML text ' . $target->user;
            }
            ok( $prop_name,         "$property_group renders a supported S2 property control" );
            ok( defined $new_value, "$property_group offers an alternate supported value" );
            $res = $cb->(
                POST $opts . '&group=' . $property_group,
                Content => [
                    lj_form_auth                       => $form_token,
                    "Widget[S2PropGroup]_${prop_name}" => $new_value,
                ]
            );
            my $prop_target = LJ::load_user( $target->user, 'force' );
            my $prop_style  = LJ::S2::load_style( $prop_target->prop('s2_style') );
            my %saved = LJ::Customize->get_s2_prop_values( $prop_name, $prop_target, $prop_style );
            is( $saved{override}, $new_value,
                "$property_group selected value persists after a fresh load" );
            $res = $cb->( GET $opts . '&group=' . $property_group );
            like(
                $res->content,
                qr/Widget\[S2PropGroup\]_\Q$prop_name\E/,
                "$property_group reload retains its rendered control"
            );
        }

        # Reset each family through its own rendered options form. Do not submit
        # controls that are absent from the form under test.
        $res = $cb->( GET $opts . '&group=text' );
        my $text_reset_token = token_for( $res->content );
        my ($text_reset_form) = customize_form( $res->content );
        ok( $text_reset_form, 'text page renders its complete reset form' );
        my $text_reset_request = $text_reset_form->click('Widget[CustomizeTheme]_reset');
        $res = $cb->(
            POST $opts . '&group=text',
            Content_Type => 'application/x-www-form-urlencoded',
            Content      => $text_reset_request->content,
        );
        $fresh = LJ::load_user( $target->user, 'force' );
        is( $fresh->prop('customtext_title'),
            'Custom Text', 'text form reset restores custom text title' );
        $fresh->set_prop( customtext_title => $marker );
        $res = $cb->(
            POST $opts . '&group=text',
            Content => [
                'Widget[CustomizeTheme]_reset' => 1,
            ]
        );
        is( LJ::load_user( $target->user, 'force' )->prop('customtext_title'),
            $marker, 'missing text reset CSRF leaves custom text unchanged' );

        $res = $cb->( GET $opts . '&group=linkslist' );
        my $links_reset_token = token_for( $res->content );
        my ($links_reset_form) = customize_form( $res->content );
        ok( $links_reset_form, 'linkslist page renders its complete reset form' );
        my $links_reset_request = $links_reset_form->click('Widget[CustomizeTheme]_reset');
        $res = $cb->(
            POST $opts . '&group=linkslist',
            Content_Type => 'application/x-www-form-urlencoded',
            Content      => $links_reset_request->content,
        );
        unlike( links_key($target), qr/\Q$link_marker\E/,
            'linkslist form reset removes saved ordered links' );
        is( current_theme_key($target),
            $applied_theme, 'actual-form resets preserve the independently selected theme' );

        $res = $cb->( GET $root . '&cat=all&show=all' );
        my $layout_target       = LJ::load_user( $target->user, 'force' );
        my $theme_before_layout = LJ::Customize->get_current_theme($layout_target);
        my %layouts             = $theme_before_layout->layouts;
        my $layout_prop         = $theme_before_layout->layout_prop;
        my $layout_style        = LJ::S2::load_style( $layout_target->prop('s2_style') );
        my %before_layout =
            $layout_prop
            ? LJ::Customize->get_s2_prop_values( $layout_prop, $layout_target, $layout_style )
            : ();
        my $before_layout_effective =
            defined $before_layout{override}
            ? $before_layout{override}
            : $before_layout{existing};
        my @layout_forms = grep { defined form_value( $_, 'Widget[LayoutChooser]_layout_choice' ) }
            forms_from( $res->content );
        my ($layout_form) = grep {
            my $choice = form_value( $_, 'Widget[LayoutChooser]_layout_choice' );
            $layout_prop
                && defined $layouts{$choice}
                && ( !defined $before_layout_effective
                || $layouts{$choice} ne $before_layout_effective )
        } @layout_forms;
        ok( $layout_form, 'layout chooser renders a distinct layout form' );
        if ($layout_form) {
            my $layout_choice = form_value( $layout_form, 'Widget[LayoutChooser]_layout_choice' );
            my $layout_token  = form_value( $layout_form, 'lj_form_auth' );
            ok( $layout_token, 'rendered layout form carries a CSRF token' );
            for my $csrf ( undef, 'invalid' ) {
                my @content = (
                    'Widget[LayoutChooser]_layout_choice' => $layout_choice,
                    'Widget[LayoutChooser]_layout_prop' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_layout_prop' ),
                    'Widget[LayoutChooser]_show_sidebar_prop' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_show_sidebar_prop' ),
                    'Widget[LayoutChooser]_apply' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_apply' ),
                );
                unshift @content, lj_form_auth => $csrf if defined $csrf;
                $res = $cb->( POST $root, Content => \@content );
                my $unchanged_style =
                    LJ::S2::load_style( LJ::load_user( $target->user, 'force' )->prop('s2_style') );
                my %unchanged =
                    LJ::Customize->get_s2_prop_values( $layout_prop, $target, $unchanged_style );
                is(
                    defined $unchanged{override} ? $unchanged{override} : $unchanged{existing},
                    $before_layout_effective,
                    ( defined $csrf ? 'invalid' : 'missing' )
                        . ' layout CSRF leaves layout unchanged'
                );
            }
            $res = $cb->(
                POST $root,
                Content => [
                    lj_form_auth                          => $layout_token,
                    'Widget[LayoutChooser]_layout_choice' => $layout_choice,
                    'Widget[LayoutChooser]_layout_prop' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_layout_prop' ),
                    'Widget[LayoutChooser]_show_sidebar_prop' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_show_sidebar_prop' ),
                    'Widget[LayoutChooser]_apply' =>
                        form_value( $layout_form, 'Widget[LayoutChooser]_apply' ),
                ]
            );
            is( $res->code, 200, 'distinct layout selection POST succeeds' );
            $layout_target = LJ::load_user( $target->user, 'force' );
            $layout_style  = LJ::S2::load_style( $layout_target->prop('s2_style') );
            my %layout =
                LJ::Customize->get_s2_prop_values( $layout_prop, $layout_target, $layout_style );
            is(
                $layout{override},
                $layouts{$layout_choice},
                'distinct layout saves its exact layout property'
            );
            isnt( $layout{override}, $before_layout_effective,
                'layout property changed from its effective previous value' );
            my %layout_names = LJ::Customize->get_layouts;
            $res = $cb->( GET $root . '&cat=all&show=all' );
            like(
                $res->content,
qr/<li class='layout-item selected'>.*?<p class='layout-desc'>\Q$layout_names{$layout_choice}\E<\/p>/s,
                'fresh layout page marks the chosen layout selected'
            );
        }
    }

    my $s1_res = $cb->( GET '/customize/?as=' . $s1_user->user . '&authas=' . $s1_user->user );
    is( $s1_res->code, 200, 'legacy customize initializes an S1 journal' );
    is( LJ::load_user( $s1_user->user, 'force' )->prop('stylesys'),
        2, 'S1 journal is migrated to S2 on entry' );
    my $alias_res = $cb->( GET '/customize?as=' . $owner->user . '&authas=' . $owner->user );
    ok(
        $alias_res->is_success || $alias_res->is_redirect,
        'slashless customize alias remains reachable'
    );

    my $denied_before = current_theme_key($stranger);
    my $denied        = '/customize/?as=' . $owner->user . '&authas=' . $stranger->user;
    my $owner_page    = $cb->(
        GET '/customize/?as=' . $owner->user . '&authas=' . $owner->user . '&cat=all&show=all' );
    my ($denied_form) = grep {
               defined form_value( $_, 'Widget[ThemeChooser]_apply_themeid' )
            && defined form_value( $_, 'Widget[ThemeChooser]_apply_layoutid' )
            && defined form_value( $_, 'Widget[ThemeChooser]_action_apply' )
            && defined form_value( $_, 'lj_form_auth' )
            && join( ':',
            form_value( $_, 'Widget[ThemeChooser]_apply_layoutid' ) || 0,
            form_value( $_, 'Widget[ThemeChooser]_apply_themeid' )  || 0 ) ne $denied_before
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
