#!/usr/bin/perl
#
# LJ::Widget::ImportConfirm
#
# Renders the form for a user to confirm their import.
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

package LJ::Widget::ImportConfirm;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Logic::Importer;

sub need_res { qw( stc/importer.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return "" unless LJ::isu($u);

    my $items_fields;
    my @items_display;
    foreach my $item ( keys %opts ) {
        next unless $item =~ /^lj_/ && $opts{$item};
        $items_fields .= $class->html_hidden( $item => 1 );
        push @items_display, $class->ml("widget.importstatus.item.$item")
            unless $item eq 'lj_verify';
    }

    my $ret;

    $ret .= "<h2 class='gradient'>" . $class->ml('widget.importconfirm.header') . "</h2>";
    $ret .= "<p>" . $class->ml('widget.importconfirm.intro') . "</p>";

    my $imports = DW::Logic::Importer->get_import_data_for_user($u);
    if ( $imports->[0]->[3] ) {
        $ret .= "<p>"
            . $class->ml( 'widget.importconfirm.source.comm',
            { user => $imports->[0]->[2], host => $imports->[0]->[1], comm => $imports->[0]->[3] } )
            . "</p>";
    }
    else {
        $ret .= "<p>"
            . $class->ml( 'widget.importconfirm.source',
            { user => $imports->[0]->[2], host => $imports->[0]->[1] } )
            . "</p>";
    }
    $ret .= "<p>"
        . $class->ml( 'widget.importconfirm.destination',
        { user => $u->ljuser_display, host => $LJ::SITENAMESHORT } )
        . "</p>";
    $ret .= "<p>"
        . $class->ml( 'widget.importconfirm.items', { items => join( '<br />', @items_display ) } )
        . "</p>";

    $ret .= $class->start_form;
    $ret .= $items_fields;
    $ret .= "<p><strong>" . $class->ml('widget.importconfirm.warning') . "</strong><br />";
    $ret .= $class->html_submit( submit => $class->ml('widget.importconfirm.btn.import') ) . "</p>";
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return ( notloggedin => 1 ) unless LJ::isu($u);

    # default job status
    my @jobs = (
        [ 'lj_verify',       'ready' ],
        [ 'lj_userpics',     'init' ],
        [ 'lj_bio',          'init' ],
        [ 'lj_tags',         'init' ],
        [ 'lj_friendgroups', 'init' ],
        [ 'lj_friends',      'init' ],
        [ 'lj_entries',      'init' ],
        [ 'lj_comments',     'init' ],
    );

    my %suboptions = ( lj_entries => ['lj_entries_remap_icon'], );

    # get import_data_id for the user
    my $imports = DW::Logic::Importer->get_import_data_for_user($u);
    my $id      = $imports->[0]->[0];

    # schedule userpic, bio, and tag imports
    foreach my $item (@jobs) {
        next unless $post->{ $item->[0] };

        my $suboption = $suboptions{ $item->[0] } || [];
        my %opts;
        foreach (@$suboption) {
            $opts{$_} = 1 if $post->{$_};
        }

        if ( my $error =
            DW::Logic::Importer->set_import_items_for_user( $u, item => $item, id => $id ) )
        {
            return ( ret => $error );
        }

        if (
            my $error = DW::Logic::Importer->set_import_data_options_for_user(
                $u,
                import_data_id => $id,
                %opts
            )
            )
        {
            return ( ret => $error );
        }
    }

    return ( refresh => 1 );
}

1;
