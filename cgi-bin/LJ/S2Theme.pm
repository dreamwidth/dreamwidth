package LJ::S2Theme;
use strict;
use Carp qw(croak);
use LJ::Customize;
use LJ::ModuleLoader;

LJ::ModuleLoader->autouse_subclasses("LJ::S2Theme");

sub init {
    1;
}


##################################################
# Class Methods
##################################################

# returns the uniq of the default theme for the given layout id or uniq (for lazy migration)
sub default_theme {
    my $class = shift;
    my $layout = shift;
    my %opts = @_;

    # turn the given $layout into a uniq if it's an id
    my $pub = LJ::S2::get_public_layers();
    if ($layout =~ /^\d+$/) {
        $layout = $pub->{$layout}->{uniq};
    }

    # return if this is a custom layout
    return "" unless ref $pub->{$layout};

    # remove the /layout part of the uniq to just get the layout name
    $layout =~ s/\/layout$//;

    my %default_themes = (
        bases => 'bases/tropical',
        basicboxes => 'basicboxes/green',
        blanket => 'blanket/peach',
        boxesandborders => 'boxesandborders/gray',
        brittle => 'brittle/rust',
        core2base => 'core2base/testing',
        crossroads => 'crossroads/lettuce',
        drifting => 'drifting/blue',
        fluidmeasure => 'fluidmeasure/spice',
        funkycircles => 'funkycircles/darkpurple',
        negatives => 'negatives/black',
        steppingstones => 'steppingstones/purple',
        tranquilityiii => 'tranquilityiii/nightsea',
        zesty => 'zesty/white',
    );

    my %local_default_themes = eval "use LJ::S2Theme_local; 1;" ? $class->local_default_themes($layout, %opts) : ();
    my $default_theme = $default_themes{$layout} || $local_default_themes{$layout};
    die "Default theme for layout $layout does not exist." unless $default_theme;
    return $default_theme;
}

sub load {
    my $class = shift;
    my %opts = @_;

    # load a single given theme by theme id
    # will check user themes if user opt is specified and themeid is not a system theme
    if ($opts{themeid}) {
        return $class->load_by_themeid($opts{themeid}, $opts{user});

    # load all themes of a single given layout id
    # will check user themes in addition to system themes if user opt is specified
    } elsif ($opts{layoutid}) {
        return $class->load_by_layoutid($opts{layoutid}, $opts{user});

    # load the default theme of a single given layout id
    } elsif ($opts{default_of}) {
        return $class->load_default_of($opts{default_of});

    # load all themes of a single given uniq (layout or theme)
    } elsif ($opts{uniq}) {
        return $class->load_by_uniq($opts{uniq});

    # load all themes of a single given category
    } elsif ($opts{cat}) {
        return $class->load_by_cat($opts{cat});

    # load all themes by a particular designer
    } elsif ($opts{designer}) {
        return $class->load_by_designer($opts{designer});

    # load all custom themes of the user
    } elsif ($opts{user}) {
        return $class->load_by_user($opts{user});

    # load all themes that match a particular search term
    } elsif ($opts{search}) {
        return $class->load_by_search($opts{search}, $opts{user});

    # load custom layout with themeid of 0
    } elsif ($opts{custom_layoutid}) {
        return $class->load_custom_layoutid($opts{custom_layoutid}, $opts{user});

    # load all themes
    # will load user themes in addition to system themes if user opt is specified
    } elsif ($opts{all}) {
        return $class->load_all($opts{user});
    }

    # no valid option given
    die "Must pass one or more of the following options to theme loader: themeid, layoutid, default_of, uniq, cat, designer, user, custom_layoutid, all";
}

sub load_by_themeid {
    my $class = shift;
    my $themeid = shift;
    my $u = shift;

    return $class->new( themeid => $themeid, user => $u );
}

