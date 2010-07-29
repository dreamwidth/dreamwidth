#!/usr/bin/perl
#
# DW::Graphs - creates graphs for the statistics system
#
# Authors:
#      Anarres <anarres@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Graphs;

use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl'; 
use GD::Graph;
use GD::Graph::bars;
use GD::Graph::hbars;
use GD::Graph::pie;
use GD::Graph::lines;
use GD::Text;
use GD::Graph::colour;
GD::Graph::colour::read_rgb("$LJ::HOME/etc/clrs.txt")
    or die "cannot read colours";

# Generates a pie chart. The argument is a hashref of labels and values.
# Returns graph object $gd which can be printed with the command: print $gd->png;
# See ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.
sub pie {
    my ( $pie_ref ) = @_;

    # Sort the key-value pairs of %$pie_ref by value:
    # @pie_labels is the keys and @pie_values is the values
    my @pie_labels = sort { $pie_ref->{$a} cmp $pie_ref->{$b} } keys %$pie_ref;
    my @pie_values = map { $pie_ref->{$_} } @pie_labels;

    # Package the data in a way that makes GD::Graph happy
    my $pie = [ [@pie_labels], [@pie_values] ];

    # Create graph object
    my $graph = GD::Graph::pie->new( 300, 300 );
    $graph->set(
        transparent    => 0,      # Set this to 1 for transparent background
        accentclr      => 'nearly_white', 
        start_angle    => 90,     # Angle of first slice of pie, 0 = 6 o'clock
        suppress_angle => 5,      # Smaller slices than this have no labels
        bgclr          => 'background',
        dclrs          => [ qw( pie_blue pie_orange pie_bluegreen pie_green
                           pie_yellow pie_pink ) ], 
        labelclr       => '#000000',
        valuesclr      => '#000000',
        textclr        => 'dw_red',
        '3d'           => 0,
    ) or die $graph->error;

    # FIXME: make the pathnames and font sizes configurable
    $graph->set_title_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 14);
    $graph->set_value_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);

    my $gd = $graph->plot( $pie ) or die $graph->error;
    return $gd;
} 

# Generates a bar chart. Arguments: a ref to an array of values, a ref to an
# array of labels, title, x-axis label, y-axis label. # Returns graph object
# $gd which can be printed with the command: print $gd->png; see 
# graphs_usage.pl for more detailed usage information.
sub bar {
    my ( $values_ref, $labels_ref, $xlabel, $ylabel ) = @_;

    # Package the input as required by GD Graph
    my $input_ref = [ $labels_ref, $values_ref ];

    # Create graph object
    my $graph = GD::Graph::bars->new(500, 350);

    # Graph settings
      $graph->set( 
            x_label         => "\n$xlabel",
            y_label         => $ylabel,
            show_values    => 1,
            values_space   => 1, # Pixels between top of bar and value above
            b_margin       => 20, # Bottom margin (makes space for labels)
            bar_spacing    => 50, # Higher value = thinner bars

            bgclr          => 'background',
            fgclr          => 'white',
            boxclr         => '#f4eedc', # Shaded-in background
            long_ticks     => 1,         # Background grid lines
            accentclr      => 'lgray',   # Colour of grid lines
            accent_treshold => 500,      # Get rid of outline around bars

            labelclr       => '#000000',
            axislabelclr   => '#000000',
            legendclr      => '#000000',
            valuesclr      => '#000000',
            textclr        => 'dw_red',

            transparent    => 0,         # 1 for transparent background
            dclrs          => [ qw( pie_blue pie_orange pie_bluegreen pie_green
                               pie_yellow pie_pink ) ],
      ) or die $graph->error;

    # FIXME: make the pathnames and font sizes configurable
    $graph->set_title_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 14);
    $graph->set_x_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_y_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_x_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_y_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_values_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);

    # Make the graph
     my $gd = $graph->plot( $input_ref ) or die $graph->error;
    return $gd;
} 

# Generates a bar chart with two or more sets of data represented by each bar.
# Arguments: a reference containing labels and datasets, x-axis label,
# y-axis label, ref to array of names for datasets. Returns graph object 
# $gd which can be printed with the command: print $gd->png; see 
# ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.
sub bar2 {
    my ( $ref, $xlabel, $ylabel, $names_ref ) = @_;

    # Create graph object
    my $graph = GD::Graph::bars->new(500, 350);

    # Graph settings
    $graph->set( 
        x_label         => "\n$xlabel",
        y_label         => $ylabel,
        show_values    => 1,
        values_space   => 1, # Pixels between top of bar and value above
        b_margin       => 20, # Bottom margin (makes space for labels)
        bar_spacing    => 50, # Higher value = thinner bars
        legend_placement => 'RC',      # Right centre
        cumulate => 'true',  # Put the two datasets in one bar

        shadowclr      => 'background',
        bgclr          => 'background',
        fgclr          => 'white',
        boxclr         => '#f4eedc', # Shaded-in background 
        long_ticks     => 1,         # Background grid lines
        accentclr      => 'white',   # Colour of grid lines
        transparent    => 0,         # 1 for transparent background
        #accent_treshold => 500,      # Get rid of outline around bars

        labelclr       => '#000000',
        axislabelclr   => '#000000',
        legendclr      => '#000000',
        valuesclr      => '#000000',
        textclr        => 'dw_red',

        dclrs          => [ qw( pie_blue pie_orange pie_bluegreen pie_green
                           pie_yellow pie_pink ) ],
    ) or die $graph->error;

    # FIXME: make the pathnames and font sizes configurable
    $graph->set_title_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 14);
    $graph->set_x_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_y_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_x_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_y_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_values_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_legend_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);

    # Set legend
    $graph->set_legend( @$names_ref );

    # Make the graph
    my $gd = $graph->plot( $ref ) or die $graph->error;
    return $gd;
}

# Generates a line graph. Arguments: a reference containing labels and datasets,
# x-axis label, y-axis label, ref to array of names for datasets. Returns
# graph object $gd which can be printed with the command: print $gd->png; see
# ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.
sub lines {
    my ( $data_ref, $xlabel, $ylabel, $data_names ) = @_;

    # Create new Graph object $graph 750px by 320 px
    my $graph = GD::Graph::lines->new(750, 320);

    # Graph settings:
    $graph->set( 
        x_label       => $xlabel,
        y_label       => $ylabel,
        show_values   => 0,
        transparent   => 0,            # Set this to 1 for transparent background
        line_width    => 1,
        long_ticks    => 1,            # Background grid lines
        line_width    => 4,            # Line width in pixels
        legend_placement => 'RC',      # Right centre

        bgclr         => 'background',
        fgclr         => 'white',
        boxclr        => '#f4eedc',    # Shaded-in background colour
        accentclr     => 'lgray',

        labelclr       => '#000000',
        axislabelclr   => '#000000',
        legendclr      => '#000000',
        valuesclr      => '#000000',
        textclr        => 'dw_red',
        dclrs                 => [ qw( solid0 solid1 solid2 solid3 solid4 ) ],
        ) or die $graph->error;

    $graph->set( line_types => [1, 2, 3, 4] ); # 1:solid 2:dash 3:dot 4:dot-dash

    # FIXME: make the pathnames and font sizes configurable
    $graph->set_title_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 14);
    $graph->set_legend_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_x_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_y_label_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 12);
    $graph->set_x_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_y_axis_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);
    $graph->set_values_font("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", 10);

    # Set legend
    $graph->set_legend( @$data_names );

    # Make the plot
    my $gd = $graph->plot( $data_ref ) or die $graph->error;
    return $gd;
}
1;
