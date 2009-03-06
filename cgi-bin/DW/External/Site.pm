#!/usr/bin/perl
#
# DW::External::Site
#
# This is a base class used by other classes to define what kind of things an
# external site can do.  This class is actually responsible for instantiating
# the right kind of class.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site;

use strict;
use Carp qw/ croak /;
use DW::External::Site::InsaneJournal;
use DW::External::Site::LiveJournal;
use DW::External::Site::Unknown;


sub new {
    my ( $class, %opts ) = @_;

    my $site = delete $opts{site}
        or croak 'site argument required';
    croak 'invalid extra parameters'
        if %opts;

    # cleanup
    $site =~ s/\r?\n//s;            # multiple lines is pain
    $site =~ s!^(?:.+)://(.*)!$1!;  # remove proto:// leading
    $site =~ s!^([^/]+)/.*$!$1!;    # remove /foo/bar.html trailing

    # validate each part of the domain based on RFC 1035
    my @parts = grep { /^[a-z][a-z0-9\-]*?[a-z0-9]$/ }
                map { lc $_ }
                split( /\./, $site );

    # FIXME: rewrite this in terms of LJ::ModuleLoader or some better
    # functionality so that daughter sites can add new external sites
    # without having to modify this file directly.
    
    # now we see who's going to accept this... when editing, try to put
    # common ones towards the top as this is likely to be run a bunch
    if ( my $obj = DW::External::Site::LiveJournal->accepts( \@parts ) ) {
        return $obj;

    } elsif ( my $obj = DW::External::Site::InsaneJournal->accepts( \@parts ) ) {
        return $obj;

    } elsif ( my $obj = DW::External::Site::Unknown->accepts( \@parts ) ) {
        # the Unknown class tries to fake it by emulating the general defaults
        # we expect most sites to use.  if it doesn't work, someone should submit a
        # patch to help us figure out what site they're using.
        #
        # do log the site though, so we can look at the logs later and maybe do it
        # ourselves.
        warn "Unknown site " . join( '.', @parts ) . " in DW::External::Site.\n";
        return $obj;

    }

    # can't handle this in any way
    return undef;
}


# these methods are expected to be implemented by the subclasses
sub accepts         { croak 'unimplemented call to accepts';         }
sub journal_url     { croak 'unimplemented call to journal_url';     }
sub profile_url     { croak 'unimplemented call to profile_url';     }
sub badge_image_url { croak 'unimplemented call to badge_image_url'; }


1;
