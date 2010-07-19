#!/usr/bin/perl
#
# DW::Controller::Latest::Mood
#
# Mood of the service toy.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::Latest::Mood;
use strict;
use warnings;
use DW::Routing;
use DW::Template;
use DW::Request;
use DW::Mood;
use JSON;

DW::Routing->register_string( "/latest/mood", \&mood_handler );

sub mood_handler {
    my $r = DW::Request->get;

    my $formats = {
        html => sub {
            DW::Template->render_template( "latest/mood.tt", $_[0] );
        },
        json => sub {
            $r->status( 503 ) if $_[0]->{no_data};
            $r->print( objToJson( $_[0] ) );
            return $r->OK;
        },
    };
    
    my $format = $formats->{ $_[0]->format || 'html' };

    return $r->NOT_FOUND if ! $format;

    my $moods = LJ::MemCache::get( "latest_moods" ) || [];
    my $out = {};

    if ( scalar @$moods ) {
        my %counts;
        my $score = 0;
        my $count = scalar @$moods;

        my $metadata = DW::Mood->get_moods;

        foreach my $moodid ( @$moods ) {
            $score += $metadata->{$moodid}->{weight} || 50;
            $counts{$metadata->{$moodid}->{name}}++;
        }

        my @names = sort { $counts{$b} <=> $counts{$a} || $a cmp $b } keys %counts;
        my %top_counts = map { ($_,$counts{$_}) } @names[0..5];
        my @top_mood;
        foreach my $mood ( @names ) {
            if ( $counts{$mood} == $counts{$names[0]} ) {
                push @top_mood, $mood;
            } else {
                last;
            }
        }

        $out->{counts} = \%top_counts;
        $out->{score} = int($score / $count);
        $out->{score} = $r->get_args->{score} if defined $r->get_args->{score};
        $out->{highest} = [ @names[0..5] ];
        $out->{top_mood} = \@top_mood;
    } else {
        $out->{no_data} = 1;
    }

    return $format->( $out );
}

1;
