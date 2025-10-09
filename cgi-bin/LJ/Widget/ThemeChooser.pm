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

package LJ::Widget::ThemeChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::S2Theme;
use LJ::Customize;

sub ajax          { 1 }
sub authas        { 1 }
sub need_res      { qw( stc/widgets/themechooser.css ) }
sub need_res_opts { priority => $LJ::OLD_RES_PRIORITY }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";
    my %cats     = LJ::Customize->get_cats($u);

    warn %opts;

    # filter criteria
    $opts{cat}      //= "";
    $opts{layoutid} //= 0;
    $opts{designer} //= "";
    $opts{search}   //= "";
    $opts{page}     //= 1;
    $opts{show}     //= 12;

    if ( $u->user ne $remote->user ) {
        $opts{authas} = $u->user;
    }

    my $cat_title;
    my @themes;
    my $current = LJ::Customize->get_current_theme($u);

    if ( $opts{cat} eq "all" ) {
        @themes    = LJ::S2Theme->load_all($u);
        $cat_title = LJ::Lang::ml('widget.themechooser.header.all');
    }
    elsif ( $opts{cat} eq "custom" ) {
        @themes    = LJ::S2Theme->load_by_user($u);
        $cat_title = LJ::Lang::ml('widget.themechooser.header.custom');
    }
    elsif ( $opts{cat} eq "base" ) {
        @themes    = LJ::S2Theme->load_default_themes();
        $cat_title = $cats{'base'}->{text};
    }
    elsif ( $opts{cat} ) {
        @themes = LJ::S2Theme->load_by_cat( $opts{cat} );
        my $cat = $opts{cat};
        $cat_title = $cats{$cat}->{text};
    }
    elsif ( $opts{layoutid} ) {
        @themes = LJ::S2Theme->load_by_layoutid( $opts{layoutid}, $u );
        my $layout_name = LJ::Customize->get_layout_name( $opts{layoutid}, user => $u );
        $cat_title = LJ::ehtml($layout_name);
    }
    elsif ( $opts{designer} ) {
        @themes    = LJ::S2Theme->load_by_designer( $opts{designer} );
        $cat_title = LJ::ehtml( $opts{designer} );
    }
    elsif ( $opts{search} ) {
        @themes    = LJ::S2Theme->load_by_search( $opts{search}, $u );
        $cat_title = LJ::Lang::ml( 'widget.themechooser.header.search',
            { 'term' => LJ::ehtml( $opts{search} ) } );
    }
    else {    # category is "featured"
        @themes    = LJ::S2Theme->load_by_cat("featured");
        $cat_title = $cats{'featured'}->{text};
    }

    if ( $opts{cat} eq "base" ) {

        # sort alphabetically by layout
        @themes = sort { lc $a->layout_name cmp lc $b->layout_name } @themes;
    }
    else {
        # sort themes with custom at the end, then alphabetically by theme
        @themes =
            sort { $a->is_custom <=> $b->is_custom }
            sort { lc $a->name cmp lc $b->name } @themes;
    }

    # remove any themes from the array that are not defined or whose layout or theme is not active
    for ( my $i = 0 ; $i < @themes ; $i++ ) {
        my $layout_is_active = LJ::Hooks::run_hook( "layer_is_active", $themes[$i]->layout_uniq );
        my $theme_is_active  = LJ::Hooks::run_hook( "layer_is_active", $themes[$i]->uniq );

        unless ( ( defined $themes[$i] )
            && ( !defined $layout_is_active || $layout_is_active )
            && ( !defined $theme_is_active  || $theme_is_active ) )
        {

            splice( @themes, $i, 1 );
            $i--;    # we just removed an element from @themes
        }
    }

    @themes = LJ::Customize->remove_duplicate_themes(@themes);
    my $max_page =
        $opts{show} ne "all" ? POSIX::ceil( scalar(@themes) / $opts{show} ) || 1 : 1;

    if ( $opts{show} ne "all" ) {
        my $i_first = $opts{show} * ( $opts{page} - 1 );
        my $i_last  = ( $opts{show} * $opts{page} ) - 1;
        @themes = splice( @themes, $i_first, $opts{show} );
    }

    my @theme_data = ();
    for my $theme (@themes) {
        my $current_theme = ( $theme->themeid && ( $theme->themeid == $current->themeid ) )
            || ( ( $theme->layoutid == $current->layoutid )
            && !$theme->themeid
            && !$current->themeid ) ? 1 : 0;
        my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

        push @theme_data, get_theme_data( $theme, $current_theme, $no_layer_edit );

    }

    my $vars = {
        cat_title => $cat_title,
        max_page  => $max_page,
        themes    => \@theme_data,
        qargs     => \%opts
    };

    return DW::Template->template_string( 'widget/themechooser.tt', $vars );
}