sub load_by_layoutid {
    my $class = shift;
    my $layoutid = shift;
    my $u = shift;

    my @themes;
    my $pub = LJ::S2::get_public_layers();
    my $children = $pub->{$layoutid}->{children};
    foreach my $themeid (@$children) {
        next unless $pub->{$themeid}->{type} eq "theme";
        push @themes, $class->new( themeid => $themeid );
    }

    if ($u) {
        my $userlay = LJ::S2::get_layers_of_user($u);
        foreach my $layer (keys %$userlay) {
            my $layer_type = $userlay->{$layer}->{type};

            # custom themes of the given layout
            if ($layer_type eq "theme" && $userlay->{$layer}->{b2lid} == $layoutid) {
                push @themes, $class->new( themeid => $layer, user => $u );

            # custom layout that is the given layout (no theme)
            } elsif ($layer_type eq "layout" && $userlay->{$layer}->{s2lid} == $layoutid) {
                push @themes, $class->new_custom_layout( layoutid => $layer, user => $u );
            }
        }
    }

    return @themes;
}

sub load_default_of {
    my $class = shift;
    my $layoutid = shift;
    my %opts = @_;

    my $default_theme = $class->default_theme($layoutid, %opts);
    return $default_theme ? $class->load_by_uniq($default_theme) : undef;
}

sub load_by_uniq {
    my $class = shift;
    my $uniq = shift;

    my $pub = LJ::S2::get_public_layers();
    if ($pub->{$uniq} && $pub->{$uniq}->{type} eq "theme") {
        return $class->load_by_themeid($pub->{$uniq}->{s2lid});
    } elsif ($pub->{$uniq} && $pub->{$uniq}->{type} eq "layout") {
        return $class->load_by_layoutid($pub->{$uniq}->{s2lid});
    }

    die "Given uniq is not a valid layout or theme: $uniq";
}

sub load_by_cat {
    my $class = shift;
    my $cat = shift;

    my @themes;
    my $pub = LJ::S2::get_public_layers();
    foreach my $layer (keys %$pub) {
        next unless $layer =~ /^\d+$/;
        next unless $pub->{$layer}->{type} eq "theme";
        my $theme = $class->new( themeid => $layer );

        # we have a theme, now see if it's in the given category
        foreach my $possible_cat ($theme->cats) {
            next unless $possible_cat eq $cat;
            push @themes, $theme;
            last;
        }
    }

    return @themes;
}

sub load_by_designer {
    my $class = shift;
    my $designer = shift;

    # decode and lowercase and remove spaces
    $designer = LJ::durl($designer);
    $designer = lc $designer;
    $designer =~ s/\s//g;

    my @themes;
    my $pub = LJ::S2::get_public_layers();
    foreach my $layer (keys %$pub) {
        next unless $layer =~ /^\d+$/;
        next unless $pub->{$layer}->{type} eq "theme";
        my $theme = $class->new( themeid => $layer );

        # we have a theme, now see if it's made by the given designer
        my $theme_designer = lc $theme->designer;
        $theme_designer =~ s/\s//g;
        push @themes, $theme if $theme_designer eq $designer;
    }

    return @themes;
}

sub load_by_user {
    my $class = shift;
    my $u = shift;

    die "Invalid user object." unless LJ::isu($u);

    my @themes;
    my $userlay = LJ::S2::get_layers_of_user($u);
    foreach my $layer (keys %$userlay) {
        my $layer_type = $userlay->{$layer}->{type};
        if ($layer_type eq "theme") {
            push @themes, $class->new( themeid => $layer, user => $u );
        } elsif ($layer_type eq "layout") {
            push @themes, $class->new_custom_layout( layoutid => $layer, user => $u );
        }
    }

    return @themes;
}

sub load_by_search {
    my $class = shift;
    my $term = shift;
    my $u = shift;

    # decode and lowercase and remove spaces
    $term = LJ::durl($term);
    $term = lc $term;
    $term =~ s/\s//g;

    my @themes_ret;
    my @themes = $class->load_all($u);
    foreach my $theme (@themes) {
        my $theme_name = lc $theme->name;
        $theme_name =~ s/\s//g;
        my $layout_name = lc $theme->layout_name;
        $layout_name =~ s/\s//g;
        my $designer_name = lc $theme->designer;
        $designer_name =~ s/\s//g;

        if ($theme_name =~ /\Q$term\E/ || $layout_name =~ /\Q$term\E/ || $designer_name =~ /\Q$term\E/) {
            push @themes_ret, $theme;
        }
    }

    return @themes_ret;
}

