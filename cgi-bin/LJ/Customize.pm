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

package LJ::Customize;
use strict;
use Carp qw(croak);

# returns the S2Theme object of the given user's current theme
sub get_current_theme {
    my $class = shift;
    my $u     = shift;

    die "Invalid user object." unless LJ::isu($u);

    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style   = LJ::S2::get_style( $u, { verify => 1, force_layers => 1 } );

    if ( $style{theme} == 0 ) {

        # default theme of system layout
        if ( $pub->{ $style{layout} } && $pub->{ $style{layout} }->{uniq} ) {
            return LJ::S2Theme->load_default_of( $style{layout}, user => $u );

            # default theme of custom layout
        }
        else {
            return LJ::S2Theme->load_custom_layoutid( $style{layout}, $u );
        }
    }
    else {
 # if the user is using a duplicate theme layer, return a theme object using the correct theme layer
        my $real_themeid =
              $pub->{ $style{theme} } && $pub->{ $style{theme} }->{uniq}
            ? $class->real_themeid_for_uniq( $pub->{ $style{theme} }->{uniq} )
            : $style{theme};
        return LJ::S2Theme->load_by_themeid( $real_themeid, $u );
    }
}

# applies the given theme to the given user's journal
sub apply_theme {
    my $class = shift;
    my $u     = shift;
    my $theme = shift;

    my %style;
    my $has_cap = $u->can_create_s2_styles;
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    die "Your account status does not allow access to this custom layer."
        if $theme->is_custom && !$has_cap;
    die "You cannot use this theme."
        unless $theme->available_to($u);
    die "No core parent."
        unless $theme->coreid;

    # delete s2_style and replace it with a new
    # or existing style for this theme
    $u->set_prop( "s2_style", '' );

    $style{theme}  = $theme->themeid;
    $style{layout} = $theme->layoutid;
    $style{core}   = $theme->coreid;

    # if a style for this theme already exists, set that as the user's style
    my $styleid = $theme->get_styleid_for_theme($u);
    if ($styleid) {
        $u->set_prop( "s2_style", $styleid );

        # now we have to populate %style from this style
        # theme, layout, and core have already been set
        my $stylay = LJ::S2::get_style_layers( $u, $u->prop('s2_style') );
        foreach my $layer (qw(user i18nc i18n)) {
            $style{$layer} = exists $stylay->{$layer} ? $stylay->{$layer} : 0;
        }

        # no existing style found, create a new one
    }
    else {
        $style{user} = $style{i18nc} = $style{i18n} = 0;
    }

    # set style
    $class->implicit_style_create( $u, %style );
}

# if there's no style set, load the default style and set it as the current theme
# return the current style
sub verify_and_load_style {
    my $class = shift;
    my $u     = shift;

    my $style = LJ::S2::load_style( $u->prop('s2_style') );

    unless ( $style && $style->{layer}->{layout} ) {

        # we have no layout layer for this style, which causes errors in
        # the customization interface
        # undef current style and force them to use the site defaults
        $u->set_prop( s2_style => 0 );
        $style = undef;
    }

    unless ( $style && $style->{userid} == $u->userid ) {
        my $theme;
        if ( $LJ::DEFAULT_STYLE->{theme} ) {
            $theme = LJ::S2Theme->load_by_uniq( $LJ::DEFAULT_STYLE->{theme} );
        }
        else {
            $theme = LJ::S2Theme->load_default_of( $LJ::DEFAULT_STYLE->{layout} );
        }

        LJ::Customize->apply_theme( $u, $theme );
        $style = LJ::S2::load_style( $u->prop('s2_style') );    # reload style
    }

    return $style;
}

# migrates current style name from wizard-layoutname to wizard-layoutname/themename, if needed
sub migrate_current_style {
    my $class = shift;
    my $u     = shift;

    my $s2style = LJ::S2::load_style( $u->prop('s2_style'), skip_layer_load => 1 );
    my $theme   = $class->get_current_theme($u);

    my $style_name_old = $theme->old_style_name_for_theme;
    my $style_name_new = $theme->new_style_name_for_theme;

    # migrate only if there's a need to
    if ( $s2style->{name} eq $style_name_old ) {
        LJ::S2::rename_user_style( $u, $s2style->{styleid}, $style_name_new );
    }

    return;
}

