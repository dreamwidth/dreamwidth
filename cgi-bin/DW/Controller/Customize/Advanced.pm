
#!/usr/bin/perl
#
# DW::Controller::Customize::Advanced
#
# This controller is for /customize/options and the helper functions for that view.
#
# Authors:
#      R Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::Customize::Advanced;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Logic::MenuNav;

DW::Routing->register_string( '/customize/advanced',             \&advanced_handler,    app => 1 );
DW::Routing->register_string( '/customize/advanced/layerbrowse', \&layerbrowse_handler, app => 1 );
DW::Routing->register_string( '/customize/advanced/layers',      \&layers_handler,      app => 1 );
DW::Routing->register_string( '/customize/advanced/styles',      \&styles_handler,      app => 1 );
DW::Routing->register_string( '/customize/advanced/layersource', \&layersource_handler, app => 1 );
DW::Routing->register_string( '/customize/advanced/layeredit',   \&layeredit_handler,   app => 1 );

sub advanced_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r             = $rv->{r};
    my $POST          = $r->post_args;
    my $u             = $rv->{u};
    my $remote        = $rv->{remote};
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

    my $vars;
    $vars->{u}             = $u;
    $vars->{remote}        = $remote;
    $vars->{no_layer_edit} = $no_layer_edit;

    return DW::Template->render_template( 'customize/advanced/index.tt', $vars );

}