sub load_custom_layoutid {
    my $class = shift;
    my $layoutid = shift;
    my $u = shift;

    return $class->new_custom_layout( layoutid => $layoutid, user => $u );
}

sub load_all {
    my $class = shift;
    my $u = shift;

    my @themes;
    my $pub = LJ::S2::get_public_layers();
    foreach my $layer (keys %$pub) {
        next unless $layer =~ /^\d+$/;
        next unless $pub->{$layer}->{type} eq "theme";
        next if LJ::S2::is_public_internal_layer($layer);
        push @themes, $class->new( themeid => $layer );
    }

    if ($u) {
        push @themes, $class->load_by_user($u);
    }

    return @themes;
}

# given an array of themes, return an array of only those themes available to the given user
sub filter_available {
    my $class = shift;
    my $u = shift;
    my @themes = @_;

    die "Invalid user object." unless LJ::isu($u);

    my @themes_ret;
    foreach my $theme (@themes) {
        push @themes_ret, $theme if $theme->available_to($u);
    }

    return @themes_ret;
}

# custom layouts without themes need special treatment when creating an S2Theme object
sub new_custom_layout {
    my $class = shift;
    my $self = {};
    my %opts = @_;

    my $layoutid = $opts{layoutid}+0;
    die "No layout id given." unless $layoutid;

    my $u = $opts{user};
    die "Invalid user object." unless LJ::isu($u);

    my %outhash = ();
    my $userlay = LJ::S2::get_layers_of_user($u);
    unless (ref $userlay->{$layoutid}) {
        LJ::S2::load_layer_info(\%outhash, [ $layoutid ]);

        die "Given layout id does not correspond to a layer usable by the given user." unless $outhash{$layoutid}->{is_public};
    }

    my $using_layer_info = scalar keys %outhash;

    die "Given layout id does not correspond to a layout."
        unless $using_layer_info ? $outhash{$layoutid}->{type} eq "layout" : $userlay->{$layoutid}->{type} eq "layout";

    my $layer;
    if ($using_layer_info) {
        $layer = LJ::S2::load_layer($layoutid);
    }

    $self->{s2lid}       = 0;
    $self->{b2lid}       = $layoutid;
    $self->{name}        = LJ::Lang::ml('s2theme.themename.notheme');
    $self->{uniq}        = undef;
    $self->{is_custom}   = 1;
    $self->{coreid}      = $using_layer_info ? $layer->{b2lid}+0 : $userlay->{$layoutid}->{b2lid}+0;
    $self->{layout_name} = LJ::Customize->get_layout_name($layoutid, user => $u);
    $self->{layout_uniq} = undef;

    bless $self, $class;
    return $self;
}