# remove duplicate themes by uniq
# always keep the theme in a set of duplicates that has the lowest s2lid
sub remove_duplicate_themes {
    my $class  = shift;
    my @themes = @_;

    @themes =
        sort { $a->uniq cmp $b->uniq }
        sort { $a->themeid <=> $b->themeid } @themes;

    my @ret;
    my $prev_uniq = "";
    foreach my $theme (@themes) {
        if ( !$theme->uniq || ( $theme->uniq ne $prev_uniq ) ) {
            push @ret, $theme;
        }
        $prev_uniq = $theme->uniq;
    }

    return @ret;
}

# given a uniq, return the lowest s2lid for that uniq
sub real_themeid_for_uniq {
    my $class = shift;
    my $uniq  = shift;

    my $pub = LJ::S2::get_public_layers();
    my @s2lids_for_uniq =
        map  { $pub->{$_}->{s2lid} }
        sort { $pub->{$a}->{s2lid} <=> $pub->{$b}->{s2lid} }
        grep { $_ =~ /^\d+$/ && $pub->{$_}->{type} eq "theme" && $pub->{$_}->{uniq} eq $uniq }
        keys %$pub;

    return scalar @s2lids_for_uniq ? $s2lids_for_uniq[0] : 0;
}

sub implicit_style_create {
    my $class = shift;

    return s2_implicit_style_create(@_);
}

# passing the opt "reset" will revert the language layers to default
sub save_language {
    my $class    = shift;
    my $u        = shift;
    my $langcode = shift;
    my %opts     = @_;

    my %style   = LJ::S2::get_style( $u, "verify" );
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    if ( $opts{reset} ) {
        $style{i18nc} = $style{i18n} = 0;
        $class->implicit_style_create( $u, %style );
        return;
    }

    unless ( $langcode eq 'custom' ) {
        my @langs = LJ::S2::get_layout_langs( $pub, $style{'layout'} );
        my ( $i18n, $i18nc );

        # scan for an i18n user layer
        foreach ( values %$userlay ) {
            last
                if $_->{'b2lid'} == $style{'layout'}
                && $_->{'type'} eq 'i18n'
                && $_->{'langcode'} eq $langcode
                && ( $i18n = $_->{'s2lid'} );
        }

        # scan for i18nc public layer and i18n layer if necessary
        foreach ( values %$pub ) {
            last if $i18nc && $i18n;
            next
                if !$i18nc
                && $_->{'type'} eq 'i18nc'
                && $_->{'langcode'} eq $langcode
                && ( $i18nc = $_->{'s2lid'} );
            next
                if !$i18n
                && $_->{'b2lid'} == $style{'layout'}
                && $_->{'type'} eq 'i18n'
                && $_->{'langcode'} eq $langcode
                && ( $i18n = $_->{'s2lid'} );
        }
        $style{'i18nc'} = $i18nc;
        $style{'i18n'}  = $i18n;
        $class->implicit_style_create( $u, %style );
    }

    return;
}

# create sorted list of layouts to pass to html_select
sub get_layouts_for_dropdown {
    my $class = shift;
    my %opts  = @_;

    my $u   = $opts{user};
    my $pub = LJ::S2::get_public_layers();

    my @layouts = map {
        my $text          = $pub->{$_}->{'name'};
        my $can_use_layer = LJ::S2::can_use_layer( $u, $pub->{$_}->{'uniq'} );
        $text = "$text*"
            if !$can_use_layer;    # for browsers that don't support disabled or colored options
        {
            value    => $_,
            text     => $text,
            disabled => !$can_use_layer,
        }
        }
        sort { $pub->{$a}->{'name'} cmp $pub->{$b}->{'name'} }
        grep {
        my $tmp       = $_;
        my $is_active = LJ::Hooks::run_hook( "layer_is_active", $pub->{$tmp}->{uniq} );
               $tmp =~ /^\d+$/
            && $pub->{$tmp}->{'type'} eq "layout"
            && $pub->{$tmp}->{'uniq'} ne "s1shortcomings/layout"
            && ( !defined $is_active || $is_active )
            && ( $_ = $tmp )
        } keys %$pub;

    # add custom layouts
    push @layouts, $class->get_custom_layouts_for_dropdown($u);
    LJ::Hooks::run_hook( "modify_layout_list", \@layouts, user => $u, add_seps => 1 );

    unshift @layouts, 0, LJ::Lang::ml('customize.layouts_for_dropdown.choose');

    return @layouts;
}

