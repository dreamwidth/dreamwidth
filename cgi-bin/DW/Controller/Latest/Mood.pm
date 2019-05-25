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
use LJ::JSON;

DW::Routing->register_string( "/latest/mood", \&mood_handler, formats => [ 'html', 'json' ] );

sub mood_handler {
    my $r = DW::Request->get;

    my $formats = {
        html => sub {
            DW::Template->render_template( "latest/mood.tt", $_[0] );
        },
        json => sub {
            $r->status(503) if $_[0]->{no_data};
            $r->print( to_json( $_[0] ) );
            return $r->OK;
        },
    };

    my $format = $formats->{ $_[0]->format };

    my $moods   = LJ::MemCache::get("latest_moods") || [];
    my $out     = {};
    my $num_top = 5;
    my $count   = scalar @$moods;

    if ($count) {
        my %counts;
        my $score = 0;

        my $metadata = DW::Mood->get_moods;

        foreach my $moodid (@$moods) {
            next unless $metadata->{$moodid};
            $score += $metadata->{$moodid}->{weight} || 50;
            $counts{ $metadata->{$moodid}->{name} }++;
        }

        my @counts_keys = keys %counts;
        my $to_show     = scalar @counts_keys > $num_top ? $num_top : scalar @counts_keys;

        my @names      = sort { $counts{$b} <=> $counts{$a} || $a cmp $b } @counts_keys;
        my @highest    = @names[ 0 .. ( $to_show - 1 ) ];
        my %top_counts = map { ( $_, $counts{$_} ) } @highest;
        my @top_mood;
        foreach my $mood (@names) {
            if ( $counts{$mood} == $counts{ $names[0] } ) {
                push @top_mood, $mood;
            }
            else {
                last;
            }
        }

        $out->{counts}   = \%top_counts;
        $out->{score}    = int( $score / $count );
        $out->{score}    = $r->get_args->{score} if defined $r->get_args->{score};
        $out->{highest}  = \@highest;
        $out->{top_mood} = \@top_mood;
    }
    else {
        $out->{no_data} = 1;
    }

    return $format->($out);
}

1;