sub new {
    my $class = shift;
    my $self = {};
    my %opts = @_;

    my $themeid = $opts{themeid}+0;
    die "No theme id given." unless $themeid;

    my $layers = LJ::S2::get_public_layers();
    my $is_custom = 0;
    my %outhash = ();
    unless ($layers->{$themeid} && $layers->{$themeid}->{uniq}) {
        if ($opts{user}) {
            my $u = $opts{user};
            die "Invalid user object." unless LJ::isu($u);

            $layers = LJ::S2::get_layers_of_user($u);
            unless (ref $layers->{$themeid}) {
                LJ::S2::load_layer_info(\%outhash, [ $themeid ]);

                die "Given theme id does not correspond to a layer usable by the given user." unless $outhash{$themeid}->{is_public};
            }
            $is_custom = 1;
        } else {
            die "Given theme id does not correspond to a system layer.";
        }
    }

    my $using_layer_info = scalar keys %outhash;

    die "Given theme id does not correspond to a theme."
        unless $using_layer_info ? $outhash{$themeid}->{type} eq "theme" : $layers->{$themeid}->{type} eq "theme";

    my $layer;
    if ($using_layer_info) {
        $layer = LJ::S2::load_layer($themeid);
    }

    $self->{s2lid}     = $themeid;
    $self->{b2lid}     = $using_layer_info ? $layer->{b2lid}+0 : $layers->{$themeid}->{b2lid}+0;
    $self->{name}      = $using_layer_info ? $layer->{name} : $layers->{$themeid}->{name};
    $self->{uniq}      = $is_custom ? undef : $layers->{$themeid}->{uniq};
    $self->{is_custom} = $is_custom;

    $self->{name} = LJ::Lang::ml('s2theme.themename.default', {themeid => "#$themeid"}) unless $self->{name};

    # get the coreid by first checking the user layers and then the public layers for the layout
    my $pub = LJ::S2::get_public_layers();
    my $userlay = $opts{user} ? LJ::S2::get_layers_of_user($opts{user}) : "";
    if ($using_layer_info) {
        my $layout_layer = LJ::S2::load_layer($self->{b2lid});
        $self->{coreid} = $layout_layer->{b2lid};
    } else {
        $self->{coreid} = $userlay->{$self->{b2lid}}->{b2lid}+0 if ref $userlay && $userlay->{$self->{b2lid}};
        $self->{coreid} = $pub->{$self->{b2lid}}->{b2lid}+0 unless $self->{coreid};
    }

    # layout name
    $self->{layout_name} = LJ::Customize->get_layout_name($self->{b2lid}, user => $opts{user});

    # layout uniq
    $self->{layout_uniq} = $pub->{$self->{b2lid}}->{uniq} if $pub->{$self->{b2lid}} && $pub->{$self->{b2lid}}->{uniq};

    # package name for the theme
    my $theme_class = $self->{uniq};
    $theme_class =~ s/-/_/g;
    $theme_class =~ s/\//::/;
    $theme_class = "LJ::S2Theme::$theme_class";

    # package name for the layout
    my $layout_class = $self->{uniq};
    $layout_class =~ s/\/.+//;
    $layout_class =~ s/-/_/g;
    $layout_class = "LJ::S2Theme::$layout_class";

    # make this theme an object of the lowest level class that's defined
    if (eval { $theme_class->init }) {
        bless $self, $theme_class;
    } elsif (eval { $layout_class->init }) {
        bless $self, $layout_class;
    } else {
        bless $self, $class;
    }

    return $self;
}


##################################################
# Object Methods
##################################################

sub s2lid {
    my $self = shift;

    return $self->{s2lid};
}
*themeid = \&s2lid;

sub b2lid {
    my $self = shift;

    return $self->{b2lid};
}
*layoutid = \&b2lid;

sub coreid {
    my $self = shift;

    return $self->{coreid};
}

sub name {
    my $self = shift;

    return $self->{name};
}

sub layout_name {
    my $self = shift;

    return $self->{layout_name};
}

sub uniq {
    my $self = shift;

    return $self->{uniq};
}

sub layout_uniq {
    my $self = shift;

    return $self->{layout_uniq};
}
*is_system_layout = \&layout_uniq; # if the theme's layout has a uniq, then it's a system layout

sub is_custom {
    my $self = shift;

    return $self->{is_custom};
}

sub preview_imgurl {
    my $self = shift;

    my $imgurl = "$LJ::IMGPREFIX/customize/previews/";
    $imgurl .= $self->uniq ? $self->uniq : "custom-layer";
    $imgurl .= ".png";

    return $imgurl;
}

sub available_to {
    my $self = shift;
    my $u = shift;

    # theme isn't available to $u if the layout isn't
    return LJ::S2::can_use_layer($u, $self->uniq) && LJ::S2::can_use_layer($u, $self->layout_uniq);
}

# wizard-layoutname
sub old_style_name_for_theme {
    my $self = shift;

    return "wizard-" . ((split("/", $self->uniq))[0] || $self->layoutid);
}

# wizard-layoutname/themename
sub new_style_name_for_theme {
    my $self = shift;

    return "wizard-" . ($self->uniq || $self->themeid || $self->layoutid);
}

