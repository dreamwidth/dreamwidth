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
use warnings;

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

    my @stickies = $u->sticky_entry;
    my $username = $u->user;

    foreach my $i ( 1... $u->count_max_stickies ) {
        my $url = "";
        if ( $stickies[$i - 1] ) {
            $url = "http://$username.dreamwidth.org/$stickies[$i - 1].html";
        } else {
            $url = "http://$username.dreamwidth.org/(Entry Number).html" if ( $i == 1 || $stickies [$i - 2] );
        }
        my $textentry = $errs ? $class->get_arg( $args, "stickyid${i}" ) : $url;

        $ret .= "<label for='${key}stickyid${i}'>" . $class->ml( 'setting.stickyentryi.label' ) . " $i </label>";
        $ret .= LJ::html_text({
            name  => "${key}stickyid${i}",
            id    => "${key}stickyid${i}",
            class => "text",
            value => "$textentry",
            size  => 50,
            maxlength => 100,
        });
        $ret .= "<br />";

    }

    # returns an error if any of the stickies are incorrectly formatted.
    my $errdiv = $class->errdiv( $errs, "stickyid" );
    $ret .= "<br />$errdiv" if $errdiv;

    $ret .= "<br />" . $class->ml( 'setting.stickyentry.details.label' );

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $max_sticky_count = $u->count_max_stickies;
    my @stickies;
    # Create a hash that we will use to check for duplicate entries.
    my %unique = ();
    my $username = $u->user;
    my $defaulturl = "http://$username.dreamwidth.org/(Entry Number).html";
    for ( my $i=1; $i<=$max_sticky_count; $i++ ) {
        my $stickyi = $class->get_arg( $args, "stickyid${i}" ) || '';
        # Unless this is a blank form entry...
        unless ( $stickyi eq '' || $stickyi eq $defaulturl ) {
            $stickyi = LJ::text_trim( $stickyi, 0, 100 );
            my $ditemid = $u->is_valid_entry( $stickyi );
            # is_valid_entry will return the correct itemid if a URL has been given.  It will be
            # undefined if the text box entry has a problem.
            if ( $ditemid ) {
                if ( exists $unique{ $ditemid } ) {
                    $class->errors( "stickyid" => ( $class->ml( 'setting.stickyentry.error.duplicate' ) . $i ) ) ;
                    return 1;
                }
                push( @stickies,  $ditemid );
                $unique{ $ditemid } = 1;
            } else {
                # As soon as we detect a problem with a sticky we break out of the subroutine.
                $class->errors( "stickyid" => ( $class->ml( 'setting.stickyentry.error.invalid2' ) . $i ) ) ;
                return 1;
            }
        }
    }

    # We pass in a reference to the array - which will be a reference to an empty array if the user has
    # blanked all their stickies.  In User.pm sticky_entry is called without an argument just to
    # get the list of current stickies, in that case the parameter will be undefined.
    $u->sticky_entry ( \@stickies );
    return 1;
}


1;
