#!/usr/bin/perl
#
# DW::User::ContentFilters::Filter
#
# This represents the actual filters that we can apply to a reading page or
# general content view.
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

package DW::User::ContentFilters::Filter;
use strict;

use Storable qw/ nfreeze thaw /;

# this just returns a base object from the input parameters.  the object itself
# is not particularly useful, as it won't have loaded the data for the filter
# itself.  things are lazy loaded only when needed.
sub new {
    my ( $class, %args ) = @_;

    my $self = bless {%args}, $class;
    return undef unless $self->_valid;
    return $self;
}

# internal validator, returns undef if we are an invalid object
sub _valid {
    my $self = $_[0];

    return 0
        unless $self->ownerid > 0 &&    # valid userid/owner
        $self->id > 0;

    return 1;
}

# method for creating a new row to the filter.  available arguments:
#
#   $filter->add_row(
#       userid => 353,     # userid to add to the filter
#
#       tags =>
#           [
#               tagid,
#               tagid,
#               tagid,
#               ...
#           ],
#
#       tag_mode => '...',             # enum( 'any_of', 'all_of', 'none_of' )
#
#       adult_content => '...',        # enum( 'any', 'nonexplicit', 'sfw' )
#
#       poster_type => '...',          # enum( 'any', 'maintainer', 'moderator' )
#   );
#
sub add_row {
    my ( $self, %args ) = @_;

    # ensure the data they gave us is sufficient
    my $t_userid = delete $args{userid};
    my $tu       = LJ::load_userid($t_userid)
        or die "add_row: userid invalid\n";

    # see if they gave poster_type
    my $poster_type = delete $args{postertype} || 'any';
    die "invalid poster_type\n"
        if $poster_type && $poster_type !~ /^(?:any|maintainer|moderator)$/;

    # adult_content
    my $adult_content = delete $args{adultcontent} || 'any';
    die "invalid adult_content\n"
        if $adult_content && $adult_content !~ /^(?:any|nonexplicit|sfw)$/;

    # tag mode
    my $tag_mode = delete $args{tagmode} || 'any_of';
    die "invalid tag_mode\n"
        if $tag_mode && $tag_mode !~ /^(?:any_of|all_of|none_of)$/;

    # tags
    # FIXME: validate that the tagids are valid for this user...?
    my $tags = delete $args{tags} || [];
    die "tags must be an arrayref\n"
        if ref $tags ne 'ARRAY';

    # if any more args, something is bunk
    die "add_row: extraneous arguments.\n"
        if %args;

    # build the row we're going to add
    my %newrow = (
        tags         => $tags,
        tagmode      => $tag_mode,
        adultcontent => $adult_content,
        postertype   => $poster_type,
    );

    # now delete the defaults
    delete $newrow{tagmode}      if $newrow{tagmode} eq 'any_of';
    delete $newrow{postertype}   if $newrow{postertype} eq 'any';
    delete $newrow{adultcontent} if $newrow{adultcontent} eq 'any';

    # now get the data for this filter
    my $data = $self->data;
    $data->{$t_userid} = \%newrow;
    $self->_save;

    return 1;
}

# method for deleting a row from the filter.  available arguments: userid
# this method deletes the complete row from the filter
#
# $filter->delete_row( userid )   # userid to remove from the filter
#
#
sub delete_row {
    my ( $self, $userid ) = @_;

    # check if user is already in this content filter
    return 0 unless $self->contains_userid($userid);

    # delete row from filter
    delete( $self->data->{$userid} );
    $self->_save;

    return 1;
}

