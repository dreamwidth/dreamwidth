#!/usr/bin/perl
#
# DW::Graphs - creates graphs for the statistics system
#
# Authors:
#      Anarres <anarres@dreamwidth.org>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Graphs;

use strict;
use warnings;
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use GD::Graph;
use GD::Graph::bars;
use GD::Graph::hbars;
use GD::Graph::pie;
use GD::Graph::lines;
use GD::Text;
use GD::Graph::colour;
use YAML ();

=head1 NAME

DW::Graphs - creates graphs for the statistics system

=head1 SYNOPSIS

  use DW::Graphs;
  my $pie = DW::Graphs::pie( { Ponies => 5, Rainbows => 1, Unicorns => 3 } );
  # Display $pie->png using your favorite library
  my $bar = DW::Graphs::bar( [ 5, 1, 3 ], [ qw( Ponies Rainbows Unicorns ) ],
                                  'Critter', 'Count' );
  # Display $bar->png using your favorite library
  my $bars = DW::Graphs::bar2( [ [ qw( Ponies Rainbows Unicorns ) ],
                                 [ 5, 1, 3 ], [ 2, 0, 1 ] ],
                               'Critter', 'Count',
                               [ qw( Plain Sparkly ) ] );
  # Display $bars->png using your favorite library
  my $lines = DW::Graphs::lines( [ [ qw( Ponies Rainbows Unicorns ) ],
                                   [ 5, 1, 3 ], [ 2, 0, 1 ] ],
                                 'Critter', 'Count',
                                 [ qw( Plain Sparkly ) ] );
  # Display $lines->png using your favorite library

=cut

# Define colours - the arrays can be over-ridden by config file
my $background = '#f7f7f7';
my $nearly_white = '#f8f8f8';
my $textclr = '#c1272d';
my $clrs = [ '#7eafd2', '#f3973e', '#77cba2', '#edd344', '#a5c640' , '#d87ba9' ];
my $dark_clrs = [ '#11061b', '#920d00', '#0d3d1b', '#490045', '#4e1b05' ];

# Default font and font sizes
my %fonts = (
    font => "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf",
    title_size => 14,
    value_size => 10,
    label_size_pie => 10,
    label_size => 12,
    axis_size => 10,
    legend_size => 12,
);

=head1 API

=head2 C<< DW::Graphs::pie( $data [, $config_filename ] ) >>

Creates pie chart from $data (slice_label => slice_value hashref), using
optional $config_filename to override defaults. Returns a GD::Graph::pie.

See ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.

=cut

sub pie {
    my ( $pie_ref, $config_filename ) = @_;

    # Sort the key-value pairs of %$pie_ref by value:
    # @pie_labels is the keys and @pie_values is the values
    my @pie_labels = sort { $pie_ref->{$a} cmp $pie_ref->{$b} } keys %$pie_ref;
    my @pie_values = map { $pie_ref->{$_} } @pie_labels;

    # Package the data in a way that makes GD::Graph happy
    my $pie = [ [@pie_labels], [@pie_values] ];

    # Default settings (can be over-ridden by config file)
    my %settings = (
        transparent    => 0,      # Set this to 1 for transparent background
        accentclr      => $nearly_white,
        start_angle    => 90,     # Angle of first slice of pie, 0 = 6 o'clock
        suppress_angle => 5,      # Smaller slices than this have no labels
        bgclr          => $background,
        dclrs          => $clrs,
        labelclr       => '#000000',
        valuesclr      => '#000000',
        textclr        => $textclr,
        '3d'           => 0,
    );
    my $image_width = 300;    # Image width in pixels - can be over-ridden
    my $image_height = 300;

    # If there is a config file, get any settings from it
    if ( defined $config_filename ) {
        my $config = YAML::LoadFile( "$LJ::HOME/etc/$config_filename" );

        # Image size
        $image_width = $config->{image_width}
            if defined $config->{image_width};
        $image_height = $config->{image_height}
            if defined $config->{image_height};

        # Over-ride %settings with settings in config file, if they exist
        foreach my $k ( keys %settings ) {
            $settings{$k} = $config->{$k}
                if defined $config->{$k};
        }

        # Over-ride %fonts with font settings in config file, if they exist
        my $config_fonts = $config->{fonts};
        if ( defined $config_fonts ) {
            $fonts{$_} = $config_fonts->{$_}
                foreach keys %$config_fonts;
        }
    }

    # Create graph object
    my $graph = GD::Graph::pie->new( $image_width, $image_height );
    $graph->set( %settings ) or die $graph->error;

    # Fonts defined at top in %fonts, and can be over-ridden by config file
    $graph->set_title_font( $fonts{font}, $fonts{title_size} );
    $graph->set_value_font( $fonts{font}, $fonts{value_size} );
    $graph->set_label_font( $fonts{font}, $fonts{label_size_pie} );

    my $gd = $graph->plot( $pie ) or die $graph->error;
    return $gd;
}