# find the appropriate styleid for this theme
# if a style for the layout but not the theme exists, rename it to match the theme
sub get_styleid_for_theme {
    my $self = shift;
    my $u = shift;

    my $style_name_old = $self->old_style_name_for_theme;
    my $style_name_new = $self->new_style_name_for_theme;

    my $userstyles = LJ::S2::load_user_styles($u);
    foreach my $styleid (keys %$userstyles) {
        my $style_name = $userstyles->{$styleid};

        next unless $style_name eq $style_name_new || $style_name eq $style_name_old;

        # lazy migration of style names from wizard-layoutname to wizard-layoutname/themename
        LJ::S2::rename_user_style($u, $styleid, $style_name_new)
            if $style_name eq $style_name_old;

        return $styleid;
    }

    return 0;
}

sub get_custom_i18n_layer_for_theme {
    my $self = shift;
    my $u = shift;

    my $userlay = LJ::S2::get_layers_of_user($u);
    my $layoutid = $self->layoutid;
    my $i18n_layer = 0;

    # scan for a custom i18n layer
    foreach my $layer (values %$userlay) {
        last if
            $layer->{b2lid} == $layoutid &&
            $layer->{type} eq 'i18n' &&
            ($i18n_layer = $layer->{s2lid});
    }

    return $i18n_layer;
}

sub get_custom_user_layer_for_theme {
    my $self = shift;
    my $u = shift;

    my $userlay = LJ::S2::get_layers_of_user($u);
    my $layoutid = $self->layoutid;
    my $user_layer = 0;

    # scan for a custom user layer
    # ignore auto-generated user layers, since they're not custom layers
    foreach my $layer (values %$userlay) {
        last if
            $layer->{b2lid} == $layoutid &&
            $layer->{type} eq 'user' &&
            $layer->{name} ne 'Auto-generated Customizations' &&
            ($user_layer = $layer->{s2lid});
    }

    return $user_layer;
}

sub get_preview_styleid {
    my $self = shift;
    my $u = shift;

    # get the styleid of the _for_preview style
    my $styleid = $u->prop('theme_preview_styleid');
    my $style = LJ::S2::load_style($styleid) if $styleid;
    if (!$styleid || !$style) {
        $styleid = LJ::S2::create_style($u, "_for_preview");
        $u->set_prop('theme_preview_styleid', $styleid);
    }
    return "" unless $styleid;

    # if we already have a style for this theme, copy it to the _for_preview style and use it
    # -- don't re-use the theme layer though, since this might be a layout (old format) style
    #    instead of a theme (new format) style
    my $theme_styleid = $self->get_styleid_for_theme($u);
    if ($theme_styleid) {
        my $style = LJ::S2::load_style($theme_styleid);
        my %layers;
        foreach my $layer (qw( core i18nc layout i18n user )) {
            $layers{$layer} = $style->{layer}->{$layer};
        }
        $layers{theme} = $self->themeid;
        LJ::S2::set_style_layers($u, $styleid, %layers);

        return $styleid;
    }

    # we don't have a style for this theme, so get the new layers and set them to _for_preview directly
    my %style = LJ::S2::get_style($u);
    my $i18n_layer = $self->get_custom_i18n_layer_for_theme($u);
    my $user_layer = $self->get_custom_user_layer_for_theme($u);
    
    # for the i18nc layer, match the user's preferences if they're not switching cores
    # if they are switching cores, we don't know what the equivalent should be
    my $i18nc_layer = ( $self->coreid == $style{core} ) ? $style{i18nc} : undef;
    
    my %layers = (
        core   => $self->coreid,
        i18nc  => $i18nc_layer,
        layout => $self->layoutid,
        i18n   => $i18n_layer,
        theme  => $self->themeid,
        user   => $user_layer,
    );
    LJ::S2::set_style_layers($u, $styleid, %layers);

    return $styleid;
}


##################################################
# Methods that get overridden by child packages
##################################################

sub cats { () } # categories that the theme is in
sub layouts { ( "1" => 1 ) } # theme layout/sidebar placement options ( layout type => property value or 1 if no property )
sub layout_prop { "" } # property that controls the layout/sidebar placement
sub show_sidebar_prop { "" } # property that controls whether a sidebar shows or not
sub designer { "" } # designer of the theme
sub linklist_support_tab { "" } # themes that don't use the linklist_support prop will have copy pointing them to the correct tab