# make sure that our data is loaded up
sub data {
    my $self = $_[0];

    # object first
    return $self->{_data}
        if exists $self->{_data};

    # try memcache second
    my $u        = $self->owner;
    my $mem_data = $u->memc_get( 'cfd:' . $self->id );
    return $self->{_data} = $mem_data
        if $mem_data;

    # fall back to the database
    my $data = $u->selectrow_array(
        q{SELECT data FROM content_filter_data WHERE userid = ? AND filterid = ?},
        undef, $u->id, $self->id );
    die $u->errstr if $u->err;

    # now decompose it
    $data = thaw($data);

    # we default to using an empty hashref, just in case this filter doesn't
    # have a data row already
    $data ||= {};

    # now save it in memcache and then the object
    $u->memc_set( 'cfd:' . $self->id, $data, 3600 );
    return $self->{_data} = $data;
}

# if this filter contains someone.  this is a very basic level check you can use
# to quickly and easily filter out accounts that don't exist in a filter at all
# before having to do some heavy lifting to load tags, statuses, etc.
sub contains_userid {
    my ( $self, $userid ) = @_;

    return 1 if exists $self->data->{$userid};
    return 0;
}

# check whether this filter qualifies as a default filter. Case-insensitive.
# e.g., Default, Default View, etc
sub is_default {
    my $name = lc( $_[0]->{name} );
    return 1 if $name eq "default" || $name eq "default view";
    return 0;
}

# called with an item hashref or LJ::Entry object, determines whether or not this
# filter allows this entry to be shown
sub show_entry {
    my ( $self, $item ) = @_;

    # these helpers are mostly for debugging help so we can make sure that the
    # various logic paths work ok
    my ( $ok, $fail, $u );
    if ($LJ::IS_DEV_SERVER) {
        $ok = sub {
            warn sprintf( "[$$] %s(%d): OK journalid=%d, jitemid=%d, ownerid=%d: %s\n",
                $u->user, $u->id, $item->{journalid}, $item->{jitemid}, $item->{ownerid}, shift() );
            return 1;
        };
        $fail = sub {
            warn sprintf( "[$$] %s(%d): FAIL journalid=%d, jitemid=%d, ownerid=%d: %s\n",
                $u->user, $u->id, $item->{journalid}, $item->{jitemid}, $item->{ownerid}, shift() );
            return 0;
        };

    }
    else {
        $ok   = sub { return 1; };
        $fail = sub { return 0; };
    }

    # short circuit: if our owner is not a paid account, then we never run any of
    # the below checks.  (this saves us in the situation where a paid users has
    # custom filters and expires.  they go back to being basic filters, but the
    # user doesn't LOSE the filters.)
    $u = $self->owner;
    return $ok->('free_user') unless $u->is_paid;

    # okay, we need the entry object.  a little note here, this is fairly efficient
    # because LJ::get_log2_recent_log actually creates all of the singletons for
    # the entries it touches.  so when we call some sort of 'load data on something'
    # on one of the entries, then it loads on all of them.  (FIXME: verify this
    # by watching memcache/db queries.)
    my $entry = LJ::Entry->new_from_item_hash($item);
    my ( $journalu, $posteru ) = ( $entry->journal, $entry->poster );

    # now we have to get the parameters to this particular filter row
    my $opts = $self->data->{ $journalu->id } || {};

    # step 1) community poster type
    if ( $journalu->is_community && $opts->{postertype} && $opts->{postertype} ne 'any' ) {
        my $is_admin     = $posteru->can_manage_other($journalu);
        my $is_moderator = $posteru->can_moderate($journalu);

        return $fail->('not_maintainer')
            if $opts->{postertype} eq 'maintainer' && !$is_admin;

        return $fail->('not_moderator_or_maintainer')
            if $opts->{postertype} eq 'moderator' && !( $is_admin || $is_moderator );
    }

    # step 2) adult content flag
    if ( $opts->{adultcontent} && $opts->{adultcontent} ne 'any' ) {
        my $aclevel = $entry->adult_content_calculated;

        if ($aclevel) {
            return $fail->('explicit_content')
                if $opts->{adultcontent} eq 'nonexplicit' && $aclevel eq 'explicit';

            return $fail->('not_safe_for_work')
                if $opts->{adultcontent} eq 'sfw' && $aclevel ne 'none';
        }
    }

    # step 3) tags, but only if they actually selected some
    my @tagids = @{ $opts->{tags} || [] };
    if ( scalar @tagids > 0 ) {

        # set a default/assumed value
        $opts->{tagmode} ||= 'any_of';

        # we change the initial state to make the logic below easier
        my $include = {
            none_of => 1,
            any_of  => 0,
            all_of  => 0,
        }->{ $opts->{tagmode} };
        return $fail->('bad_tagmode') unless defined $include;

        # now iterate over each tag and alter $include
        my $tags = $entry->tag_map || {};
        foreach my $id (@tagids) {
            foreach my $id2 ( keys %$tags ) {

                # any_of: unconditionally turn on this entry if we match one tag
                $include = 1
                    if $opts->{tagmode} eq 'any_of' && $id2 == $id;

                # none_of: unconditionally turn off this entry if we match one tag
                $include = 0
                    if $opts->{tagmode} eq 'none_of' && $id2 == $id;

                # all_of: increment $include for each matched tag
                $include++
                    if $opts->{tagmode} eq 'all_of' && $id2 == $id;
            }
        }

        # failed all_of if include doesn't match size of tags
        return $fail->('failed_all_of_tag_select')
            if $opts->{tagmode} eq 'all_of' && ( $include != scalar @tagids );

        # otherwise, treat it as a boolean
        return $fail->('failed_tag_select') unless $include;
    }

    # if we get here, then this entry looks good, include it
    return $ok->('success');
}

