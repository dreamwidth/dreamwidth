#!/usr/bin/perl
#
# DW::Formats
#
# A helper package for getting info about DW's supported markup formats. Each of
# these named formats represents a specific set of expected formatting
# behaviors, and each entry and comment is assigned a specific format. By
# remembering the expected formats of archived content, we can always display it
# as originally intended despite changing our markup behaviors over time.
#
# When adding a new format, you must also:
# - Implement its markup transformations in LJ::CleanHTML. We're deliberately
#   sacrificing some convenience in this package to keep CleanHTML more legible.
# - If it replaces an existing format, update @active_formats, %format_upgrades,
#   and $default_format accordingly.
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Formats;

use strict;

our @active_formats = qw( html_casual1 markdown0 html_raw0 );
our $default_format = 'html_casual1';

# obsolete version => newest version:
our %format_upgrades = ( html_casual0 => 'html_casual1', );

our %formats = (
    html_casual0 => {
        id   => 'html_casual0',
        name => "Casual HTML (legacy 0)",
        description =>
"Text with normal line breaks, plus HTML tags for formatting. Doesn't support \@mentions.",
    },
    html_casual1 => {
        id   => 'html_casual1',
        name => "Casual HTML",
        description =>
            "Text with normal line breaks, plus \@mentions and HTML tags for formatting.",
    },
    html_raw0 => {
        id   => 'html_raw0',
        name => "Raw HTML",
        description =>
"Pre-formatted HTML. Doesn't automatically detect paragraph breaks, and doesn't support \@mentions.",
    },
    html_extra_raw => {
        id   => 'html_extra_raw',
        name => "Raw HTML (external source)",
        description =>
"Pre-formatted HTML from a feed or some other external source. Doesn't support special Dreamwidth tags like &lt;user&gt;.",
    },
    markdown0 => {
        id   => 'markdown0',
        name => "Markdown",
        description =>
"Markdown, a lightweight text format that makes paragraphs from normal line breaks and provides shortcuts for the most common HTML tags. Supports \@mentions, and supports real HTML tags for more complex formatting.",
    },
);

# Legacy aliases:
$formats{markdown} = $formats{markdown0};

# Builds items that can be passed to an LJ::html_select for picking a format,
# plus the format that should be initially selected.
# Args: opts hash like (current => "format", preferred => "format").
# Returns: Hashref like {selected => "format", items => [...]}. (Unfortunately,
# LJ::html_select doesn't support just setting selected=true on one of the items,
# so we need to return an extra value.)
sub select_items {
    my %opts = @_;

    # Canonicalize em
    my $current   = validate( $opts{current} );
    my $preferred = validate( $opts{preferred} );

    my @formats  = @active_formats;
    my $selected = $default_format;

    # Use the content's existing format if possible, then fall back to the
    # user's preference (IF it's active or has an active replacement), then the
    # site default.
    if ($current) {
        push( @formats, $current ) unless grep( $_ eq $current, @formats );
        $selected = $current;
    }
    elsif ( $preferred && is_active($preferred) ) {
        $selected = $preferred;
    }
    elsif ( $preferred && is_active( upgrade($preferred) ) ) {
        $selected = upgrade($preferred);
    }

    return {
        selected => $selected,
        items =>
            [ map { { value => $formats{$_}->{id}, text => $formats{$_}->{name}, } } @formats ],
    };
}

# Return the canonical version of the provided format ID if valid, empty string if not.
sub validate {
    my $format = $_[0];
    if ( $formats{$format} ) {
        return $formats{$format}->{id};
    }
    else {
        return '';
    }
}

sub is_active {
    my $format = $_[0];
    if ( grep( $_ eq $format, @active_formats ) ) {
        return 1;
    }
    return 0;
}

sub display_name {
    my $format = $_[0];
    if ( $formats{$format} ) {
        return $formats{$format}->{name};
    }
    return "Unknown markup format";
}

# If the provided format ID was replaced by a newer format, return the newest ID
# in its lineage.
sub upgrade {
    my $format = validate( $_[0] );
    return $format_upgrades{$format} || $format;
}

# Convenience aliases for email posts -- these should never be entered into the
# database as an editor prop value, but email posts pass these to validate() as
# a way of asking which format a user currently means if they just said 'html'
# or 'markdown'. (Why not just use 'html' and 'markdown' as the "current"
# aliases? Because 'markdown' is already in use by old email comments.)
$formats{markdown_latest}    = $formats{ upgrade('markdown0') };
$formats{html_casual_latest} = $formats{ upgrade('html_casual1') };
