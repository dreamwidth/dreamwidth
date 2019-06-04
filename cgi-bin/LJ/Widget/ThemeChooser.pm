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

sub ajax     { 1 }
sub authas   { 1 }
sub need_res { qw( stc/widgets/themechooser.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";

    # filter criteria
    my $cat      = defined $opts{cat}      ? $opts{cat}      : "";
    my $layoutid = defined $opts{layoutid} ? $opts{layoutid} : 0;
    my $designer = defined $opts{designer} ? $opts{designer} : "";
    my $search   = defined $opts{search}   ? $opts{search}   : "";
    my $page = $opts{page} || 1;
    my $show = $opts{show} || 12;

    my $showarg = $show != 12 ? "&show=$opts{show}" : "";

    my $viewing_featured = !$cat && !$layoutid && !$designer;

    my %cats = LJ::Customize->get_cats($u);
    my $ret .= "<div class='theme-selector-content pkg'>";
    $ret .=
          "<script>Customize.ThemeChooser.confirmation = \""
        . $class->ml('widget.themechooser.confirmation')
        . "\";</script>";

    my @getargs;
    my @themes;
    if ( $cat eq "all" ) {
        push @getargs, "cat=all";
        @themes = LJ::S2Theme->load_all($u);
    }
    elsif ( $cat eq "custom" ) {
        push @getargs, "cat=custom";
        @themes = LJ::S2Theme->load_by_user($u);
    }
    elsif ( $cat eq "base" ) {
        push @getargs, "cat=base";
        @themes = LJ::S2Theme->load_default_themes();
    }
    elsif ($cat) {
        push @getargs, "cat=$cat";
        @themes = LJ::S2Theme->load_by_cat($cat);
    }
    elsif ($layoutid) {
        push @getargs, "layoutid=$layoutid";
        @themes = LJ::S2Theme->load_by_layoutid( $layoutid, $u );
    }
    elsif ($designer) {
        push @getargs, "designer=" . LJ::eurl($designer);
        @themes = LJ::S2Theme->load_by_designer($designer);
    }
    elsif ($search) {
        push @getargs, "search=" . LJ::eurl($search);
        @themes = LJ::S2Theme->load_by_search( $search, $u );
    }
    else {    # category is "featured"
        @themes = LJ::S2Theme->load_by_cat("featured");
    }

    if ( $show != 12 ) {
        push @getargs, "show=$show";
    }

    @themes = LJ::Customize->remove_duplicate_themes(@themes);

    if ( $cat eq "base" ) {

        # sort alphabetically by layout
        @themes = sort { lc $a->layout_name cmp lc $b->layout_name } @themes;
    }
    else {
        # sort themes with custom at the end, then alphabetically by theme
        @themes =
            sort { $a->is_custom <=> $b->is_custom }
            sort { lc $a->name cmp lc $b->name } @themes;
    }

    LJ::Hooks::run_hooks( "modify_theme_list", \@themes, user => $u, cat => $cat );

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

    my $current_theme        = LJ::Customize->get_current_theme($u);
    my $index_of_first_theme = $show ne "all" ? $show * ( $page - 1 ) : 0;
    my $index_of_last_theme  = $show ne "all" ? ( $show * $page ) - 1 : scalar @themes - 1;
    my @themes_this_page     = @themes[ $index_of_first_theme .. $index_of_last_theme ];

    if ( $cat eq "all" ) {
        $ret .= "<h3>" . $class->ml('widget.themechooser.header.all') . "</h3>";
    }
    elsif ( $cat eq "custom" ) {
        $ret .= "<h3>" . $class->ml('widget.themechooser.header.custom') . "</h3>";
    }
    elsif ($cat) {
        $ret .= "<h3>$cats{$cat}->{text}</h3>";
    }
    elsif ($layoutid) {
        my $layout_name = LJ::Customize->get_layout_name( $layoutid, user => $u );
        $ret .= "<h3>$layout_name</h3>";
    }
    elsif ($designer) {
        $ret .= "<h3>$designer</h3>";
    }
    elsif ($search) {
        $ret .= "<h3>"
            . $class->ml( 'widget.themechooser.header.search', { 'term' => LJ::ehtml($search) } )
            . "</h3>";
    }
    else {    # category is "featured"
        $ret .= "<h3>$cats{featured}->{text}</h3>";
    }

    $ret .= $class->print_paging(
        themes   => \@themes,
        show     => $show,
        page     => $page,
        getargs  => \@getargs,
        getextra => $getextra,
        location => "top",
    );

    $ret .= "<div class='themes-area'><ul class='select-list'>";
    foreach my $theme (@themes_this_page) {
        next unless defined $theme;

        # figure out the type(s) of theme this is so we can modify the output accordingly
        my %theme_types;
        if ( $theme->themeid ) {
            $theme_types{current} = 1 if $theme->themeid == $current_theme->themeid;
        }
        elsif ( !$theme->themeid && !$current_theme->themeid ) {
            $theme_types{current} = 1 if $theme->layoutid == $current_theme->layoutid;
        }
        $theme_types{upgrade} = 1 if !$theme->available_to($u);
        $theme_types{special} = 1 if LJ::Hooks::run_hook( "layer_is_special", $theme->uniq );

        my ( $theme_class, $theme_options, $theme_icons ) = ( "", "", "" );

        $theme_icons .= "<div class='theme-icons'>"
            if $theme_types{upgrade} || $theme_types{special};
        if ( $theme_types{current} ) {
            my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

            $theme_class .= " selected";
            $theme_options .=
                  "<strong><a href='$LJ::SITEROOT/customize/options$getextra'>"
                . $class->ml('widget.themechooser.theme.customize')
                . "</a></strong>";
            if ( !$no_layer_edit && $theme->is_custom && !$theme_types{upgrade} ) {
                if ( $theme->layoutid && !$theme->layout_uniq ) {
                    $theme_options .=
                          "<br /><strong><a href='$LJ::SITEROOT/customize/advanced/layeredit?id="
                        . $theme->layoutid . "'>"
                        . $class->ml('widget.themechooser.theme.editlayoutlayer')
                        . "</a></strong>";
                }
                if ( $theme->themeid && !$theme->uniq ) {
                    $theme_options .=
                          "<br /><strong><a href='$LJ::SITEROOT/customize/advanced/layeredit?id="
                        . $theme->themeid . "'>"
                        . $class->ml('widget.themechooser.theme.editthemelayer')
                        . "</a></strong>";
                }
            }
        }
        if ( $theme_types{upgrade} ) {
            $theme_class   .= " upgrade";
            $theme_options .= "<br />" if $theme_options;
            $theme_options .= LJ::Hooks::run_hook( "customize_special_options", $u, $theme );
            $theme_icons   .= LJ::Hooks::run_hook( "customize_special_icons", $u, $theme );
        }
        if ( $theme_types{special} ) {
            $theme_class .= " special"
                if $viewing_featured && LJ::Hooks::run_hook( "should_see_special_content", $u );
            $theme_icons .= LJ::Hooks::run_hook( "customize_available_until", $theme );
        }
        $theme_icons .= "</div><!-- end .theme-icons -->" if $theme_icons;

        my $theme_layout_name = $theme->layout_name;
        my $theme_designer    = $theme->designer;

        $ret .= "<li class='theme-item$theme_class'>";
        $ret .= "<img src='" . $theme->preview_imgurl . "' class='theme-preview' />";

        $ret .= "<h4>" . $theme->name . "</h4><div class='theme-action'><span class='theme-desc'>";

        if ($theme_designer) {
            my $designer_link =
                  "<a href='$LJ::SITEROOT/customize/$getextra${getsep}designer="
                . LJ::eurl($theme_designer)
                . "$showarg' class='theme-designer'>$theme_designer</a> ";
            $ret .= $class->ml( 'widget.themechooser.theme.designer',
                { 'designer' => $designer_link } );
        }

        my $preview_redirect_url;
        if ( $theme->themeid ) {
            $preview_redirect_url =
                "$LJ::SITEROOT/customize/preview_redirect$getextra${getsep}themeid="
                . $theme->themeid;
        }
        else {
            $preview_redirect_url =
                "$LJ::SITEROOT/customize/preview_redirect$getextra${getsep}layoutid="
                . $theme->layoutid;
        }
        $ret .= "<a href='$preview_redirect_url' target='_blank' class='theme-preview-link' title='"
            . $class->ml('widget.themechooser.theme.preview') . "'>";

        $ret .=
"<img src='$LJ::IMGPREFIX/customize/preview-theme.gif' class='theme-preview-image' /></a>";
        $ret .= $theme_icons;

        my $layout_link =
              "<a href='$LJ::SITEROOT/customize/$getextra${getsep}layoutid="
            . $theme->layoutid
            . "$showarg' class='theme-layout'><em>$theme_layout_name</em></a>";
        my $special_link_opts =
"href='$LJ::SITEROOT/customize/$getextra${getsep}cat=special$showarg' class='theme-cat'";
        if ( $theme_types{special} ) {
            $ret .= $class->ml( 'widget.themechooser.theme.specialdesc2',
                { 'aopts' => $special_link_opts } );
        }
        else {
            $ret .= $class->ml( 'widget.themechooser.theme.desc2', { 'style' => $layout_link } );
        }
        $ret .= "</span>";

        if ($theme_options) {
            $ret .= $theme_options;
        }
        else {    # apply theme form
            $ret .= $class->start_form( class => "theme-form" );
            $ret .= $class->html_hidden(
                apply_themeid  => $theme->themeid,
                apply_layoutid => $theme->layoutid,
            );
            $ret .= $class->html_submit(
                apply => $class->ml('widget.themechooser.theme.apply'),
                {
                          raw => "class='theme-button' id='theme_btn_"
                        . $theme->layoutid
                        . $theme->themeid . "'"
                },
            );
            $ret .= $class->end_form;
        }
        $ret .= "</div><!-- end .theme-action --></li><!-- end .theme-item -->";
    }
    $ret .= "</ul></div><!-- end .themes-area --->";

    $ret .= $class->print_paging(
        themes   => \@themes,
        show     => $show,
        page     => $page,
        getargs  => \@getargs,
        getextra => $getextra,
        location => "bottom",
    );

    $ret .= "</div><!-- end .theme-selector-content -->";

    return $ret;
}

sub print_paging {
    my $class = shift;
    my %opts  = @_;

    my $themes   = $opts{themes};
    my $page     = $opts{page};
    my $show     = $opts{show};
    my $location = $opts{location};

    my $max_page = $show ne "all" ? POSIX::ceil( scalar(@$themes) / $show ) || 1 : 1;

    my $getargs  = $opts{getargs};
    my $getextra = $opts{getextra};

    my $q_string = join( "&", @$getargs );
    my $q_sep  = $q_string ? "&" : "";
    my $getsep = $getextra ? "&" : "?";

    my $url = "$LJ::SITEROOT/customize/$getextra$getsep$q_string$q_sep";

    my $ret;

    $ret .= "<div class='theme-paging theme-paging-$location'>";
    unless ( $page == 1 && $max_page == 1 ) {
        if ( $page - 1 >= 1 ) {
            $ret .=
                "<span class='item'><a href='${url}page=1' class='theme-page'>&lt;&lt;</a></span>";
            $ret .=
                  "<span class='item'><a href='${url}page="
                . ( $page - 1 )
                . "' class='theme-page'>&lt;</a></span>";
        }
        else {
            $ret .= "<span class='item'>&lt;&lt;</span>";
            $ret .= "<span class='item'>&lt;</span>";
        }

        my @pages;
        foreach my $pagenum ( 1 .. $max_page ) {
            push @pages, $pagenum, $pagenum;
        }
        my $currentpage = LJ::Widget::ThemeNav->html_select(
            {
                name     => "page",
                id       => "page_dropdown_$location",
                selected => $page,
            },
            @pages,
        );

        $ret .= $class->start_form;
        $ret .= "<span class='item'>" . $class->ml('widget.themechooser.page') . " ";
        $ret .= $class->ml( 'widget.themechooser.page.maxpage',
            { currentpage => $currentpage, maxpage => $max_page } )
            . " ";
        $ret .=
            "<noscript>"
            . LJ::Widget::ThemeNav->html_submit(
            page_dropdown_submit => $class->ml('widget.themechooser.btn.page') )
            . "</noscript></span>";
        $ret .= $class->end_form;

        if ( $page + 1 <= $max_page ) {
            $ret .=
                  "<span class='item'><a href='${url}page="
                . ( $page + 1 )
                . "' class='theme-page'>&gt;</a></span>";
            $ret .=
"<span class='item'><a href='${url}page=$max_page' class='theme-page'>&gt;&gt;</a></span>";
        }
        else {
            $ret .= "<span class='item'>&gt;</span>";
            $ret .= "<span class='item'>&gt;&gt;</span>";
        }

        $ret .= "<span class='item'>|</span>";
    }

    my @shows = qw( 6 6 12 12 24 24 48 48 96 96 all All );

    $ret .= $class->start_form;
    $ret .= "<span class='item'>" . $class->ml('widget.themechooser.show') . " ";
    $ret .= LJ::Widget::ThemeNav->html_select(
        {
            name     => "show",
            id       => "show_dropdown_$location",
            selected => $show,
        },
        @shows,
    ) . " ";
    $ret .=
        "<noscript>"
        . LJ::Widget::ThemeNav->html_submit(
        show_dropdown_submit => $class->ml('widget.themechooser.btn.show') )
        . "</noscript></span>";
    $ret .= $class->end_form;

    $ret .= " <span id='paging_msg_area_$location'></span>";
    $ret .= "</div>";

    return $ret;
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

            // add event listeners to all of the category, layout, designer, and page links
            // adding an event listener to page is done separately because we need to be sure to use that if it is there,
            //     and we will miss it if it is there but there was another arg before it in the URL
            filter_links.forEach(function (filter_link) {
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
            DOM.addEventListener($('page_dropdown_top'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_top').value) });
            DOM.addEventListener($('page_dropdown_bottom'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_bottom').value) });
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
