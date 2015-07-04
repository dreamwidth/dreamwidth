#!/usr/bin/perl
#
# dw/bin/dev/graphs_usage.pl - Graphs usage examples
#
# Authors:
#      Anarres <anarres@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# Gives examples of usage of the DW::Graphs module to make pie, bar, and line
# graphs. This script is only for the purpose of showing how the Graphs module
# works, normally the Graphs module would be used by graph image controller modules
# such as DW::Controller::PaidAccountsGraph, not by a standalone script. A config
# file example.yaml (which just repeats the default settings) is used, but this can
# be left out in which case a graph is made using the default configuration.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use DW::Graphs;
use strict;
use warnings;

# -------------------------- Generate a pie chart --------------------------->
my $pie_ref = {
    "label 1" => 1,
    "label 2" => 0.05,
    "label 3" => 0.07,
    "label 4" => 1.5,
    "label 5" => 0.12,
    "label 6" => 0.06,
};
my $gd = DW::Graphs::pie( $pie_ref, "example.yaml" );

# Print the graph to a file
open(IMG, '>pie.png') or die $!;
binmode IMG;
print IMG $gd->png;

# ---------------------- Generate a bar chart ------------------------------->

my $bar_ref = [ 13.377, 15.9, 145.67788, 123.1111, 0.1, 44.03455, 33.3, 43, 123 ];

# Labels - one label per bar. If labels are not wanted pass empty strings.
# Optinally put "\n" in front of every 2nd label to stop them crowding each-other.
my $bar_labels = [ ( "label 1", "\nlabel 2", "label 3", "\nlabel 4", "label 5",
    "\nlabel 6", "label 7", "\nlabel 8", "label 9" ) ];

my $bar_gd = DW::Graphs::bar( $bar_ref, $bar_labels, 'x-axis label',
                              'y-axis label', "example.yaml" );

# Print the graph to a file
open(IMG, '>bar.png') or die $!;
binmode IMG;
print IMG $bar_gd->png;

# ---------- Generate a bar chart with two (or more) datasets ------------->

# You can have any number of datasets - here there are two
my @values1 = ( 7243, 15901, 26188 );
my @values2 = ( 4243, 12901, 11188 );

# Dataset names to distinguish the datasets, used in the legend. The number
# of dataset names must be the same as the number of datasets!
my $names_ref = [ ( "Dataset 1",  "Dataset 2" ) ];

# labels - one label per bar. The number of labels must be the same as the
# number of values per dataset. If labels are not wanted pass empty strings.
my @bar2_labels = ( "Bar 1", "Bar 2", "Bar 3" );

# Package the input
my $bar2_input = [ [@bar2_labels], [@values1], [@values2] ];

my $bar2_gd = DW::Graphs::bar2( $bar2_input, 'x-axis label', 'y-axis label',
                                $names_ref, "example.yaml" );

# Print the graph to a file
open(IMG, '>bar2.png') or die $!;
binmode IMG;
print IMG $bar2_gd->png;

# --------------------- Generate a line graph -------------------------------->

# Define labels to go along the horizontal axis under the graph.
# If labels are not wanted use empty strings
my @line_labels = ( "1st","2nd","3rd","4th","5th","6th","7th", "8th" );

# Define the datasets - each dataset will form one line on the graph
# Each dataset should have the same length as the number of labels
my @dataset1 = qw( 1900 2035 2078 2140 2141 2200 2460 2470 2576 );
my @dataset2 = qw( 871 996 990 1058 1102 1162 1105 1150 );
my @dataset3 = qw( 200 360 370 471 496 690 758 802 );

# Names for the datasets, for the graph legend
my $line_names = [ "1st dataset", "2nd dataset", "3rd dataset" ];

# Put the data in a format DW::Graphs can deal with
my $line_ref = [ [@line_labels], [@dataset1], [@dataset2], [@dataset3] ];

my $line_gd = DW::Graphs::lines( $line_ref, 'x-axis label', 'y-axis label',
   $line_names, "example.yaml" );

# Print the graph to a file
open(IMG, '>lines.png') or die $!;
binmode IMG;
print IMG $line_gd->png;