sub get_custom_layouts_for_dropdown {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my @layers = ();

    my $has_cap = $u->can_create_s2_styles;
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style   = LJ::S2::get_style( $u, "verify" );

    my @user = map {
        my $text =
              $userlay->{$_}->{'name'}
            ? $userlay->{$_}->{'name'}
            : LJ::Lang::ml( 'customize.layoutname.default', { 'layoutid' => "\#$_" } );
        $text = "$text*" if !$has_cap; # for browsers that don't support disabled or colored options
        {
            value    => $_,
            text     => $text,
            disabled => !$has_cap,
        }
        }
        sort { $userlay->{$a}->{'name'} cmp $userlay->{$b}->{'name'} || $a <=> $b }
        grep {
               /^\d+$/
            && $userlay->{$_}->{'b2lid'} == $style{core}
            && $userlay->{$_}->{'type'} eq "layout"
        } keys %$userlay;

    if (@user) {
        push @layers,
            {
            value    => "",
            text     => "--- Custom Layers: ---",
            disabled => 1
            }, @user;
    }

    return @layers;
}

# given a layout id, get the layout's name
sub get_layout_name {
    my $class    = shift;
    my $layoutid = shift;
    my %opts     = @_;

    my $pub     = LJ::S2::get_public_layers();
    my $userlay = $opts{user} ? LJ::S2::get_layers_of_user( $opts{user} ) : "";

    my $layout_name;
    $layout_name = $pub->{$layoutid}->{name} if $pub->{$layoutid} && $pub->{$layoutid}->{name};
    $layout_name = $userlay->{$layoutid}->{name}
        if ref $userlay && $userlay->{$layoutid} && $userlay->{$layoutid}->{name};

    unless ($layout_name) {
        my %outhash = ();
        LJ::S2::load_layer_info( \%outhash, [$layoutid] );

        $layout_name = $outhash{$layoutid}->{name};
    }

    $layout_name = LJ::Lang::ml( 'customize.layoutname.default', { 'layoutid' => "#$layoutid" } )
        unless $layout_name;

    return $layout_name;
}

sub get_search_keywords_for_js {
    my $class = shift;
    my $u     = shift;

    my %keywords;
    my @themes = LJ::S2Theme->load_all($u);
    foreach my $theme (@themes) {
        next unless $theme;
        if ( LJ::Hooks::are_hooks("layer_is_active") ) {
            next
                unless LJ::Hooks::run_hook( "layer_is_active", $theme->uniq )
                && LJ::Hooks::run_hook( "layer_is_active", $theme->layout_uniq );
        }

        my $theme_name    = LJ::ejs( $theme->name );
        my $layout_name   = LJ::ejs( $theme->layout_name );
        my $designer_name = LJ::ejs( $theme->designer );

        if ($theme_name) {
            $keywords{$theme_name} = 1;
        }
        if ($layout_name) {
            $keywords{$layout_name} = 1;
        }
        if ($designer_name) {
            $keywords{$designer_name} = 1;
        }
    }

    my @sorted = sort { lc $a cmp lc $b } keys %keywords;
    @sorted = map { $_ = "\"$_\"" } @sorted;

    return @sorted;
}

sub get_layerids {
    my $class = shift;
    my $style = shift;

    my $dbh        = LJ::get_db_writer();
    my $layer      = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );
    my $lyr_layout = LJ::S2::load_layer( $dbh, $layer->{'b2lid'} );
    die "Layout layer for this $layer->{'type'} layer not found." unless $lyr_layout;
    my $lyr_core = LJ::S2::load_layer( $dbh, $lyr_layout->{'b2lid'} );
    die "Core layer for layout not found." unless $lyr_core;

    my @layers;
    push @layers,
        (
        [ 'core'   => $lyr_core->{'s2lid'} ],
        [ 'i18nc'  => $style->{'layer'}->{'i18nc'} ],
        [ 'layout' => $lyr_layout->{'s2lid'} ],
        [ 'i18n'   => $style->{'layer'}->{'i18n'} ]
        );

    if ( $layer->{'type'} eq "user" && $style->{'layer'}->{'theme'} ) {
        push @layers, [ 'theme' => $style->{'layer'}->{'theme'} ];
    }
    push @layers, [ $layer->{'type'} => $layer->{'s2lid'} ];

    my @layerids = grep { $_ } map { $_->[1] } @layers;

    return @layerids;
}

