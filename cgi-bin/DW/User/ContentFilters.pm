#!/usr/bin/perl
#
# DW::User::ContentFilters
#
# This module allows working with watch filters, the constructs that enable
# a user to filter content on their reading page.
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

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

package DW::User::ContentFilters;
use strict;

use DW::User::ContentFilters::Filter;

# loads a list of a user's filters, returns them in a list sorted by their
# given sort order.  note that you can specify an argument to return only
# public filters or not.
#
#    my @filters = $u->content_filters( public => 1 );
#
# or don't include the argument to return all filters (default).  returns
# objects that are some subclass of DW::User::ContentFilters::Abstract.
sub content_filters {
    my $u = LJ::want_user( shift() )
        or die 'Must call on a user object';
    my %args = (@_);

    # now return what they want, remember these are objects now, so sort them
    # by the sortorder
    my $sort_filters = sub {
        my @list =
            sort { $a->sortorder <=> $b->sortorder }
            grep { $args{public} ? $_->public : 1 }

            # return content filter regardless of case
            grep { $args{name} ? lc( $_->name ) eq lc( $args{name} ) : 1 }
            grep { $args{id} ? $_->id == $args{id} : 1 } @_;
        return wantarray ? @list : $list[0];
    };

    # we do this here because we don't want to try to memcache the actual
    # objects which might contain random data, so instead we're just caching
    # what the db tells us.  so we have to reconstitute the objects every
    # time, which is what this does.
    my $build_filters = sub {

        # now promote everything to an object
        return sort { $a->sortorder <=> $b->sortorder || $a->name cmp $b->name }
            map {
            DW::User::ContentFilters::Filter->new(
                ownerid   => $u->id,
                id        => $_->[0],
                name      => $_->[1],
                public    => $_->[2],
                sortorder => $_->[3],
            )
            } @_;
    };

    # if on the user object, they're already built
    return $sort_filters->( @{ $u->{_content_filters} } )
        if $u->{_content_filters};

    # if in memcache, build and return
    my $filters = $u->memc_get('content_filters');
    return $sort_filters->( $build_filters->(@$filters) )
        if $filters;

    # try the database now
    $filters = $u->selectall_arrayref(
        q{SELECT filterid, filtername, is_public, sortorder
          FROM content_filters
          WHERE userid = ?},
        undef, $u->id
    );

    # and make sure it goes into memcache for an hour
    $u->memc_set( 'content_filters', $filters, 3600 );

    # store on the user object in case they call us later so we don't have to
    # do more memcache roundtrips
    $u->{_content_filters} = [ $build_filters->(@$filters) ];
    return $sort_filters->( @{ $u->{_content_filters} } );
}
*LJ::User::content_filters = \&content_filters;

# makes a new watch filter for the user.  pretty easy to use, everything is actually
# optional...
sub create_content_filter {
    my ( $u, %args ) = @_;

    # FIXME: this is probably the point we should implement limits on how many
    # filters you can create...

# check if a filter with this name already exists, if so return its id, so the user can edit or remove it
    my $name = LJ::text_trim( delete $args{name}, 255, 100 ) || '';
    return $u->content_filters( name => $name )->id
        if $u->content_filters( name => $name );

    # we need a filterid, or #-1 FAILURE MODE IMMINENT
    my $fid = LJ::alloc_user_counter( $u, 'F' )
        or die 'unable to allocate counter';

    # database insert
    $u->do(
        q{INSERT INTO content_filters (userid, filterid, filtername, is_public, sortorder)
          VALUES (?, ?, ?, ?, ?)},
        undef, $u->id, $fid, $name,
        ( $args{public} ? '1' : '0' ), ( $args{sortorder} + 0 ),
    );
    die $u->errstr if $u->err;

    # everything is OK, so clear memcache, user object
    delete $u->{_content_filters};
    $u->memc_delete('content_filters');
    return $fid;
}
*LJ::User::create_content_filter = \&create_content_filter;

# removes a content filter.  arguments are the same as what you'd pass to content_filters
# to get a filter, and if it returns just one filter, we'll nuke it.
sub delete_content_filter {
    my ( $u, %args ) = @_;

    # import to use the array return so that we get all of the filters that match
    # the query and can make sure it only returns one.
    my @filters = $u->content_filters(%args);
    die "tried to delete more than one content filter in a single call to delete_content_filter\n"
        if scalar(@filters) > 1;
    return undef unless @filters;

    # delete
    $u->do( 'DELETE FROM content_filters WHERE userid = ? AND filterid = ?',
        undef, $u->id, $filters[0]->id );
    $u->do( 'DELETE FROM content_filter_data WHERE userid = ? AND filterid = ?',
        undef, $u->id, $filters[0]->id );
    delete $u->{_content_filters};
    $u->memc_delete('content_filters');

    # return the id of the deleted filter
    return $filters[0]->id;
}
*LJ::User::delete_content_filter = \&delete_content_filter;

sub add_to_default_filters {
    my ( $u, $targetu ) = @_;

    # assume things are okay at first
    # one mis-add means failure
    # (but we're still okay if no adds were done)
    my $ok = 1;
    foreach my $filter ( $u->content_filters ) {
        next unless $filter->is_default();
        next if $filter->contains_userid( $targetu->userid );

        $ok = $filter->add_row( userid => $targetu->userid ) && $ok;
    }

    return $ok;
}
*LJ::User::add_to_default_filters = \&add_to_default_filters;

1;
