package LJ::Widget::ThemeNav;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub ajax { 1 }
sub can_fake_ajax_post { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/themenav.css js/inputcomplete.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $theme_chooser_id = defined $opts{theme_chooser_id} ? $opts{theme_chooser_id} : 0;
    my $headextra = $opts{headextra};

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    # filter criteria
    my $cat = defined $opts{cat} ? $opts{cat} : "";
    my $layoutid = defined $opts{layoutid} ? $opts{layoutid} : 0;
    my $designer = defined $opts{designer} ? $opts{designer} : "";
    my $search = defined $opts{search} ? $opts{search} : "";
    my $filter_available = defined $opts{filter_available} ? $opts{filter_available} : 0;
    my $page = defined $opts{page} ? $opts{page} : 1;
    my $show = defined $opts{show} ? $opts{show} : 12;

    my $filterarg = $filter_available ? "filter_available=1" : "";
    my $showarg = $show != 12 ? "show=$opts{show}" : "";

    # we want to have "All" selected if we're filtering by layout or designer, or if we're searching
    my $viewing_all = $layoutid || $designer || $search;

    my $theme_chooser = LJ::Widget::ThemeChooser->new( id => $theme_chooser_id );
    $theme_chooser_id = $theme_chooser->{id} unless $theme_chooser_id;
    $$headextra .= $theme_chooser->wrapped_js( page_js_obj => "Customize" ) if $headextra;

    # sort cats by specificed order key, then alphabetical order
    my %cats = LJ::Customize->get_cats($u);
    my @cats_sorted =
        sort { $cats{$a}->{order} <=> $cats{$b}->{order} }
        sort { lc $cats{$a}->{text} cmp lc $cats{$b}->{text} } keys %cats;

    # pull the main cats out of the full list
    my @main_cats_sorted;
    for (my $i = 0; $i < @cats_sorted; $i++) {
        my $c = $cats_sorted[$i];

        if (defined $cats{$c}->{main}) {
            my $el = splice(@cats_sorted, $i, 1);
            push @main_cats_sorted, $el;
            $i--; # we just removed an element from @cats_sorted
        }
    }

    my $ret;
    $ret .= "<h2 class='widget-header'>" . $class->ml('widget.themenav.title');
    $ret .= $class->start_form;
    $ret .= "<span>" . $class->html_check( name => "filter_available", id => "filter_available", selected => $filter_available );
    $ret .= " <label for='filter_available'>" . $class->ml('widget.themenav.filteravailable') . "</label>";
    $ret .= " " . $class->html_submit( "filter" => $class->ml('widget.themenav.btn.filteravailable'), { id => "filter_btn" }) . "</span>";
    $ret .= $class->end_form;
    $ret .= "</h2>";

    my @keywords = LJ::Customize->get_search_keywords_for_js($u);
    my $keywords_string = join(",", @keywords);
    $ret .= "<script>Customize.ThemeNav.searchwords = [$keywords_string];</script>";

    $ret .= $class->start_form( id => "search_form" );
    $ret .= "<p class='detail theme-nav-search-box'>";
    $ret .= $class->html_text( name => 'search', id => 'search_box', size => 30, raw => "autocomplete='off'" );
    $ret .= " " . $class->html_submit( "search_submit" => $class->ml('widget.themenav.btn.search'), { id => "search_btn" });
    $ret .= "</p>";
    $ret .= $class->end_form;

    $ret .= "<div class='theme-nav-inner-wrapper'>";
    $ret .= "<div class='theme-selector-nav'>";

    $ret .= "<ul class='theme-nav nostyle'>";
    $ret .= $class->print_cat_list(
        user => $u,
        selected_cat => $cat,
        viewing_all => $viewing_all,
        cat_list => \@main_cats_sorted,
        getextra => $getextra,
        filterarg => $filterarg,
        showarg => $showarg,
    );
    $ret .= "</ul>";

    if (scalar @cats_sorted) {
        $ret .= "<div class='theme-nav-separator'><hr /></div>";
    
        $ret .= "<ul class='theme-nav nostyle'>";
        $ret .= $class->print_cat_list(
            user => $u,
            selected_cat => $cat,
            viewing_all => $viewing_all,
            cat_list => \@cats_sorted,
            getextra => $getextra,
            filterarg => $filterarg,
            showarg => $showarg,
        );
        $ret .= "</ul>";
    
        $ret .= "<div class='theme-nav-separator'><hr /></div>";
    }
    
    $ret .= "<ul class='theme-nav-small nostyle'>";
    $ret .= "<li class='first'><a href='$LJ::SITEROOT/customize/advanced/'>" . $class->ml('widget.themenav.developer') . "</a>";
    $ret .= LJ::run_hook('customize_advanced_area_upsell', $u) . "</li>";
    
    my $no_system_switch = LJ::run_hook("no_s1s2_system_switch", $u);
    unless ($no_system_switch) {
        $ret .= "<li class='last'><a href='$LJ::SITEROOT/customize/switch_system.bml$getextra'>" . $class->ml('widget.themenav.switchtos1') . "</a></li>";
    }
    $ret .= "</ul>";

    $ret .= "</div>";

    $ret .= "<div class='theme-nav-content'>";
    $ret .= $class->html_hidden({ name => "theme_chooser_id", value => $theme_chooser_id, id => "theme_chooser_id" });
    $ret .= $theme_chooser->render(
        cat => $cat,
        layoutid => $layoutid,
        designer => $designer,
        search => $search,
        filter_available => $filter_available,
        page => $page,
        show => $show,
    );
    $ret .= "</div>";
    $ret .= "</div>";

    return $ret;
}