sub layerbrowse_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;

    my $vars;
    $vars->{u}      = $u;
    $vars->{remote} = $remote;
    $vars->{expand} = $GET->{'expand'};

    my $pub = LJ::S2::get_public_layers();

    my $id;
    if ( $GET->{'id'} ) {
        if ( $GET->{'id'} =~ /^\d+$/ ) {    # numeric
            $id = $GET->{'id'};
        }
        else {                              # redist_uniq
            $id = $pub->{ $GET->{'id'} }->{'s2lid'};
        }
    }

    my $dbr = LJ::get_db_reader();

    my %layerinfo;
    my @to_load = grep { /^\d+$/ } keys %$pub;
    LJ::S2::load_layer_info( \%layerinfo, \@to_load );

    my @s2_keys =
        grep { /^\d+$/ && exists $pub->{$_}->{'b2lid'} && $pub->{$_}->{'b2lid'} == 0 } keys %$pub;

    $vars->{pub}     = $pub;
    $vars->{s2_keys} = \@s2_keys;

    $vars->{childsort} = sub {
        my $unsortedchildren = shift;
        my @sortedchildren   = sort {
                   ( $layerinfo{$b}{type} cmp $layerinfo{$a}{type} )
                || ( $layerinfo{$a}{name} cmp $layerinfo{$b}{name} )
        } @$unsortedchildren;

        return \@sortedchildren;
    };

    my $xlink = sub {
        my $r = shift;
        $r =~ s/\[class\[(\w+)\]\]/<a href=\"\#class.$1\">$1<\/a>/g;
        $r =~ s/\[method\[(.+?)\]\]/<a href=\"\#meth.$1\">$1<\/a>/g;
        $r =~ s/\[function\[(.+?)\]\]/<a href=\"\#func.$1\">$1<\/a>/g;
        $r =~ s/\[member\[(.+?)\]\]/<a href=\"\#member.$1\">$1<\/a>/g;
        return $r;
    };

    my $class;
    my $s2info;
    if ($id) {
        LJ::S2::load_layers($id);
        $s2info = S2::get_layer_all($id);
        $class  = $s2info->{'class'} || {};

        $vars->{s2info} = $s2info;
        $vars->{id}     = $id;
        $vars->{class}  = $class;

        # load layer info
        my $layer = defined $pub->{$id} ? $pub->{$id} : LJ::S2::load_layer($id);

        my $layerinfo = {};
        LJ::S2::load_layer_info( $layerinfo, [$id] );
        my $srcview =
            exists $layerinfo->{$id}->{'source_viewable'}
            ? $layerinfo->{$id}->{'source_viewable'}
            : undef;

        # do they have access?
        my $isadmin =
            !defined $pub->{$id} && $remote && $remote->has_priv( 'siteadmin', 'styleview' );
        my $can_manage = $remote && $remote->can_manage( LJ::load_userid( $layer->{userid} ) );

        $vars->{srcview}    = $srcview;
        $vars->{isadmin}    = $isadmin;
        $vars->{can_manage} = $can_manage;

    }

    my $xlink_args = sub {
        my $r = shift;
        return
            unless $r =~ /^(.+?\()(.*)\)$/;
        my ( $new, @args ) = ( $1, split( /\s*\,\s*/, $2 ) );
        foreach (@args) {
            s/^(\w+)/defined $class->{$1} ? "[class[$1]]" : $1/eg;
        }
        $new .= join( ", ", @args ) . ")";
        $r = $new;
        $xlink->($r);
    };

    my $format_value;
    $format_value = sub {
        my $v = shift;

        if ( ref $v eq "HASH" ) {
            if ( $v->{'_type'} eq "Color" && $v->{'as_string'} =~ /^#\w\w\w\w\w\w$/ ) {
                my $ecolor = LJ::ehtml( $v->{'as_string'} );
                $v =
"<span style=\"border: 1px solid #000000; padding-left: 2em; background-color: $ecolor\">&nbsp;</span> <tt>$ecolor</tt>";
            }
            elsif ( defined $v->{'_type'} ) {
                $v = BML::ml( '.propformat.object', { 'type' => LJ::ehtml( $v->{'_type'} ) } );
            }
            else {
                if ( scalar(%$v) ) {
                    $v =
"<code>{</code><ul style='list-style: none; margin: 0 0 0 1.5em; padding: 0;'>"
                        . join(
                        "\n",
                        map {
                                  "<li><b>"
                                . LJ::ehtml($_)
                                . "</b> &rarr; "
                                . $format_value->( $v->{$_} )
                                . ",</li>"
                        } keys %$v
                        ) . "</ul><code>}</code>";
                }
                else {
                    $v = "<code>{}</code>";
                }
            }
        }
        elsif ( ref $v eq "ARRAY" ) {
            if ( scalar(@$v) ) {
                $v =
                    "<code>[</code><ul style='list-style: none; margin: 0 0 0 1.5em; padding: 0;'>"
                    . join( "\n", map { "<li>" . $format_value->($_) . ",</li>" } @$v )
                    . "</ul><code>]</code>";
            }
            else {
                $v = "<code>[]</code>";
            }
        }
        else {
            $v = $v ne '' ? LJ::ehtml($v) : "<i>" . LJ::Lang::ml('.propformat.empty') . "</i>";
        }

        return $v;
    };

    $vars->{xlink}      = $xlink;
    $vars->{xlink_args} = $xlink_args;
    $vars->{layer_is_active} =
        sub { my $x = shift; LJ::Hooks::run_hook( "layer_is_active", $pub->{$x}->{uniq} ); };
    $vars->{ehtml}        = \&LJ::ehtml;
    $vars->{defined}      = sub { return defined $_; };
    $vars->{format_value} = $format_value;
    $vars->{layerinfo}    = \%layerinfo;

    return DW::Template->render_template( 'customize/advanced/layerbrowse.tt', $vars );

}

