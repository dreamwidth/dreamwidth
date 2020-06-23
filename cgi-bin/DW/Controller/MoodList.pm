#!/usr/bin/perl
#
# DW::Controller::MoodList
#
# View all images in a mood theme, or a list of public mood themes.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::MoodList;

use strict;

use DW::Routing;
use DW::Controller;
use DW::Template;

use DW::Mood;

use POSIX qw( ceil );

DW::Routing->register_string( '/moodlist', \&main_handler, app => 1 );

sub main_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $args = $r->get_args;
    my $vars = {};

    {    # initial setup for all page templates - mood info and visible themes

        my $moods = DW::Mood->get_moods;
        my @mlist = map { $moods->{$_} }
            sort { $moods->{$a}->{name} cmp $moods->{$b}->{name} } keys %$moods;

        my @themes = DW::Mood->public_themes;
        @themes = sort { lc( $a->{name} ) cmp lc( $b->{name} ) } @themes;

        $vars->{moods}  = $moods;
        $vars->{mlist}  = \@mlist;
        $vars->{themes} = \@themes;
    }

    # image loading helper sub for all pages
    # args: theme id, mood name
    $vars->{load_image} = sub {
        my $tobj = DW::Mood->new( $_[0] );
        return {} unless $tobj;

        my %pic;
        $tobj->get_picture( $tobj->mood_id( $_[1] ), \%pic );
        return \%pic;
    };

    unless ( defined $args->{moodtheme} ) {

        {    # calculate pagination
            my $page      = int( $args->{page} || 0 ) || 1;
            my $page_size = 15;
            my $first     = ( $page - 1 ) * $page_size;
            my $total     = scalar( @{ $vars->{themes} } );

            my $total_pages = POSIX::ceil( $total / $page_size );

            my $last = $page_size * $page - 1;
            if ( $last >= $total ) {
                $last = $total - 1;
            }

            $vars->{pages} = {
                current     => $page,
                total_pages => $total_pages,
                first_item  => $first,
                last_item   => $last,
            };
        }

        # see if the user changed the shown moods

        if ( $args->{theme1} && $args->{theme2} && $args->{theme3} && $args->{theme4} ) {
            $vars->{show_moods} =
                [ $args->{theme1}, $args->{theme2}, $args->{theme3}, $args->{theme4} ];
        }
        else {
            $vars->{show_moods} = [qw( happy sad angry tired )];
        }

        $vars->{mood_select} = [ map { $_->{name}, $_->{name} } @{ $vars->{mlist} } ];

        return DW::Template->render_template( 'mood/index.tt', $vars );
    }

    # from here, we want to view all the images for a given mood theme

    $vars->{themeid} = $args->{moodtheme};

    {    # load any non-public themes from the specified owner

        my @user_themes;
        my $remote = $rv->{remote};

        # Check if the (non-system) user is logged in and didn't specify an owner.
        # If so, append their private mood themes.
        if ( ( $remote->user ne 'system' ) && !$args->{ownerid} ) {
            @user_themes = DW::Mood->get_themes( { ownerid => $remote->id } );
        }
        elsif ( $args->{ownerid} ) {
            @user_themes = DW::Mood->get_themes(
                {
                    themeid => $args->{moodtheme},
                    ownerid => $args->{ownerid}
                }
            );
        }

        $vars->{user_themes} = [ sort { lc( $a->{name} ) cmp lc( $b->{name} ) } @user_themes ];
    }

    my $scope = '/mood/index.tt';

    # see if the user can even view this theme
    my $theme = ( grep { $_->{moodthemeid} == $args->{moodtheme} }
            ( @{ $vars->{themes} }, @{ $vars->{user_themes} } ) )[0];

    return error_ml("$scope.error.cantviewtheme") unless $theme;

    if ( $args->{ownerid} ) {
        $vars->{ownerinfo} = sprintf( "%s - %s",
            LJ::ehtml( $theme->{name} ),
            LJ::ljuser( LJ::get_username( $args->{ownerid} ) ) );
    }
    else {
        $vars->{theme_select} = [
            ( map { $_->{moodthemeid}, $_->{name} } @{ $vars->{themes} } ),
            ( @{ $vars->{user_themes} } ? ( 0, "---" ) : () ),
            ( map { $_->{moodthemeid}, $_->{name} } @{ $vars->{user_themes} } )
        ];
    }

    # Does the user want the table format, or the tree format?

    return DW::Template->render_template( 'mood/table.tt', $vars )
        unless defined $args->{mode} && $args->{mode} eq 'tree';

    $vars->{mode} = 'tree';

    my %lists = ();

    foreach (
        sort { $vars->{moods}->{$a}->{name} cmp $vars->{moods}->{$b}->{name} }
        keys %{ $vars->{moods} }
        )
    {
        my $m = $vars->{moods}->{$_};
        $lists{ $m->{'parent'} } //= [];
        push @{ $lists{ $m->{'parent'} } }, $m;
    }

    $vars->{lists} = \%lists;

    return DW::Template->render_template( 'mood/tree.tt', $vars );
}

1;