sub load_all_s2_props {
    my $class = shift;
    my $u     = shift;
    my $style = shift;

    my $styleid = $style->{styleid};

    # return if props have already been loaded in this request
    return if $LJ::REQ_GLOBAL{s2props}->{$styleid};

    my %s2_style = LJ::S2::get_style( $u, "verify" );

    unless ( $style->{layer}->{user} ) {
        $style->{layer}->{user} =
            LJ::S2::create_layer( $u->{userid}, $style->{layer}->{layout}, "user" );
        die "Could not generate user layer" unless $style->{layer}->{user};
        $s2_style{user} = $style->{layer}->{user};
    }

    $class->implicit_style_create( $u, %s2_style );

    my $dbh   = LJ::get_db_writer();
    my $layer = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );

    # if the b2lid of this layer has been remapped to a new layerid
    # then update the b2lid mapping for this layer
    my $b2lid = $layer->{b2lid};
    if ( $b2lid && $LJ::S2LID_REMAP{$b2lid} ) {
        LJ::S2::b2lid_remap( $u, $style->{'layer'}->{'user'}, $b2lid );
        $layer->{b2lid} = $LJ::S2LID_REMAP{$b2lid};
    }

    die "Layer belongs to another user. $layer->{userid} vs $u->{userid}"
        unless $layer->{userid} == $u->userid;
    die "Layer isn't of type user or theme."
        unless $layer->{type} eq "user" || $layer->{type} eq "theme";

    my @layerids = $class->get_layerids($style);
    LJ::S2::load_layers(@layerids);

    # load the language and layout choices for core.
    my %layerinfo;
    LJ::S2::load_layer_info( \%layerinfo, \@layerids );

    $LJ::REQ_GLOBAL{s2props}->{$styleid} = 1;

    return;
}

# passing the opt "reset" will revert all submitted props in $post to their default values
# passing the opt "delete_layer" will delete the entire user layer
sub save_s2_props {
    my $class = shift;
    my $u     = shift;
    my $style = shift;
    my $post  = shift;
    my %opts  = @_;

    $class->load_all_s2_props( $u, $style );

    my $dbh     = LJ::get_db_writer();
    my $layer   = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );
    my $layerid = $layer->{'s2lid'};

    if ( $opts{delete_layer} ) {
        my %s2_style = LJ::S2::get_style( $u, "verify" );

        LJ::S2::delete_layer( $s2_style{'user'} );
        $s2_style{'user'} = LJ::S2::create_layer( $u->{userid}, $s2_style{'layout'}, "user" );
        LJ::S2::set_style_layers( $u, $u->{'s2_style'}, "user", $s2_style{'user'} );
        $layerid = $s2_style{'user'};

        LJ::S2::load_layers($layerid);

        return;
    }

    my $lyr_layout = LJ::S2::load_layer( $dbh, $layer->{'b2lid'} );
    die "Layout layer for this $layer->{'type'} layer not found." unless $lyr_layout;
    my $lyr_core = LJ::S2::load_layer( $dbh, $lyr_layout->{'b2lid'} );
    die "Core layer for layout not found." unless $lyr_core;

    $lyr_layout->{'uniq'} = $dbh->selectrow_array(
        "SELECT value FROM s2info WHERE s2lid=? AND infokey=?",
        undef, $lyr_layout->{'s2lid'},
        "redist_uniq"
    );

    my @grouped_properties =
        grep { $_->{grouped} && $_->{grouped} == 1 } S2::get_properties( $lyr_core->{s2lid} );

    my %override;
    foreach my $prop ( S2::get_properties( $lyr_layout->{s2lid} ), @grouped_properties ) {
        $prop = S2::get_property( $lyr_core->{'s2lid'}, $prop )
            unless ref $prop;
        next unless ref $prop;
        next if $prop->{'noui'};
        my $name = $prop->{'name'};
        next unless LJ::S2::can_use_prop( $u, $lyr_layout->{'uniq'}, $name );

        my %prop_values = $class->get_s2_prop_values( $name, $u, $style );

        my $prop_value;
        if ( $opts{reset} ) {
            $prop_value = defined $post->{$name} ? $prop_values{existing} : $prop_values{override};
        }
        else {
            $prop_value = defined $post->{$name} ? $post->{$name} : $prop_values{override};
        }

        # new and existing match if both defined and same, or both undefined.
        next if !defined $prop_value and !defined $prop_values{existing};
        next
            if defined $prop_value
            and defined $prop_values{existing}
            and $prop_value eq $prop_values{existing};

        # special case: if the style doesn't define a value, and the user has a defined-but
        # blank or empty value, skip it
        next
            if !defined $prop_values{existing}
            && defined $prop_value
            && length($prop_value) == 0;

        $override{$name} = [ $prop, $prop_value ];
    }

    if ( LJ::S2::layer_compile_user( $layer, \%override ) ) {

        # saved
    }
    else {
        my $error = LJ::last_error();
        die "Error saving layer: $error";
    }

    LJ::S2::load_layers($layerid);

    return;
}