sub layers_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r             = $rv->{r};
    my $POST          = $r->post_args;
    my $u             = $rv->{u};
    my $remote        = $rv->{remote};
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $remote );
    my $GET           = $r->get_args;
    my $authas        = $u->user ne $remote->user ? "?authas=" . $u->user : "";

    # id is optional
    my $id;
    $id = $POST->{'id'} if $POST->{'id'} =~ /^\d+$/;

    # this catches core_hidden if it's set
    $POST->{'parid'} ||= $POST->{'parid_hidden'};

    my $pub  = LJ::S2::get_public_layers();
    my $ulay = LJ::S2::get_layers_of_user($u);

    my $vars;
    $vars->{u}             = $u;
    $vars->{remote}        = $remote;
    $vars->{no_layer_edit} = $no_layer_edit;
    $vars->{pub}           = $pub;
    $vars->{ulay}          = $ulay;
    $vars->{authas}        = $authas;
    $vars->{authas_html}   = $rv->{authas_html};

    return error_ml('/customize/advanced/index.tt.error.advanced.editing.denied')
        if $no_layer_edit;

    # if we don't have a u, maybe they're an admin and can view stuff anyway?
    my $noactions = 0;
    my $viewall   = $remote && $remote->has_priv( 'siteadmin', 'styleview' );

    if ( $GET->{user} && $viewall ) {
        return error_ml('/customize/advanced/layers.tt.error.cantuseonsystem')
            if $GET->{user} eq 'system';
        $noactions = 1;    # don't let admins change anything
    }
    return error_ml('.error.cantbeauthenticated')
        unless $u;

    return error_ml(
        (
            $remote->{user} eq $u->{user}
            ? '/customize/advanced/layers.tt.error.youcantuseadvanced'
            : '/customize/advanced/layers.tt.error.usercantuseadvanced'
        ),
        undef,
        { authas => $rv->{authas_html} }
    ) unless $u->can_create_s2_styles || $viewall;

    if ( $POST->{'action:create'} && !$noactions ) {

        return error_ml('/customize/advanced/layers.tt.error.maxlayers')
            if keys %$ulay >= $u->count_s2layersmax;

        my $type = $POST->{'type'}
            or return error_ml('/customize/advanced/layers.tt.error.nolayertypeselected');
        my $parid = $POST->{'parid'} + 0
            or return error_ml('/customize/advanced/layers.tt.error.badparentid');
        return error_ml('/customize/advanced/layers.tt.error.invalidlayertype')
            unless $type =~ /^layout|theme|user|i18nc?$/;
        my $parent_type =
            ( $type eq "theme" || $type eq "i18n" || $type eq "user" ) ? "layout" : "core";

        # parent ID is public layer
        if ( $pub->{$parid} ) {

            # of the wrong type
            return error_ml('/customize/advanced/layers.tt.error.badparentid')
                if $pub->{$parid}->{'type'} ne $parent_type;

            # parent ID is user layer, or completely invalid
        }
        else {
            return error_ml('.error.badparentid')
                if !$ulay->{$parid} || $ulay->{$parid}->{'type'} != $parent_type;
        }

        my $id = LJ::S2::create_layer( $u, $parid, $type );
        return error_ml('/customize/advanced/layers.tt.error.cantcreatelayer') unless $id;

        my $lay = {
            'userid' => $u->userid,
            'type'   => $type,
            'b2lid'  => $parid,
            's2lid'  => $id,
        };

        # help user out a bit, creating the beginning of their layer.
        my $s2 = "layerinfo \"type\" = \"$type\";\n";
        $s2 .= "layerinfo \"name\" = \"\";\n\n";
        my $error;
        unless ( LJ::S2::layer_compile( $lay, \$error, { 's2ref' => \$s2 } ) ) {
            return error_ml( '/customize/advanced/layers.tt.error.cantsetuplayer',
                { 'errormsg' => $error } );
        }

        # redirect so they can't refresh and create a new layer again
        return $r->redirect("$LJ::SITEROOT/customize/advanced/layers$authas");
    }

    # delete
    if ( $POST->{'action:del'} && !$noactions ) {

        my $id  = $POST->{'id'} + 0;
        my $lay = LJ::S2::load_layer($id);
        return error_ml('/customize/advanced/layers.tt.error.layerdoesntexist')
            unless $lay;

        return error_ml('/customize/advanced/layers.tt.error.notyourlayer')
            unless $lay->{userid} == $u->userid;

        LJ::S2::delete_layer( $u, $id );
        return $r->redirect("$LJ::SITEROOT/customize/advanced/layers$authas");
    }

    my %active_style = LJ::S2::get_style($u);

    # set up indices for the sort, because it's easier than the convoluted logic
    # of doing all this within the sort itself
    my @parentlayernames;
    my @layernames;
    my @weight;
    my %specialnamelayers;
    my @layerids = keys %$ulay;
    foreach my $layerid (@layerids) {
        my $parent = $ulay->{ $ulay->{$layerid}->{b2lid} } || $pub->{ $ulay->{$layerid}->{b2lid} };
        push @parentlayernames, $parent->{name};

        my $layername = $ulay->{$layerid}->{name};
        push @layernames, $layername;

        my $weight = {
            "Auto-generated Customizations" => 1,    # auto-generated
            ""                              => 2     # empty
        }->{$layername};
        push @weight, $weight;

        $specialnamelayers{$layerid} = 1 if $weight;
    }

    my @sortedlayers = @layerids[
        sort {
            # alphabetically by parent layer's name
            $parentlayernames[$a] cmp $parentlayernames[$b]

              # special case empty names and auto-generated customizations (push them to the bottom)
                || $weight[$a] cmp $weight[$b]

                # alphabetically by layer name (for regular layer names)
                || $layernames[$a] cmp $layernames[$b]

                # Auto-generated customizations then layers with no name sorted by layer id
                || $layerids[$a] <=> $layerids[$b]

        } 0 .. $#layerids
    ];

    my @corelayers = map { $_, $pub->{$_}->{'majorversion'} }
        sort { $pub->{$b}->{'majorversion'} <=> $pub->{$a}->{'majorversion'} }
        grep { $pub->{$_}->{'b2lid'} == 0 && $pub->{$_}->{'type'} eq 'core' && /^\d+$/ }
        keys %$pub;

    my @layouts = ( '', '' );
    push @layouts, map { $_, $pub->{$_}->{'name'} }
        sort { $pub->{$a}->{'name'} cmp $pub->{$b}->{'name'} || $a <=> $b }
        grep { $pub->{$_}->{'type'} eq 'layout' && /^\d+$/ }
        keys %$pub;
    if (%$ulay) {
        my @ulayouts = ();
        push @ulayouts, map {
            $_,
                BML::ml(
                '.createlayer.layoutspecific.select.userlayer',
                { 'name' => $ulay->{$_}->{'name'}, 'id' => $_ }
                )
            }
            sort { $ulay->{$a}->{'name'} cmp $ulay->{$b}->{'name'} || $a <=> $b }
            grep { $ulay->{$_}->{'type'} eq 'layout' }
            keys %$ulay;
        push @layouts, ( '', '---', @ulayouts ) if @ulayouts;
    }

    $vars->{authas_html}       = $rv->{authas_html};
    $vars->{noactions}         = $noactions;
    $vars->{layouts}           = \@layouts;
    $vars->{corelayers}        = \@corelayers;
    $vars->{sortedlayers}      = \@sortedlayers;
    $vars->{active_style}      = \%active_style;
    $vars->{specialnamelayers} = \%specialnamelayers;
    $vars->{ehtml}             = \&LJ::ehtml;
    $vars->{ejs}               = \&LJ::ejs;

    return DW::Template->render_template( 'customize/advanced/layers.tt', $vars );

}

