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

package DW::Controller::Customize::Simple;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use LJ::Customize;

DW::Routing->register_string( '/customize',       \&index_handler, app => 1 );
DW::Routing->register_string( '/customize/',      \&index_handler, app => 1 );
DW::Routing->register_string( '/customize/index', \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/customize/options.bml', \&options_handler, app => 1 );
DW::Routing->register_string( '/customize/options',     \&options_handler, app => 1 );

sub _prepare {
    my ($rv) = @_;
    my $u = $rv->{u};

    $u->set_prop( stylesys => 2 ) unless $u->prop('stylesys') == 2;
    LJ::Customize->verify_and_load_style($u);
    LJ::Customize->migrate_current_style($u);
    return $u;
}

sub _widget_html {
    my ( $widget, $args, $headextra, $page_js_obj ) = @_;
    $$headextra .= $widget->wrapped_js( page_js_obj => $page_js_obj ) if $page_js_obj;
    $$headextra .= $widget->wrapped_js unless $page_js_obj;
    return $widget->render(%$args);
}

sub _legacy_redirect {
    my ( $r, $url ) = @_;
    $r->redirect($url);
    $r->status(302);
    return $r->res;
}

sub _common_vars {
    my ( $rv, $u, $headextra ) = @_;
    my $r = $rv->{r};
    return {
        authas_html       => $rv->{authas_html},
        widget_authas     => $r->get_args->{authas},
        community_linkbar => $u->is_community ? $u->maintainer_linkbar( 'customize', 1 ) : '',
        headextra         => $$headextra,
        u                 => $u,
    };
}

sub index_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $r = $rv->{r};
    local $LJ::ACTIVE_RES_GROUP = 'foundation';
    LJ::need_res(
        { group => 'foundation' },
        qw(js/6alib/core.js js/6alib/dom.js js/6alib/httpreq.js js/livejournal.js js/customize.js)
    );
    my $u         = _prepare($rv);
    my $get       = $r->get_args;
    my $headextra = '';
    my $errors    = [];

    if ( $r->did_post ) {
        if ( $r->post_args->{nextpage} ) {
            return error_ml('error.invalidform')
                unless LJ::check_form_auth( $r->post_args->{lj_form_auth} );
            return _legacy_redirect( $r,
                LJ::create_url( '/customize/options', keep_args => ['authas'] ) );
        }
        my %post_result = LJ::Widget->handle_post( $r->post_args,
            qw(JournalTitles ThemeChooser ThemeNav LayoutChooser) );
        return _legacy_redirect( $r, $post_result{redirect} ) if $post_result{redirect};
        $errors = LJ::Widget->errors;
    }

    my $current_theme  = LJ::Widget::CurrentTheme->new;
    my $journal_titles = LJ::Widget::JournalTitles->new;
    my $theme_nav      = LJ::Widget::ThemeNav->new;
    my $layout_chooser = LJ::Widget::LayoutChooser->new;
    my %theme_args     = map {
        $_ => ( $get->{$_} // ( $_ eq 'layoutid' ? 0 : $_ eq 'page' ? 1 : $_ eq 'show' ? 12 : '' ) )
    } qw(cat layoutid designer search page show);
    my $vars = _common_vars( $rv, $u, \$headextra );
    $vars->{title} = LJ::Lang::ml(
        $u->is_community ? '/customize/index.tt.title.comm' : '/customize/index.tt.title2' );
    $vars->{current_theme} =
        _widget_html( $current_theme, { show => $theme_args{show} }, \$headextra, 'Customize' );
    $vars->{journal_titles} = _widget_html( $journal_titles, {}, \$headextra );
    $theme_args{headextra} = \$headextra;
    $vars->{theme_nav} = _widget_html( $theme_nav, \%theme_args, \$headextra, 'Customize' );
    $vars->{layout_chooser} =
        _widget_html( $layout_chooser, { headextra => \$headextra }, \$headextra, 'Customize' );
    $vars->{errors}    = $errors;
    $vars->{headextra} = $headextra;
    LJ::need_res( { priority => $LJ::OLD_RES_PRIORITY }, 'stc/customize.css' );
    LJ::need_res( { group    => 'foundation' },          'js/customize.js' );
    LJ::need_res('stc/select-list.css');
    return DW::Template->render_template( 'customize/index.tt', $vars );
}

sub options_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $r = $rv->{r};
    local $LJ::ACTIVE_RES_GROUP = 'foundation';
    LJ::need_res(
        { group => 'foundation' },
        qw(js/6alib/core.js js/6alib/dom.js js/6alib/httpreq.js js/livejournal.js js/customize.js)
    );
    my $u         = _prepare($rv);
    my $group     = $r->get_args->{group} || 'presentation';
    my $headextra = '';
    my $errors    = [];

    if ( $r->did_post ) {
        LJ::Widget->handle_post( $r->post_args,
            qw(CustomizeTheme CustomTextModule JournalTitles MoodThemeChooser NavStripChooser S2PropGroup LinksList LayoutChooser)
        );
        $errors = LJ::Widget->errors;
    }

    my $current_theme   = LJ::Widget::CurrentTheme->new;
    my $journal_titles  = LJ::Widget::JournalTitles->new;
    my $customize_theme = LJ::Widget::CustomizeTheme->new;
    my $layout_chooser  = LJ::Widget::LayoutChooser->new;
    my $vars            = _common_vars( $rv, $u, \$headextra );
    $vars->{title} = LJ::Lang::ml(
        $u->is_community ? '/customize/options.tt.title.comm' : '/customize/options.tt.title' );
    $vars->{current_theme} =
        _widget_html( $current_theme, { no_theme_chooser => 1, headextra => \$headextra },
        \$headextra, 'Customize' );
    $vars->{journal_titles} =
        _widget_html( $journal_titles, { no_theme_chooser => 1 }, \$headextra );
    $vars->{customize_theme} =
        _widget_html( $customize_theme,
        { group => $group, post => $r->post_args, headextra => \$headextra },
        \$headextra, 'Customize' );
    $vars->{layout_chooser} =
        _widget_html( $layout_chooser, { no_theme_chooser => 1, headextra => \$headextra },
        \$headextra, 'Customize' );
    $vars->{errors}    = $errors;
    $vars->{headextra} = $headextra;
    LJ::need_res( { group => 'foundation' }, 'js/customize.js' );
    LJ::need_res(qw(stc/customize.css stc/select-list.css));
    return DW::Template->render_template( 'customize/options.tt', $vars );
}

1;