sub get_theme_data {
    my ( $theme, $current, $no_layer_edit ) = @_;
    my $tmp = {
        imgurl   => $theme->preview_imgurl,
        layoutid => $theme->layoutid,
        themeid  => $theme->themeid,
        name     => $theme->{'name'},
        designer => $theme->designer,
        layout   => $theme->{'layout_name'},
    };

    $tmp->{'designer_link'} = LJ::create_url(
        "/customize",
        keep_args => [ 'show', 'authas' ],
        args      => { designer => $theme->designer }
    ) if $theme->designer;
    $tmp->{'layout_link'} = LJ::create_url(
        "/customize",
        keep_args => [ 'show', 'authas' ],
        args      => { layoutid => $theme->layoutid }
    );
    $tmp->{'current'} = $current;

    if ( $current && !$no_layer_edit && $theme->is_custom ) {
        $tmp->{can_edit_layout} = $theme->layoutid && !$theme->{layout_uniq} ? 1 : 0;
        $tmp->{can_edit_theme}  = $theme->themeid  && !$theme->{uniq}        ? 1 : 0;
    }

    if ( $theme->themeid ) {
        $tmp->{preview_url} = LJ::create_url( "/customize/preview_redirect",
            args => { 'themeid' => $theme->themeid } );
    }
    else {
        $tmp->{preview_url} = LJ::create_url( "/customize/preview_redirect",
            args => { 'layoutid' => $theme->layoutid } );
    }
    return $tmp;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $themeid  = $post->{apply_themeid} + 0;
    my $layoutid = $post->{apply_layoutid} + 0;

    # we need to load sponsor's themes for sponsored users
    my $substitue_user = LJ::Hooks::run_hook( "substitute_s2_layers_user", $u );
    my $effective_u    = defined $substitue_user ? $substitue_user : $u;
    my $theme;
    if ($themeid) {
        $theme = LJ::S2Theme->load_by_themeid( $themeid, $effective_u );
    }
    elsif ($layoutid) {
        $theme = LJ::S2Theme->load_custom_layoutid( $layoutid, $effective_u );
    }
    else {
        die "No theme id or layout id specified.";
    }

    LJ::Customize->apply_theme( $u, $theme );
    LJ::Hooks::run_hooks( 'apply_theme', $u );

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            var filter_links = DOM.getElementsByClassName(document, "theme-cat");
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-layout"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-designer"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-page"));
            page_links = document.querySelectorAll(".pagination a");
            page_links.forEach(link => {
                filter_links.push(link);
            })

            // add event listeners to all of the category, layout, designer, and page links
            // adding an event listener to page is done separately because we need to be sure to use that if it is there,
            //     and we will miss it if it is there but there was another arg before it in the URL
            filter_links.forEach(function (filter_link) {
                console.log(filter_link);
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                if (getArgs["page"]) {
                    DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", getArgs["page"]) });
                } else {
                    for (var arg in getArgs) {
                        if (!getArgs.hasOwnProperty(arg)) continue;
                        if (arg == "authas" || arg == "show") continue;
                        DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, arg, getArgs[arg]) });
                        break;
                    }
                }
            });

            // add event listeners to all of the apply theme forms
            var apply_forms = DOM.getElementsByClassName(document, "theme-form");
            apply_forms.forEach(function (form) {
                DOM.addEventListener(form, "submit", function (evt) { self.applyTheme(evt, form) });
            });

            // add event listeners to the preview links
            var preview_links = DOM.getElementsByClassName(document, "theme-preview-link");
            preview_links.forEach(function (preview_link) {
                DOM.addEventListener(preview_link, "click", function (evt) { self.previewTheme(evt, preview_link.href) });
            });

            // add event listener to the page and show dropdowns
            //DOM.addEventListener($('.pagination a'), "click", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_top').value) });
            // DOM.addEventListener($('page_dropdown_bottom'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_bottom').value) });
            DOM.addEventListener($('show_dropdown_top'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "show", $('show_dropdown_top').value) });
            DOM.addEventListener($('show_dropdown_bottom'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "show", $('show_dropdown_bottom').value) });
        },
        applyTheme: function (evt, form) {
            var given_themeid = form["Widget[ThemeChooser]_apply_themeid"].value + "";
            var given_layoutid = form["Widget[ThemeChooser]_apply_layoutid"].value + "";
            $("theme_btn_" + given_layoutid + given_themeid).disabled = true;
            DOM.addClassName($("theme_btn_" + given_layoutid + given_themeid), "theme-button-disabled disabled");

            this.doPost({
                apply_themeid: given_themeid,
                apply_layoutid: given_layoutid
            });

            Event.stop(evt);
        },
        onData: function (data) {
            Customize.ThemeNav.updateContent({
                method: "GET",
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                search: Customize.search,
                page: Customize.page,
                show: Customize.show,
                theme_chooser_id: $('theme_chooser_id').value
            });
            alert(Customize.ThemeChooser.confirmation);
            LiveJournal.run_hook("update_other_widgets", "ThemeChooser");
        },
        previewTheme: function (evt, href) {
            window.open(href, 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