sub styles_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r             = $rv->{r};
    my $POST          = $r->post_args;
    my $u             = $rv->{u};
    my $remote        = $rv->{remote};
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $remote );
    my $GET           = $r->get_args;
    my $authas        = $u->user ne $remote->user ? "?authas=" . $u->user : "";

    my $vars;
    $vars->{u}             = $u;
    $vars->{remote}        = $remote;
    $vars->{no_layer_edit} = $no_layer_edit;
    $vars->{authas_html}   = $rv->{authas_html};
    $vars->{post}          = $POST;

    # if we don't have a u, maybe they're an admin and can view stuff anyway?
    my $noactions = 0;
    my $viewall   = $remote && $remote->has_priv( 'siteadmin', 'styleview' );

    if ( $GET->{user} && $viewall ) {
        return error_ml('/customize/advanced/styles.tt.error.cantuseonsystem')
            if $GET->{user} eq 'system';
        $noactions = 1;    # don't let admins change anything
    }

    return error_ml(
        (
            $remote->{user} eq $u->{user}
            ? '/customize/advanced/styles.tt.error.youcantuseadvanced'
            : '/customize/advanced/styles.tt.error.usercantuseadvanced'
        ),
        undef,
        { authas => $rv->{authas_html} }
    ) unless $u->can_create_s2_styles || $viewall;

    return error_ml('/customize/advanced/index.tt.error.advanced.editing.denied')
        if $no_layer_edit;

    # extra arguments for get requests
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : '';
    my $getextra_amp = $getextra ? "&authas=" . $u->user : '';
    if ($noactions) {
        $getextra     = "?user=" . $u->user;
        $getextra_amp = "&user=" . $u->user;
    }

    $vars->{getextra}     = $getextra;
    $vars->{getextra_amp} = $getextra_amp;

    # style id to edit, if we have one
    # if we have this we're assumed to be in 'edit' mode
    my $id = $GET->{'id'} + 0;

    my $dbh = LJ::get_db_writer();

    # variables declared here, but only filled in if $id
    my ( $core, $layout );         # scalars
    my ( $pub, $ulay, $style );    # hashrefs

    if ($id) {

        # load style
        $style = LJ::S2::load_style($id);
        return error_ml('/customize/advanced/styles.tt.error.stylenotfound') unless $style;

        # check that they own the style
        return error_ml('/customize/advanced/styles.tt.error.notyourstyle')
            unless $style->{userid} == $u->userid;

        # use selected style
        if ( $POST->{'action:usestyle'} && !$noactions ) {

            # save to db and update user object
            $u->set_prop(
                {
                    stylesys => '2',
                    s2_style => $id
                }
            );
            LJ::Hooks::run_hooks( 'apply_theme', $u );
            return $r->redirect("styles$getextra");
        }

        # get public layers
        $pub = LJ::S2::get_public_layers();
        $vars->{pub} = $pub;

        # get user layers
        $ulay = LJ::S2::get_layers_of_user($u);
        $vars->{ulay} = $ulay;

        # find effective layerids being used
        my %eff_layer    = ();
        my @other_layers = ();
        foreach (qw(i18nc layout theme i18n user)) {
            my $lid = $POST->{$_} eq "_other" ? $POST->{"other_$_"} : $POST->{$_};
            next unless $lid;
            $eff_layer{$_} = $lid;

            unless ( $ulay->{ $eff_layer{$_} } || $pub->{ $eff_layer{$_} } ) {
                push @other_layers, $lid;
            }
        }

        # core lid (can't use user core layer)
        $POST->{core} ||= $POST->{core_hidden};
        $core = defined $POST->{core} ? $POST->{core} : $style->{layer}->{core};
        my $highest_core;
        map {
            $highest_core = $_
                if $pub->{$_}->{type} eq 'core'
                && /^\d+$/
                && $pub->{$_}->{majorversion} > $pub->{$highest_core}->{majorversion}
        } keys %$pub;
        unless ($core) {
            $core = $highest_core;

            # update in POST to keep things in sync
            $POST->{core} = $highest_core;
        }
        $style->{layer}->{core} = $highest_core unless $style->{layer}->{core};

        $vars->{core} = $core;

        # layout lid
        $layout = $POST->{'action:change'} ? $eff_layer{'layout'} : $style->{'layer'}->{'layout'};

        # if we're changing core, clear everything
        if (   $POST->{'core'}
            && $style->{'layer'}->{'core'}
            && $POST->{'core'} != $style->{'layer'}->{'core'} )
        {
            foreach (qw(i18nc layout theme i18n user)) {
                delete $eff_layer{$_};
            }
            undef $layout;
        }

        # if we're changing layout, clear everything below
        if (   $eff_layer{'layout'}
            && $style->{'layer'}->{'layout'}
            && $eff_layer{'layout'} != $style->{'layer'}->{'layout'} )
        {
            foreach (qw(theme i18n user)) {
                delete $eff_layer{$_};
            }
        }

        ### process edit actions

        # delete
        if ( $POST->{'action:delete'} && !$noactions ) {
            LJ::S2::delete_user_style( $u, $id );
            undef $id;    # don't show form below
            return $r->redirect("styles$getextra");
        }

        # save changes
        if ( ( $POST->{'action:change'} || $POST->{'action:savechanges'} ) && !$noactions ) {
            $vars->{post_action} = 'change';

            # are they renaming their style?
            if (   $POST->{'stylename'}
                && $style->{'name'}
                && $POST->{'stylename'} ne $style->{'name'} )
            {

                # update db
                my $styleid = $style->{'styleid'};
                LJ::S2::rename_user_style( $u, $styleid, $POST->{stylename} );

                # update style object
                $style->{'name'} = $POST->{'stylename'};
            }

            # load layer info of any "other" layers
            my %other_info = ();
            if (@other_layers) {
                LJ::S2::load_layer_info( \%other_info, \@other_layers );
                foreach (@other_layers) {
                    return error_ml( '/customize/advanced/styles.tt.error.layernotfound',
                        { 'layer' => $_ } )
                        unless exists $other_info{$_};
                    return error_ml( '/customize/advanced/styles.tt.error.layernotpublic',
                        { 'layer' => $_ } )
                        unless $other_info{$_}->{'is_public'};
                }
            }

            # error check layer modifications
            my $get_layername = sub {
                my $lid = shift;

                my $name;
                $name = $pub->{$lid}->{'name'} if $pub->{$lid};
                $name ||= $ulay->{$lid}->{'name'} if $ulay->{$lid};
                $name ||= ml( '.layerid', { 'id' => $lid } );

                return $name;
            };

            # check layer hierarchy
            my $error_check = sub {
                my ( $type, $parentid ) = @_;

                my $lid = $eff_layer{$type};
                next if !$lid;

                my $layer      = $ulay->{$lid} || $pub->{$lid} || LJ::S2::load_layer($lid);
                my $parentname = $get_layername->($parentid);
                my $layername  = $get_layername->($lid);

                # is valid layer type?
                return error_ml(
                    '/customize/advanced/styles.tt.error.invalidlayertype',
                    { 'name' => "<i>$layername</i>", 'type' => $type }
                ) if $layer->{'type'} ne $type;

                # is a child?
                return error_ml(
                    '/customize/advanced/styles.tt.error.layerhierarchymismatch',
                    {
                        'layername'  => "<i>$layername</i>",
                        'type'       => $type,
                        'parentname' => "<i>$parentname</i>"
                    }
                ) unless $layer->{'b2lid'} == $parentid;

                return undef;
            };

            # check child layers of core
            foreach my $type (qw(i18nc layout)) {
                my $errmsg = $error_check->( $type, $core );
                return error_ml($errmsg) if $errmsg;
            }

            # don't check sub-layout layers if there's no layout
            if ($layout) {

                # check child layers of selected layout
                foreach my $type (qw(theme i18n user)) {
                    my $errmsg = $error_check->( $type, $layout );
                    return error_ml($errmsg) if $errmsg;
                }
            }

            # save in database
            my @layers = ( 'core' => $core );
            push @layers, map { $_, $eff_layer{$_} } qw(i18nc layout i18n theme user);
            LJ::S2::set_style_layers( $u, $style->{'styleid'}, @layers );

            # redirect if they clicked the bottom button
            return return $r->redirect("styles$getextra") if $POST->{'action:savechanges'};
        }
        $vars->{id}     = $id;
        $vars->{layout} = $layout;
        $vars->{style}  = $style;
    }
    else {
        # load user styles
        my $ustyle        = LJ::S2::load_user_styles($u);
        my @sortedustyles = sort { $ustyle->{$a} cmp $ustyle->{$b} || $a <=> $b } keys %$ustyle;

        $vars->{sortedustyles} = \@sortedustyles;
        $vars->{ustyle}        = $ustyle;

        # process create action
        if ( ( $POST->{'action:create'} && $POST->{'stylename'} ) && !$noactions ) {

            return error_ml( '/customize/advanced/styles.tt.error.maxstyles2',
                { 'numstyles' => scalar( keys %$ustyle ), 'maxstyles' => $u->count_s2stylesmax } )
                if scalar( keys %$ustyle ) >= $u->count_s2stylesmax;

            my $styleid = LJ::S2::create_style( $u, $POST->{'stylename'} );
            return error_ml('/customize/advanced/styles.tt.error.cantcreatestyle') unless $styleid;

            return $r->redirect("styles?id=$styleid$getextra_amp");
        }

        # load style currently in use
        $u->preload_props('s2_style');

    }

    my $layerselect_sub = sub {
        my ( $type, $b2lid ) = @_;

        my @opts = ();

        my $lid = $POST->{'action:change'} ? $POST->{$type} : $style->{layer}->{$type};
        $lid = $POST->{"other_$type"} if $lid eq "_other";

        # greps, and sorts a list
        my $greplist = sub {
            my $ref = shift;
            return sort { $ref->{$a}->{'name'} cmp $ref->{$b}->{'name'} || $a <=> $b }
                grep {
                my $is_active = LJ::Hooks::run_hook( "layer_is_active", $ref->{$_}->{uniq} );
                       $ref->{$_}->{'type'} eq $type
                    && $ref->{$_}->{'b2lid'} == $b2lid
                    && ( !defined $is_active || $is_active )
                    && !( $pub->{$_} && $pub->{$_}->{is_internal} )
                    && # checking this directly here, as I don't care if the parent layers are internal
                    /^\d+$/
                } keys %$ref;
        };

        # public layers
        my $name = $type eq 'core' ? 'majorversion' : 'name';
        push @opts, map { $_, $pub->{$_}->{$name} } $greplist->($pub);

        # no user core layers
        return { 'lid' => $lid, 'opts' => \@opts } if $type eq 'core';

        # user layers / using an internal layer %
        push @opts, ( '', '---' );
        my $startsize = scalar(@opts);

        # add the current layer if it's internal and the user is using it.
        push @opts,
            (
            $lid,
            LJ::Lang::ml(
                '/customize/advanced/styles.tt.stylelayers.select.layout.user',
                { 'layername' => $pub->{$lid}->{'name'}, 'id' => $lid }
            )
            ) if $lid && $pub->{$lid} && $pub->{$lid}->{is_internal};
        push @opts, map {
            $_,
                LJ::Lang::ml(
                '/customize/advanced/styles.tt.stylelayers.select.layout.user',
                { 'layername' => $ulay->{$_}->{'name'}, 'id' => $_ }
                )
        } $greplist->($ulay);

        # if we didn't push anything above, remove dividing line %
        pop @opts, pop @opts unless scalar(@opts) > $startsize;

        # add option for other layerids
        push @opts,
            (
            '_other', LJ::Lang::ml('/customize/advanced/styles.tt.stylelayers.select.layout.other')
            );

        # add blank option to beginning of list
        unshift @opts, ( '', @opts ? '' : ' ' );
        return { 'lid' => $lid, 'opts' => \@opts };
    };

    $vars->{layerselect_sub} = $layerselect_sub;
    $vars->{ehtml}           = \&LJ::ehtml;

    return DW::Template->render_template( 'customize/advanced/styles.tt', $vars );

}