# meant to be called internally only by the filter object and not by cowboys
# that think they're smarter than us.  that's why it has a prefixed underscore.
# sometimes I do wish for a real language with real OO concepts like private
# methods and such.
sub _save {
    my $self = $_[0];

    my $u    = $self->owner;
    my $data = $self->data;    # do this in case we called _save before load

    $u->do( q{REPLACE INTO content_filter_data (userid, filterid, data) VALUES (?, ?, ?)},
        undef, $u->id, $self->id, nfreeze($data) );
    die $u->errstr if $u->err;

    $u->memc_set( 'cfd:' . $self->id, $data, 3600 );

    return 1;
}

# some simple accessors... we don't really support using these as setters
# FIXME: we should sanitize on the object creation, not in these getters,
# ...just hacking this together right now
sub id      { $_[0]->{id} + 0 }
sub ownerid { $_[0]->{ownerid} + 0 }

# getter/setters
sub name      { $_[0]->_getset( name      => $_[1] ); }
sub public    { $_[0]->_getset( public    => $_[1] ); }
sub sortorder { $_[0]->_getset( sortorder => $_[1] ); }

# other helpers
sub owner { LJ::load_userid( $_[0]->{ownerid} + 0 ) }

# generic helper thingy
sub _getset {
    my ( $self, $which, $val ) = @_;

    # if no argument, just bail
    return $self->{$which} unless defined $val;

    # FIXME: we should probably have generic vetters somewhere... or something, I don't know,
    # I just know that I don't really like doing this here
    if ( $which eq 'name' ) {
        $val = LJ::text_trim( $val, 255, 100 ) || '';
    }
    elsif ( $which eq 'public' ) {
        $val = $val ? 1 : 0;
    }
    elsif ( $which eq 'sortorder' ) {
        $val += 0;
    }
    else {
        # this should never happen if you updated this function right...
        die 'Programmer needs food badly.  Programmer is about to die!';
    }

    # make sure to update this object
    $self->{$which} = $val;

    # stupid hack for column name mapping
    $which = 'is_public'  if $which eq 'public';
    $which = 'filtername' if $which eq 'name';

    # update the database
    my $u = $self->owner;
    $u->do( "UPDATE content_filters SET $which = ? WHERE userid = ? AND filterid = ?",
        undef, $val, $u->id, $self->id );
    die $u->errstr if $u->err;

    # clear memcache and the object
    delete $u->{_content_filters};
    $u->memc_delete('content_filters');

    return $val;
}

1;