=head2 C<< DW::Graphs::bar( $values_ref, $labels_ref, $xlabel, $ylabel [, $config_filename ] ) >>

Creates bar chart from $values_ref (value arrayref), $labels_ref (label
arrayref), $xlabel, $ylabel, using optional $config_filename to override
defaults. Returns a GD::Graph::bars.

See ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.

=cut

sub bar {
    my ( $values_ref, $labels_ref, $xlabel, $ylabel, $config_filename ) = @_;

    # Package the input as required by GD Graph
    my $input_ref = [ $labels_ref, $values_ref ];

    # Default settings (can be over-ridden by config file)
    my %settings = (
        x_label      => "\r\n$xlabel",
        y_label      => $ylabel,
        show_values  => 1,
        values_space => 1,   # Pixels between top of bar and value above
        b_margin     => 20,  # Bottom margin (makes space for labels)
        t_margin     => 50,  # Top margin - makes space for value above highest bar
        y_min_value  => 0.0, # Stop scale going below zero

        bgclr        => $background,
        fgclr        => 'white',
        boxclr       => '#f4eedc',      # Shaded-in background
        long_ticks   => 1,              # Background grid lines
        accentclr    => $background,    # Colour of grid lines

        labelclr     => '#000000',
        axislabelclr => '#000000',
        legendclr    => '#000000',
        valuesclr    => '#000000',
        textclr      => $textclr,
        transparent  => 0,              # 1 for transparent background
        dclrs        => $clrs,
    );
    my $image_width = 500;    # Image width in pixels - can be over-ridden
    my $image_height = 350;

    # If there is a config file, get any settings from it
    if ( defined $config_filename ) {
        my $config = YAML::LoadFile( "$LJ::HOME/etc/$config_filename" );

        # Image size
        $image_width = $config->{image_width}
            if defined $config->{image_width};
        $image_height = $config->{image_height}
            if defined $config->{image_height};

        # Over-ride %settings with settings in config file, if they exist
        foreach my $k ( keys %settings ) {
            $settings{$k} = $config->{$k}
                if defined $config->{$k};
        }

        # Over-ride %fonts with font settings in config file, if they exist
        my $config_fonts = $config->{fonts};
        if ( defined $config_fonts ) {
            $fonts{$_} = $config_fonts->{$_}
                foreach keys %$config_fonts;
        }
    }

    # Create graph object
    my $graph = GD::Graph::bars->new( $image_width, $image_height );
    $graph->set( %settings ) or die $graph->error;

    # Fonts defined at top in %fonts, and can be over-ridden by config file
    $graph->set_title_font( $fonts{font}, $fonts{title_size} );
    $graph->set_x_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_y_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_x_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_y_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_values_font( $fonts{font}, $fonts{value_size} );

    # Make the graph
     my $gd = $graph->plot( $input_ref ) or die $graph->error;
    return $gd;
}

=head2 C<< DW::Graphs::bar2( $values_ref, $labels_ref, $xlabel, $ylabel [, $config_filename ] ) >>

Creates bar chart with two or more sets of data from $ref ([ [ @value_labels ],
[ @dataset1 ], [ @dataset2 ], ... ]), $xlabel, $ylabel, $names_ref (label
arrayref, must have 1 element per dataset), using optional $config_filename to
override defaults. Returns a GD::Graph::bars.

See ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.

=cut

