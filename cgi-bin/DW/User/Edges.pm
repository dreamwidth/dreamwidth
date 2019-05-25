#!/usr/bin/perl
#
# DW::User::Edges
#
# This module defines relationships between accounts.  It allows for finding
# edges, defining edges, removing edges, and other tasks related to the edges
# that can exist between accounts.  Methods are added to the LJ::User/DW::User
# classes as appropriate.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

package DW::User::Edges;
use strict;

# FYI - including edges is done at the end of this file.  scroll down to the
# comment denoted 'XXX'.

# overall list of edges that are valid, if it's not in this list (and not one
# of the special edges like 'all') then we don't know how to deal with it
our %VALID_EDGES;

# defines a new edge in the valid list above.  this function is assumed to be
# called at startup, so we are safe using 'die' for any error conditions, as
# we WANT to prevent site startup.
sub define_edge {
    my ( $name, $opts ) = @_;

    die "Attempt to define edge with bad name: $name.\n"
        unless $name =~ /^[\w\d-]+$/;
    die "Attempt to re-define edge $name.\n"
        if exists $VALID_EDGES{$name} && !$LJ::IS_DEV_SERVER;
    die "Defined edge $name contains no type.\n"
        unless $opts->{type};
    die "Defined edge $name contains invalid type: $opts->{type}.\n"
        unless $opts->{type} =~ /^(?:int|bool|hashref)$/;
    die "Defined edge $name contains invalid db_edge: $opts->{db_edge}.\n"
        if exists $opts->{db_edge} && $opts->{db_edge} !~ /^\w$/;

    if ( my $hr = $opts->{options} ) {
        die "Defined edge $name options not a hashref.\n"
            unless ref $hr && ref $hr eq 'HASH';
        die "Edge $name must have type 'hashref'.\n"
            unless $opts->{type} && $opts->{type} eq 'hashref';

        foreach my $opt ( keys %$hr ) {
            die "Defined edge $name has invalid option name: $opt.\n"
                unless $opt =~ /^[\w\d-]+$/;
            die "Defined edge $name option $opt is not a hashref.\n"
                unless $hr->{$opt} && ref $hr->{$opt} eq 'HASH';
            die "Defined edge $name option $opt has invalid type: $hr->{$opt}->{type}.\n"
                unless $hr->{$opt}->{type} && $hr->{$opt}->{type} =~ /^(?:int|bool)$/;

            # by default, not required, fill that in if they didn't specify it
            $hr->{$opt}->{required} ||= 0;
            die "Defined edge $name option $opt value 'required' must be 0 or 1.\n"
                unless $hr->{$opt}->{required} =~ /^(?:0|1)$/;
        }
    }

    foreach (qw/ add_sub del_sub /) {
        die "Defined edge $name does not define $_.\n"
            unless $opts->{$_};
        die "Defined edge $name not given a code reference for $_.\n"
            if ref $opts->{$_} ne 'CODE';
    }

    $VALID_EDGES{$name} = $opts;
}