# returns hash with existing (parent) prop value and override (user layer) prop value
sub get_s2_prop_values {
    my ( $class, $prop_name, $u, $style, %opts ) = @_;

    $class->load_all_s2_props( $u, $style );

    my $dbh   = LJ::get_db_writer();
    my $layer = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );

    # figure out existing value (if there was no user/theme layer)
    my $existing;
    my @layerids = $class->get_layerids($style);
    foreach my $lid ( reverse @layerids ) {
        next if $lid == $layer->{'s2lid'};
        $existing = S2::get_set( $lid, $prop_name );
        last if defined $existing;
    }

    if ( ref $existing eq "HASH" && !$opts{noui} ) { $existing = $existing->{'as_string'}; }

    my $override     = S2::get_set( $layer->{'s2lid'}, $prop_name );
    my $had_override = defined $override;
    $override = $existing unless defined $override;

    if ( ref $override eq "HASH" && !$opts{noui} ) { $override = $override->{'as_string'}; }

    return ( existing => $existing, override => $override );
}

sub get_propgroups {
    my $class = shift;
    my $u     = shift;
    my $style = shift;

    $class->load_all_s2_props( $u, $style );

    my $dbh        = LJ::get_db_writer();
    my $layer      = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );
    my $lyr_layout = LJ::S2::load_layer( $dbh, $layer->{'b2lid'} );
    die "Layout layer for this $layer->{'type'} layer not found." unless $lyr_layout;
    my $lyr_core = LJ::S2::load_layer( $dbh, $lyr_layout->{'b2lid'} );
    die "Core layer for layout not found." unless $lyr_core;

    my %prop;    # name hashref, deleted when added to a category
    my @propnames;

    my @grouped_properties = S2::get_properties( $lyr_core->{s2lid} );
    @grouped_properties = grep { $_->{grouped} && $_->{grouped} == 1 } @grouped_properties;

    foreach my $prop ( S2::get_properties( $lyr_layout->{s2lid} ), @grouped_properties ) {
        unless ( ref $prop ) {
            $prop = S2::get_property( $lyr_core->{'s2lid'}, $prop );
            next unless ref $prop;
        }
        $prop{ $prop->{'name'} } = $prop;
        push @propnames, $prop->{'name'};
    }

    my @groups = S2::get_property_groups( $lyr_layout->{'s2lid'} );
    my @merged_groups;
    my $misc_group;
    my %groupprops;    # gname -> [ propname ]
    my %propgroup;     # pname -> gname;

    foreach my $gname (@groups) {
        if ( $gname eq "misc" || $gname eq "other" ) { $misc_group = $gname; }
        my $gname_merge = $gname;
        $gname_merge =~ s/_child$//;
        push @merged_groups, $gname if $gname_merge eq $gname;

        foreach my $pname ( S2::get_property_group_props( $lyr_layout->{'s2lid'}, $gname ) ) {
            my $prop = $prop{$pname};
            next if !$prop || $prop->{noui} || $propgroup{$pname};
            $propgroup{$pname} = $gname_merge;
            push @{ $groupprops{$gname_merge} }, $pname;
        }
    }

    # put unsorted props into an existing or new unsorted/misc group
    if (@merged_groups) {
        my @unsorted;
        foreach my $pname (@propnames) {
            my $prop = $prop{$pname};
            next if !$prop || $prop->{noui} || $prop->{grouped} || $propgroup{$pname};
            push @unsorted, $pname;
        }
        if (@unsorted) {
            unless ($misc_group) {
                $misc_group = "misc";
                push @merged_groups, "misc";
            }
            push @{ $groupprops{$misc_group} }, @unsorted;
        }
    }

    return (
        props      => \%prop,
        groups     => \@merged_groups,
        groupprops => \%groupprops,
        propgroup  => \%propgroup
    );
}