# for appending layout-specific props to global props
sub _append_props {
    my $self = shift;
    my $method = shift;
    my @props = @_;

    my @defaults = eval "LJ::S2Theme->$method";
    return (@defaults, @props);
}

# props that shouldn't be shown in the wizard UI
sub hidden_props {
    qw(
        custom_control_strip_colors
        control_strip_bgcolor
        control_strip_fgcolor
        control_strip_bordercolor
        control_strip_linkcolor
    )
}

# props by category heading
sub display_option_props {
    qw(
        num_items_recent
        num_items_reading
        use_journalstyle_entry_page
        page_recent_items
        page_friends_items
        view_entry_disabled
        use_shared_pic
        linklist_support
    )
}

sub module_props {
    qw (
        text_module_links
        text_module_pagesummary
        text_module_syndicate
        text_module_tags
        text_generated_on
        text_tags_manage
        text_tag_uses
        text_module_customtext
        text_module_customtext_content
        text_module_customtext_url
        color_module_background
        color_module_text
        color_module_border
        color_module_link
        color_module_link_active
        color_module_link_hover
        color_module_link_visited
        color_module_title
        color_module_title_background
        font_module_heading
        font_module_heading_size
        font_module_heading_units
        font_module_text
        font_module_text_size
        font_module_text_units
        image_background_module_group
        image_background_module_url
        image_background_module_repeat
        image_background_module_position
    )
}

sub navigation_props { 
    qw (
        text_view_archive
        text_view_friends
        text_view_friends_comm
        text_view_friends_filter
        text_view_network
        text_view_memories
        text_view_recent
        text_view_userinfo
        text_view_tags
    ) 
}

sub header_props {
    qw (
        text_tags_page_header
        color_header_background
        font_journal_title
        font_journal_title_size
        font_journal_title_units
        font_journal_subtitle
        font_journal_subtitle_size
        font_journal_subtitle_units
        image_background_header_group
        image_background_header_url
        image_background_header_repeat
        image_background_header_position
        image_background_header_height
    )
}

sub footer_props {
    qw (
        color_footer_background
        color_footer_link
        color_footer_link_active
        color_footer_link_hover
        color_footer_link_visited
    )
}

sub entry_props {
    qw (
        text_edit_entry
        text_edit_tags
        text_mem_add
        text_post_comment
        text_read_comments
        text_post_comment_friends
        text_read_comments_friends
        text_permalink
        text_stickyentry_subject
        text_entry_prev
        text_entry_next
        text_tell_friend
        text_meta_mood
        text_meta_music
        text_meta_groups
        text_meta_location
        text_nosubject
        text_watch_comments
        text_unwatch_comments
        text_tags
        color_entry_link
        color_entry_link_active
        color_entry_link_hover
        color_entry_link_visited
        color_entry_border
        color_entry_background
        color_entry_text
        color_entry_title
        color_entry_title_background
        color_entry_interaction_links
        color_entry_interaction_links_hover
        color_entry_interaction_links_active
        color_entry_interaction_links_visited
        font_entry_title
        font_entry_title_size
        font_entry_title_units
        image_background_entry_group
        image_background_entry_url
        image_background_entry_repeat
        image_background_entry_position
    )
}

sub comment_props {
    qw (
        text_comment_date
        text_comment_edittime
        text_comment_expand
        text_comment_from
        text_comment_frozen
        text_comment_ipaddr
        text_comment_parent
        text_comment_posted
        text_comment_reply
        text_comment_thread
        color_comment_title_background
    )
}

sub archive_props {
    qw (
        text_day_next
        text_day_prev
        text_view_month
    )
}

sub page_props {
    qw (
        color_page_background
        color_page_text
        color_page_link
        color_page_link_active
        color_page_link_hover
        color_page_link_visited
        color_page_title
        color_page_border
        font_base
        font_fallback
        font_base_size
        font_base_units
        image_background_page_group
        image_background_page_url
        image_background_page_repeat
        image_background_page_position
    )
}

1;
