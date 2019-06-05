#!/usr/bin/perl
#
# LJ::Widget::ImportChooseData
#
# Renders the form for a user to choose data to import.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::ImportChooseData;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

sub need_res      { qw( stc/importer.css js/jquery.importer.js ) }
sub need_res_opts { group => "jquery" }

sub render_body {
    my ( $class, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return "" unless LJ::isu($u);

    my @options = (
        {
            name         => 'lj_bio',
            display_name => $class->ml('widget.importstatus.item.lj_bio'),
            desc         => $class->ml('widget.importchoosedata.item.lj_bio.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_friends',
            display_name => $class->ml('widget.importstatus.item.lj_friends'),
            desc         => $class->ml('widget.importchoosedata.item.lj_friends.desc'),
            selected     => 0,
            comm_okay    => 0,
        },
        {
            name         => 'lj_friendgroups',
            display_name => $class->ml('widget.importstatus.item.lj_friendgroups'),
            desc         => $class->ml(
                'widget.importchoosedata.item.lj_friendgroups.desc',
                { sitename => $LJ::SITENAMESHORT }
            ),
            selected  => 0,
            comm_okay => 0,
        },
        {
            name         => 'lj_entries',
            display_name => $class->ml('widget.importstatus.item.lj_entries'),
            desc         => $class->ml('widget.importchoosedata.item.lj_entries.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_comments',
            display_name => $class->ml('widget.importstatus.item.lj_comments'),
            desc         => $class->ml('widget.importchoosedata.item.lj_comments.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_tags',
            display_name => $class->ml('widget.importstatus.item.lj_tags'),
            desc         => $class->ml('widget.importchoosedata.item.lj_tags.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_userpics',
            display_name => $class->ml('widget.importstatus.item.lj_userpics'),
            desc         => $class->ml(
                'widget.importchoosedata.item.lj_userpics.desc',
                { sitename => $LJ::SITENAMESHORT }
            ),
            selected  => 0,
            comm_okay => 1,
        },
    );

    my @fixup_options = (
        {
            name         => 'lj_entries_remap_icon',
            display_name => $class->ml('widget.importstatus.item.lj_entries_remap_icon'),
            desc         => $class->ml('widget.importchoosedata.item.lj_entries_remap_icon.desc'),
            selected     => 0,
        },
    );

    my $ret;

    $ret .= "<h2 class='gradient'>" . $class->ml('widget.importchoosedata.header2') . "</h2>";

    $ret .= $class->start_form;
    $ret .= "<div class='importoptions'>";

    foreach my $option (@options) {
        next unless $u->is_person || $option->{comm_okay};

        $ret .= "<div class='importoption'>";
        $ret .= $class->html_check(
            name     => $option->{name},
            id       => $option->{name},
            value    => 1,
            selected => $option->{selected},
        );
        $ret .= " <label for='$option->{name}'>$option->{display_name}</label>";
        $ret .= "<?p $option->{desc} p?>";
        $ret .= "</div>";
    }

    $ret .= "</div>";

    if (@fixup_options) {
        $ret .=
            "<h2 class='gradient'>" . $class->ml('widget.importchoosedata.header.fixup') . "</h2>";
        $ret .= "<div class='importoptions'>";

        foreach my $option (@fixup_options) {
            $ret .= "<div class='importoption'>";
            $ret .= $class->html_check(
                name     => $option->{name},
                id       => $option->{name},
                value    => 1,
                selected => $option->{selected},
            );
            $ret .= " <label for='$option->{name}'>$option->{display_name}</label>";
            $ret .= "<?p $option->{desc} p?>";
            $ret .= "</div>";
        }

        $ret .= "</div>";
    }

    $ret .= $class->html_submit( submit => $class->ml('widget.importchoosedata.btn.continue') );
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return ( notloggedin => 1 ) unless LJ::isu($u);

    my $has_items = 0;
    foreach my $key ( keys %$post ) {
        if ( $key =~ /^lj_/ && $post->{$key} ) {
            $has_items = 1;
            last;
        }
    }
    return ( ret => $class->ml('widget.importchoosedata.error.noitemsselected') )
        unless $has_items;

    # if we're doing the suboption, turn on the parent option
    $post->{lj_entries} = 1
        if $post->{lj_entries_remap_icon};

    # if comments are on, turn entries on
    $post->{lj_entries} = 1
        if $post->{lj_comments};

    # okay, this is kinda hacky but turn on the right things so we can do
    # a proper entry import...
    if ( $post->{lj_entries} ) {
        $post->{lj_tags}         = 1;
        $post->{lj_friendgroups} = 1;
    }

    # if friends are on, turn on groups
    $post->{lj_friendgroups} = 1
        if $post->{lj_friends};

    # everybody needs a verifier
    $post->{lj_verify} = 1;

    # and finally, make sure modes that make no sense for communities are off
    if ( $u->is_community ) {
        $post->{lj_friends}      = 0;
        $post->{lj_friendgroups} = 0;
    }

    return ( ret => LJ::Widget::ImportConfirm->render(%$post) );
}

1;