sub layersource_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r             = $rv->{r};
    my $POST          = $r->post_args;
    my $GET           = $r->get_args;
    my $u             = $rv->{u};
    my $remote        = $rv->{remote};
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

    my $pub = LJ::S2::get_public_layers();

    my $dbr = LJ::get_db_reader();

    my $id = $GET->{'id'};
    return $r->redirect('layerbrowse') unless $id =~ /^\d+$/;

    my $lay = defined $pub->{$id} ? $pub->{$id} : LJ::S2::load_layer($id);
    return error_ml('/customize/advanced/layerbrowse.tt.error.layerdoesntexist')
        unless $lay;

    my $layerinfo = {};
    LJ::S2::load_layer_info( $layerinfo, [$id] );
    my $srcview =
        exists $layerinfo->{$id}->{'source_viewable'}
        ? $layerinfo->{$id}->{'source_viewable'}
        : undef;

    # authorized to view this layer?
    my $isadmin = !defined $pub->{$id} && $remote && $remote->has_priv( 'siteadmin', 'styleview' );

    # public styles are pulled from the system account, so we don't
    # want to check privileges in case they're private styles
    return error_ml('/customize/advanced/layerbrowse.tt.error.cantviewlayer')
        unless defined $pub->{$id} && ( !defined $srcview || $srcview != 0 )
        || $srcview == 1
        || $isadmin
        || $remote && $remote->can_manage( LJ::load_userid( $lay->{userid} ) );

    my $s2code = LJ::S2::load_layer_source($id);

    # get html version of the code?
    if ( $GET->{'fmt'} eq "html" ) {
        my $html;
        my ( $md5, $save_cache );
        if ( $pub->{$id} ) {

            # let's see if we have it cached
            $md5 = Digest::MD5::md5_hex($s2code);
            my $cache =
                $dbr->selectrow_array("SELECT value FROM blobcache WHERE bckey='s2html-$id'");
            if ( $cache =~ s/^\[$md5\]// ) {
                $html = $cache;
            }
            else {
                $save_cache = 1;
            }
        }

        unless ($html) {
            my $cr = new S2::Compiler;
            $cr->compile_source(
                {
                    'source' => \$s2code,
                    'output' => \$html,
                    'format' => "html",
                    'type'   => $pub->{$id}->{'type'},
                }
            );
        }

        if ($save_cache) {
            my $dbh = LJ::get_db_writer();
            $dbh->do( "REPLACE INTO blobcache (bckey, dateupdate, value) VALUES (?,NOW(),?)",
                undef, "s2html-$id", "[$md5]$html" );
        }
        $r->print($html);
        return $r->OK;
    }

    # return text version
    $r->content_type("text/plain");
    my $ua = $r->header_in("User-Agent");
    if ( $ua && $ua =~ /\bMSIE\b/ ) {
        my $filename = "s2source-$id.txt";
        $r->header_out( 'Content-Disposition' => "attachment; filename=$filename" );
    }

    $r->print($s2code);
    return $r->OK;

}