sub bar2 {
    my ( $ref, $xlabel, $ylabel, $names_ref, $config_filename ) = @_;

    #Default settings (can be over-ridden by config file)
    my %settings = (
        x_label         => "\r\n$xlabel",
        y_label         => $ylabel,
        show_values    => 1,
        values_space   => 1,  # Pixels between top of bar and value above
        b_margin       => 20, # Bottom margin (makes space for labels)
        t_margin       => 50, # Top margin - makes space for value above highest bar
        y_min_value => 0.0,   # Stop scale going below zero

        legend_placement => 'RC',      # Right centre
        cumulate => 'true',            # Put the two datasets in one bar
        bar_spacing => undef,

        shadowclr      => $background,
        bgclr          => $background,
        fgclr          => 'white',
        boxclr         => '#f4eedc', # Shaded-in background
        long_ticks     => 1,         # Background grid lines
        accentclr      => 'white',   # Colour of grid lines
        transparent    => 0,         # 1 for transparent background

        labelclr       => '#000000',
        axislabelclr   => '#000000',
        legendclr      => '#000000',
        valuesclr      => '#000000',
        textclr        => $textclr,
        dclrs          => $clrs,
    );
    my $image_width = 500;    # Image width in pixels - can be over-ridden
    my $image_height = 350;

    # If there is a config file, get any settings from it
    if ( defined $config_filename ) {
        my $config = YAML::LoadFile( "$LJ::HOME/etc/$config_filename" );

        # Image size
        $image_width = $config->{image_width}
            if defined $config->{image_width};
        $image_height = $config->{image_height}
            if defined $config->{image_height};

        # Over-ride %settings with settings in config file, if they exist
        foreach my $k ( keys %settings ) {
            $settings{$k} = $config->{$k}
                if defined $config->{$k};
        }

        # Over-ride %fonts with font settings in config file, if they exist
        my $config_fonts = $config->{fonts};
        if ( defined $config_fonts ) {
            $fonts{$_} = $config_fonts->{$_}
                foreach keys %$config_fonts;
        }
    }

    # Create graph object
    my $graph = GD::Graph::bars->new( $image_width, $image_height );
    $graph->set( %settings ) or die $graph->error;

    # Fonts defined at top in %fonts, and can be over-ridden by config file
    $graph->set_title_font( $fonts{font}, $fonts{title_size} );
    $graph->set_x_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_y_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_x_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_y_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_values_font( $fonts{font}, $fonts{value_size} );
    $graph->set_legend_font( $fonts{font}, $fonts{legend_size} );

    # Set legend
    $graph->set_legend( @$names_ref );

    # Make the graph
    my $gd = $graph->plot( $ref ) or die $graph->error;
    return $gd;
}

=head2 C<< DW::Graphs::bar2( $values_ref, $labels_ref, $xlabel, $ylabel [, $config_filename ] ) >>

Creates line graph with two or more sets of data from $ref ([ [ @value_labels ],
[ @dataset1 ], [ @dataset2 ], ... ]), $xlabel, $ylabel, $names_ref (label
arrayref, must have 1 element per dataset), using optional $config_filename to
override defaults. Returns a GD::Graph::bars.

See ~/dw/bin/dev/graphs_usage.pl for more detailed usage information.

=cut

sub lines {
    my ( $data_ref, $xlabel, $ylabel, $data_names, $config_filename ) = @_;

    #Default settings (can be over-ridden by config file)
    my %settings = (
        x_label       => $xlabel,
        y_label       => $ylabel,
        show_values   => 0,
        transparent   => 0,            # Set this to 1 for transparent background
        line_width    => 1,
        long_ticks    => 1,            # Background grid lines
        line_width    => 4,            # Line width in pixels
        legend_placement => 'RC',      # Right centre

        bgclr         => $background,
        fgclr         => 'white',
        boxclr        => '#f4eedc',    # Shaded-in background colour
        accentclr     => 'lgray',

        labelclr      => '#000000',
        axislabelclr  => '#000000',
        legendclr     => '#000000',
        valuesclr     => '#000000',
        textclr       => $textclr,
        dclrs         => $dark_clrs,
    );
    my $image_width = 750;    # Image width in pixels - can be over-ridden
    my $image_height = 320;

    # If there is a config file, get any settings from it
    if ( defined $config_filename ) {
        my $config = YAML::LoadFile( "$LJ::HOME/etc/$config_filename" );

        # Image size
        $image_width = $config->{image_width}
            if defined $config->{image_width};
        $image_height = $config->{image_height}
            if defined $config->{image_height};

        # Over-ride %settings with settings in config file, if they exist
        foreach my $k ( keys %settings ) {
            $settings{$k} = $config->{$k}
                if defined $config->{$k};
        }

        # Over-ride %fonts with font settings in config file, if they exist
        my $config_fonts = $config->{fonts};
        if ( defined $config_fonts ) {
            $fonts{$_} = $config_fonts->{$_}
                foreach keys %$config_fonts;
        }
    }

    # Create Graph
    my $graph = GD::Graph::lines->new( $image_width, $image_height );
    $graph->set( %settings ) or die $graph->error;
    $graph->set( line_types => [1, 2, 3, 4] ); # 1:solid 2:dash 3:dot 4:dot-dash
    $graph->set_legend( @$data_names );

    # Fonts defined at top in %fonts, and can be over-ridden by config file
    $graph->set_title_font( $fonts{font}, $fonts{title_size} );
    $graph->set_x_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_y_label_font( $fonts{font}, $fonts{label_size} );
    $graph->set_x_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_y_axis_font( $fonts{font}, $fonts{axis_size} );
    $graph->set_values_font( $fonts{font}, $fonts{value_size} );
    $graph->set_legend_font( $fonts{font}, $fonts{legend_size} );

    # Make the plot
    my $gd = $graph->plot( $data_ref ) or die $graph->error;
    return $gd;
}

1;

=head1 AUTHORS AND COPYRIGHT

Authors: Anarres <anarres@dreamwidth.org>

Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
