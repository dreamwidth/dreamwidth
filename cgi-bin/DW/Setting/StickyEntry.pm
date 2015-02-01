#!/usr/bin/perl
#
# DW::Setting::StickyEntry - set which entry should be used as a sticky entry on top of the journal
#
# Authors:
#      Rebecca Freiburg <beckyvi@gmail.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Setting::StickyEntry;
use base 'LJ::Setting';
use strict;

sub should_render {
    $_[1] ? 1 : 0;
}

sub label {
    $_[0]->ml( 'setting.stickyentry.label2' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    my @stickies = $u->sticky_entries;
    my $username = $u->user;

    foreach my $i ( 1...$u->count_max_stickies ) {
        my $url = "";
        my $placeholder = "";
        my $e = $stickies[$i - 1];
        if ( $e ) {
            $url = $e->url;
        } else {
            $placeholder = $u->journal_base . "/1234.html" if $i == 1;
        }
        my $textentry = $errs ? $class->get_arg( $args, "stickyid${i}" ) : $url;

        $ret .= "<label for='${key}stickyid${i}'>" . $class->ml( 'setting.stickyentryi.label', { stickyid => $i } ) . " </label>";
        $ret .= LJ::html_text({
            name  => "${key}stickyid${i}",
            id    => "${key}stickyid${i}",
            class => "text",
            value => $textentry,
            placeholder => $textentry ? "" : $placeholder,
            size  => 50,
            maxlength => 100,
        });
        $ret .= q{ - <a href='} . $e->url . q{'>} . ( $e->subject_html || "(no subject)" ) . q{</a>} if $e;
        $ret .= "<br>";

    }

    # returns an error if any of the stickies are incorrectly formatted.
    my $errdiv = $class->errdiv( $errs, "stickyid" );
    $ret .= "$errdiv<br>" if $errdiv;

    $ret .= "<em>" . $class->ml( 'setting.stickyentry.details.label' ) . "</em>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $max_sticky_count = $u->count_max_stickies;
    my @stickies;
    # Create a hash that we will use to check for duplicate entries.
    my %unique = ();
    my $username = $u->user;

    for my $i ( 1 ... $max_sticky_count ) {
        my $stickyi = $class->get_arg( $args, "stickyid${i}" ) || '';

        # blank form entry
        next unless $stickyi;

        $stickyi = LJ::text_trim( $stickyi, 0, 100 );
        my $e = LJ::Entry->new_from_url_or_ditemid( $stickyi, $u );
        if ( $e ) {
            my $ditemid = $e->ditemid;
            if ( $unique{$ditemid} ) {
                $class->errors( "stickyid" => ( $class->ml( 'setting.stickyentry.error.duplicate', { stickyid => $i } ) ) ) ;
                return 1;
            }
            push @stickies,  $ditemid;
            $unique{$ditemid} = 1;
        } else {
            # As soon as we detect a problem with a sticky we break out of the subroutine.
            $class->errors( "stickyid" => ( $class->ml( 'setting.stickyentry.error.invalid2', { stickyid => $i } ) ) ) ;
            return 1;
        }
    }

    $u->sticky_entries( \@stickies );
    return 1;
}


1;