sub layeredit_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r             = $rv->{r};
    my $POST          = $r->post_args;
    my $GET           = $r->get_args;
    my $u             = $rv->{u};
    my $remote        = $rv->{remote};
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

    my $vars;

    # we need a valid id
    my $id;
    $id = $GET->{'id'} if $GET->{'id'} =~ /^\d+$/;
    return error_ml('/customize/advanced/layeredit.tt.error.nolayer')
        unless $id;

    return error_ml('/customize/advanced/index.tt.error.advanced.editing.denied')
        if $no_layer_edit;

    # load layer
    my $lay = LJ::S2::load_layer($id);
    return error_ml('/customize/advanced/layers.tt.error.layerdoesntexist')
        unless $lay;

    # if the b2lid of this layer has been remapped to a new layerid
    # then update the b2lid mapping for this layer
    my $b2lid = $lay->{b2lid};
    if ( $b2lid && $LJ::S2LID_REMAP{$b2lid} ) {
        LJ::S2::b2lid_remap( $remote, $id, $b2lid );
        $lay->{b2lid} = $LJ::S2LID_REMAP{$b2lid};
    }

    # get u of user they are acting as
    $u = LJ::load_userid( $lay->{userid} );

    # is authorized admin for this layer?
    return error_ml('/customize/advanced/layeredit.tt.error.layerunauthorized')
        unless $u && $remote->can_manage($u);

    # check priv and ownership
    return error_ml('/customize/advanced/layeredit.tt.error.stylesunauthorized')
        unless $u->can_create_s2_styles;

    # at this point, they are authorized, allow viewing & editing

    # get s2 code from db - use writer so we know it's up-to-date
    my $dbh    = LJ::get_db_writer();
    my $s2code = LJ::S2::load_layer_source( $lay->{s2lid} );

    # we tried to compile something
    my $build;
    if ( $POST->{'action'} eq "compile" ) {
        return error_ml("error.invalidform") unless LJ::check_form_auth( $POST->{lj_form_auth} );

        $build = "<b>S2 Compiler Output</b> <em>at " . scalar(localtime) . "</em><br />\n";

        my $error;
        $POST->{'s2code'} =~ tr/\r//d;    # just in case
        unless ( LJ::S2::layer_compile( $lay, \$error, { 's2ref' => \$POST->{'s2code'} } ) ) {

            $error =~ s/LJ::S2,.+//s;
            $error =~ s!, .+?(src/s2|cgi-bin)/!, !g;

            $error =~
s/^Compile error: line (\d+), column (\d+)/Compile error: <a href="javascript:moveCursor($1-1,$2)">line $1, column $2<\/a>/;

            $build .=
                "Error compiling layer:\n<pre style=\"border-left: 1px red solid\">$error</pre>";

        }
        else {
            $build .= "Compiled with no errors.\n";
        }
        $r->print($build);
        return $r->OK;
    }

    # load layer info
    my $layinf = {};
    LJ::S2::load_layer_info( $layinf, [$id] );

    # find a title to display on this page
    my $type = $layinf->{$id}->{'type'};
    my $name = $layinf->{$id}->{'name'};

    # find name of parent layer if this is a child layer
    if ( !$name && $type =~ /^(user|theme|i18n)$/ ) {
        my $par = $lay->{'b2lid'} + 0;
        LJ::S2::load_layer_info( $layinf, [$par] );
        $name = $layinf->{$par}->{'name'};
    }

    # Only use the layer name if there is one and it's more than just whitespace
    my $title = "[$type] ";
    $title .= $name && $name =~ /[^\s]/ ? "$name [\#$id]" : "Layer \#$id";
    $vars->{build}  = "Loaded layer $id.";
    $vars->{title}  = $title;
    $vars->{s2code} = $s2code;

    return DW::Template->render_template( 'customize/advanced/layeredit.tt',
        $vars, { no_sitescheme => 1 } );

}

1;