sub propgroup_name {
    my $class = shift;
    my $gname = shift;
    my $u     = shift;
    my $style = shift;

    $class->load_all_s2_props( $u, $style );

    my $dbh        = LJ::get_db_writer();
    my $layer      = LJ::S2::load_layer( $dbh, $style->{'layer'}->{'user'} );
    my $lyr_layout = LJ::S2::load_layer( $dbh, $layer->{'b2lid'} );
    die "Layout layer for this $layer->{'type'} layer not found." unless $lyr_layout;
    my $lyr_core = LJ::S2::load_layer( $dbh, $lyr_layout->{'b2lid'} );
    die "Core layer for layout not found." unless $lyr_core;

    foreach my $lid (
        $style->{'layer'}->{'i18n'},  $lyr_layout->{'s2lid'},
        $style->{'layer'}->{'i18nc'}, $lyr_core->{'s2lid'}
        )
    {
        next unless $lid;
        my $name = S2::get_property_group_name( $lid, $gname );
        return LJ::ehtml($name) if $name;
    }
    return "Misc" if $gname eq "misc";
    return $gname;
}

sub get_cats {
    my $class = shift;
    my $u     = shift;

    my @categories = (
        all => {
            text  => LJ::Lang::ml('customize.cats.all'),
            main  => 1,
            order => 2,
        },
        featured => {
            text  => LJ::Lang::ml('customize.cats.featured'),
            main  => 1,
            order => 1,
        },
        special => {
            text  => LJ::Lang::ml('customize.cats.special'),
            main  => 1,
            order => 4,
        },
        custom => {
            text  => LJ::Lang::ml('customize.cats.custom'),
            main  => 1,
            order => 5,
        },
        base => {
            text  => LJ::Lang::ml('customize.cats.base'),
            main  => 1,
            order => 3,
        },
        map { $_ => { text => $_, order => 3, } }
            LJ::S2Theme->all_categories( special => 0, all => 0 ),
    );

    LJ::Hooks::run_hooks( "modify_cat_list", \@categories, user => $u, );

    return @categories;
}

sub get_layouts {
    return (
        '1'    => LJ::Lang::ml('customize.layouts2.1'),
        '1s'   => LJ::Lang::ml('customize.layouts.1s'),
        '2l'   => LJ::Lang::ml('customize.layouts2.2l'),
        '2r'   => LJ::Lang::ml('customize.layouts2.2r'),
        '2lnh' => LJ::Lang::ml('customize.layouts2.2lnh'),
        '2rnh' => LJ::Lang::ml('customize.layouts2.2rnh'),
        '3l'   => LJ::Lang::ml('customize.layouts2.3l'),
        '3r'   => LJ::Lang::ml('customize.layouts2.3r'),
        '3'    => LJ::Lang::ml('customize.layouts2.3'),
    );
}

sub get_propgroup_subheaders {
    return (
        page       => LJ::Lang::ml('customize.propgroup_subheaders.page'),
        module     => LJ::Lang::ml('customize.propgroup_subheaders.module'),
        navigation => LJ::Lang::ml('customize.propgroup_subheaders.navigation'),
        header     => LJ::Lang::ml('customize.propgroup_subheaders.header'),
        entry      => LJ::Lang::ml('customize.propgroup_subheaders.entry'),
        comment    => LJ::Lang::ml('customize.propgroup_subheaders.comment'),
        archive    => LJ::Lang::ml('customize.propgroup_subheaders.archive'),
        footer     => LJ::Lang::ml('customize.propgroup_subheaders.footer'),

        unsorted => LJ::Lang::ml('customize.propgroup_subheaders.unsorted'),
    );
}