# takes as input a hashref of items to be validated and makes sure that the
# inputs are valid according to what we know about the defined edges
sub validate_edges {
    my $edges = $_[0];

    # error stuff
    my $err = sub {
        warn "validate_edges: " . shift() . "\n";
        return 0;
    };
    return $err->('Invalid parameter')
        unless ref $edges eq 'ARRAY' || ref $edges eq 'HASH';

    # iterate over each edge in the hash and validate
    my @iter = ref $edges eq 'HASH' ? keys %$edges : @$edges;
    foreach my $edge (@iter) {

        # if it's not in valid edges, it's bunk
        my $er = $VALID_EDGES{$edge};
        return $err->("Edge '$edge' unknown.") unless $er;

        # at this point, if they gave us an array of items to check (as opposed to a hash) then we
        # assume it's good.  the array behavior is used in cases where they are deleting edges and
        # only know the name of the edge.
        next if ref $edges eq 'ARRAY';

        # type assurance
        return $err->("Edge $edge of type bool with invalid value [$edges->{$edge}].")
            if $er->{type} eq 'bool' && $edges->{$edge} !~ /^(?:0|1)$/;
        return $err->("Edge $edge of type int with invalid value [$edges->{$edge}].")
            if $er->{type} eq 'int' && $edges->{$edge} !~ /^\d+$/;

        # if it's a hashref/subopt/complex type, check the options
        if ( $er->{type} eq 'hashref' ) {
            return $err->("Edge $edge of type hashref with invalid value.")
                unless ref $edges->{$edge} eq 'HASH';

## FIXME: we don't assert all of the 'required' options are passed yet

            my $opts = $er->{options};
            foreach my $opt ( keys %$opts ) {

                # set default if we've been given one
                $edges->{$edge}->{$opt} = $opts->{$opt}->{default}
                    if !exists $edges->{$edge}->{$opt}
                    && exists $opts->{$opt}->{default};

                # skip the edge if they didn't provide and it's not required
                next
                    unless exists $edges->{$edge}->{$opt}
                    || $opts->{$opt}->{required};

                # now error check
                return $err->(
"Edge $edge option $opt of type bool with invalid value [$edges->{$edge}->{$opt}]."
                ) if $opts->{$opt}->{type} eq 'bool' && $edges->{$edge}->{$opt} !~ /^(?:0|1)$/;
                return $err->(
"Edge $edge option $opt of type int with invalid value [$edges->{$edge}->{$opt}]."
                ) if $opts->{$opt}->{type} eq 'int' && $edges->{$edge}->{$opt} !~ /^\d+$/;
            }
        }
    }

    # should be valid at this point
    return 1;
}

# XXX: add new edge modules that are global here
use DW::User::Edges::WatchTrust;
use DW::User::Edges::CommMembership;

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

# for now, we push our methods into the DW::User namespace
package DW::User;
use strict;

# adds edges between one user and another
sub add_edge {
    my ( $from_u, $to_u, %edges ) = @_;

    # need u objects
    $from_u = LJ::want_user($from_u);
    $to_u   = LJ::want_user($to_u);

    # error check inputs
    return 0 unless $from_u && $to_u;
    return 0 unless DW::User::Edges::validate_edges( \%edges );

    # now we try to add these edges.  note that we do this in this way so that
    # multiple edges can be consumed by one add sub.
    my @to_add = keys %edges;
    my $ok     = 1;
    while ( my $key = shift @to_add ) {

        # some modules will define multiple edges, and so one call to add_sub might
        # get rid of more than one edge, so we have to do this check to ensure that
        # the edge still exists
        next unless $edges{$key};

        # simply calls an add_sub to handle the edge.  we expect them to remove the
        # edge from the hashref if they process it.
        my $success = $DW::User::Edges::VALID_EDGES{$key}->{add_sub}->( $from_u, $to_u, \%edges );
        $ok &&= $success;    # will zero out if any edges fail
    }

    # all good
    return $ok;
}

# removes an edge between two users
sub remove_edge {
    my ( $from_u, $to_u, %edges ) = @_;

    # need u objects
    $from_u = LJ::want_user($from_u);
    $to_u   = LJ::want_user($to_u);

    # error check inputs
    return 0 unless $from_u && $to_u;
    return 0 unless DW::User::Edges::validate_edges( \%edges );

    # now we try to remove these edges.  note that we do this in this way so that
    # multiple edges can be consumed by one remove sub.
    my @to_del = keys %edges;
    my $ok     = 1;
    while ( my $key = shift @to_del ) {

        # some modules will define multiple edges, and so one call to add_sub might
        # get rid of more than one edge, so we have to do this check to ensure that
        # the edge still exists
        next unless $edges{$key};

        # simply calls an add_sub to handle the edge.  we expect them to remove the
        # edge from the hashref if they process it.
        my $success = $DW::User::Edges::VALID_EDGES{$key}->{del_sub}->( $from_u, $to_u, \%edges );
        $ok &&= $success;    # will zero out if any edges fail
    }

    # all good
    return $ok;
}

# and now we link these into the LJ::User namespace for backwards compatibility
*LJ::User::add_edge    = \&add_edge;
*LJ::User::remove_edge = \&remove_edge;

1;