sub print_cat_list {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user};
    my $cat_list = $opts{cat_list};

    my %cats = LJ::Customize->get_cats($u);

    my @special_themes = LJ::S2Theme->load_by_cat("special");
    my $special_themes_exist = 0;
    foreach my $special_theme (@special_themes) {
        my $layout_is_active = LJ::run_hook("layer_is_active", $special_theme->layout_uniq);
        my $theme_is_active = LJ::run_hook("layer_is_active", $special_theme->uniq);

        if ($layout_is_active && $theme_is_active) {
            $special_themes_exist = 1;
            last;
        }
    }

    my @custom_themes = LJ::S2Theme->load_by_user($opts{user});

    my $ret;

    for (my $i = 0; $i < @$cat_list; $i++) {
        my $c = $cat_list->[$i];

        next if $c eq "special" && !$special_themes_exist;
        next if $c eq "custom" && !@custom_themes;

        my $li_class = "";
        $li_class .= " on" if
            ($c eq $opts{selected_cat}) ||
            ($c eq "featured" && !$opts{selected_cat} && !$opts{viewing_all}) ||
            ($c eq "all" && $opts{viewing_all});
        $li_class .= " first" if $i == 0;
        $li_class .= " last" if $i == @$cat_list - 1;
        $li_class =~ s/^\s//; # remove the first space
        $li_class = " class='$li_class'" if $li_class;

        my $arg = "";
        $arg = "cat=$c" unless $c eq "featured";
        if ($arg || $opts{filterarg} || $opts{showarg}) {
            my $allargs = $arg;
            $allargs .= "&" if $allargs && $opts{filterarg};
            $allargs .= $opts{filterarg};
            $allargs .= "&" if $allargs && $opts{showarg};
            $allargs .= $opts{showarg};

            $arg = $opts{getextra} ? "&$allargs" : "?$allargs";
        }

        $ret .= "<li$li_class><a href='$LJ::SITEROOT/customize/$opts{getextra}$arg' class='theme-nav-cat'>$cats{$c}->{text}</a></li>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $q_string = BML::get_query_string();
    $q_string =~ s/&?page=\d+//g;

    my $url = "$LJ::SITEROOT/customize/";
    if ($post->{filter}) {
        $q_string =~ s/&?filter_available=\d//g;
        $q_string = "?$q_string" if $q_string;
        my $q_sep = $q_string ? "&" : "?";

        if ($post->{filter_available}) {
            $url .= "$q_string${q_sep}filter_available=1";
        } else {
            $url .= $q_string;
        }
    } elsif ($post->{page}) {
        $q_string = "?$q_string" if $q_string;
        my $q_sep = $q_string ? "&" : "?";

        $post->{page} = LJ::eurl($post->{page});
        if ($post->{page} != 1) {
            $url .= "$q_string${q_sep}page=$post->{page}";
        } else {
            $url .= $q_string;
        }
    } elsif ($post->{show}) {
        $q_string =~ s/&?show=\w+//g;
        $q_string = "?$q_string" if $q_string;
        my $q_sep = $q_string ? "&" : "?";

        $post->{show} = LJ::eurl($post->{show});
        if ($post->{show} != 12) {
            $url .= "$q_string${q_sep}show=$post->{show}";
        } else {
            $url .= $q_string;
        }
    } elsif ($post->{search}) {
        my $filter = ($q_string =~ /&?filter_available=\d/) ? "&filter_available=1" : "";
        my $show = ($q_string =~ /&?show=(\w+)/) ? "&show=$1" : "";
        my $authas = ($q_string =~ /&?authas=(\w+)/) ? "&authas=$1" : "";
        $q_string = "";

        $post->{search} = LJ::eurl($post->{search});
        $url .= "?search=$post->{search}$authas$filter$show";
    }

    return BML::redirect($url);
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            if ($('search_box')) {
                var keywords = new InputCompleteData(Customize.ThemeNav.searchwords, "ignorecase");
                var ic = new InputComplete($('search_box'), keywords);

                var text = "theme, layout, or designer";
                var color = "#999";
                $('search_box').style.color = color;
                $('search_box').value = text;
                DOM.addEventListener($('search_box'), "focus", function (evt) {
                    if ($('search_box').value == text) {
                        $('search_box').style.color = "";
                        $('search_box').value = "";
                    }
                });
                DOM.addEventListener($('search_box'), "blur", function (evt) {
                    if ($('search_box').value == "") {
                        $('search_box').style.color = color;
                        $('search_box').value = text;
                    }
                });
            }

            $('filter_btn').style.display = "none";
            DOM.addEventListener($('filter_available'), "click", function (evt) { self.filterThemes(evt, "filter_available", $('filter_available').checked) });

            // add event listener to the search form
            DOM.addEventListener($('search_form'), "submit", function (evt) { self.filterThemes(evt, "search", $('search_box').value) });

            var filter_links = DOM.getElementsByClassName(document, "theme-nav-cat");

            // add event listeners to all of the category links
            filter_links.forEach(function (filter_link) {
                var evt_listener_added = 0;
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                for (var arg in getArgs) {
                    if (!getArgs.hasOwnProperty(arg)) continue;
                    if (arg == "authas" || arg == "filter_available" || arg == "show") continue;
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, arg, getArgs[arg]) });
                    evt_listener_added = 1;
                    break;
                }

                // if there was no listener added to a link, add it without any args (for the 'featured' category)
                if (!evt_listener_added) {
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, "", "") });
                }
            });
        },
        filterThemes: function (evt, key, value) {
            // filtering by availability, page, and show use the values of the other filters, so do not reset them in that case
            if (key == "filter_available") {
                if (value) {
                    Customize.filter_available = 1;
                } else {
                    Customize.filter_available = 0;
                }

                // need to go back to page 1 if the filter was switched because
                // the current page may no longer have any themes to show on it
                Customize.page = 1;
            } else if (key == "show") {
                // need to go back to page 1 if the show amount was switched because
                // the current page may no longer have any themes to show on it
                Customize.page = 1;
            } else if (key != "page") {
                Customize.resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                Event.stop(evt);
                return;
            }

            if (key == "cat") Customize.cat = value;
            if (key == "layoutid") Customize.layoutid = value;
            if (key == "designer") Customize.designer = value;
            if (key == "search") Customize.search = value;
            if (key == "page") Customize.page = value;
            if (key == "show") Customize.show = value;

            this.updateContent({
                method: "GET",
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                search: Customize.search,
                filter_available: Customize.filter_available,
                page: Customize.page,
                show: Customize.show,
                theme_chooser_id: $('theme_chooser_id').value
            });

            Event.stop(evt);

            if (key == "search") {
                $("search_btn").disabled = true;
            } else if (key == "page" || key == "show") {
                $("paging_msg_area_top").innerHTML = "<em>Please wait...</em>";
                $("paging_msg_area_bottom").innerHTML = "<em>Please wait...</em>";
            } else {
                Customize.cursorHourglass(evt);
            }
        },
        onData: function (data) {
            Customize.CurrentTheme.updateContent({
                filter_available: Customize.filter_available,
                show: Customize.show
            });
            Customize.hideHourglass();
        },
        onRefresh: function (data) {
            this.initWidget();
            Customize.ThemeChooser.initWidget();
        }
    ];
}

1;