sub get_propgroup_subheaders_order {
    return (
        qw (
            page
            module
            navigation
            header
            footer
            entry
            comment
            archive
            unsorted
            )

    );
}

# <LJFUNC>
# name: LJ::Customize::s2_implicit_style_create
# des:  Common "create s2 style" skeleton.
# args: opts?, user, style*
# des-opts: Hash of options
#           - force: forces creation of a new style even if one already exists
# des-user: User to get layers of
# des-style: Hash of style information
#            - theme: theme id of style theme
#            - layout: layout id of style layout
#            Other keys as used by LJ::S2::set_style_layers
# returns: 1 if successful
# </LJFUNC>
sub s2_implicit_style_create {
    my ( $opts, $u, %style );

    # this is because the arguments aren't static
    # old callers don't pass in an options hashref, so we create a blank one
    if ( ref $_[0] && ref $_[1] ) {
        ( $opts, $u ) = ( shift, shift );
    }
    else {
        ( $opts, $u ) = ( {}, shift );
    }

    # everything else is part of the style hash
    %style = (@_);

    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    # Create new style if necessary
    my $s2style = LJ::S2::load_style( $u->prop('s2_style') );
    if ( !( $s2style && $s2style->{userid} == $u->userid ) || $opts->{force} ) {
        my $themeid  = $style{theme};
        my $layoutid = $style{layout};
        my $layer    = $pub->{$themeid} || $userlay->{$themeid} || $userlay->{$layoutid};
        my $uniq     = $layer->{uniq} || $layer->{s2lid};

        my $s2_style;
        unless ( $s2_style = LJ::S2::create_style( $u, "wizard-$uniq" ) ) {
            die "Can't create style";
        }
        $u->set_prop( "s2_style", $s2_style );
    }

    # save values in %style to db
    LJ::S2::set_style_layers( $u, $u->prop('s2_style'), %style );

    return 1;
}

# <LJFUNC>
# name: LJ::Customize::validate_moodthemeid
# des: Spoof checking for mood theme ids
# args: user, themeid
# des-user: user attempting to use the mood theme
# des-themeid: mood theme user wants to use
# returns: themeid if public or owned by user, false otherwise
# </LJFUNC>
sub validate_moodthemeid {
    my ( $class, $u, $themeid ) = @_;
    my $theme = DW::Mood->new($themeid);
    return 0
        unless $theme
        && ( $theme->is_public eq 'Y' || $theme->ownerid == $u->userid );
    return $themeid;
}

# <LJFUNC>
# name: LJ::Customize::get_moodtheme_select_list
# des: Gets mood theme list.
# args: user
# des-user: users whose private mood themes should be returned
# returns: Returns a list of mood themes that the user can select from,
#          suitable for [func[LJ::html_select]].
# </LJFUNC>
sub get_moodtheme_select_list {
    my ( $class, $u ) = @_;

    # faster to get full cached data, but we only want id & name
    my $strip = sub {
        return {
            moodthemeid => $_[0]->{moodthemeid},
            name        => $_[0]->{name}
        };
    };

    my @themes;
    foreach my $moodtheme ( DW::Mood->public_themes ) {
        my $is_active = LJ::Hooks::run_hook( "mood_theme_is_active", $moodtheme->{moodthemeid} );
        next unless !defined $is_active || $is_active;
        push @themes, $strip->($moodtheme);
    }
    LJ::Hooks::run_hook( 'modify_mood_theme_list', \@themes, user => $u, add_seps => 1 );
    unshift @themes, { 'moodthemeid' => 0, 'name' => '(None)' };

    ### user's private themes
    {
        my @theme_user;
        foreach ( DW::Mood->get_themes( { ownerid => $u->id } ) ) {
            next if $_->{is_public} eq 'Y';
            push @theme_user, $strip->($_);
        }
        if (@theme_user) {
            my $text = LJ::Lang::ml('customize.moodicons.personal');
            push @themes,
                {
                moodthemeid => 0,
                name        => "--- $text ---",
                disabled    => 1
                };
            push @themes, @theme_user;
        }
    }

    return @themes;
}

1;
