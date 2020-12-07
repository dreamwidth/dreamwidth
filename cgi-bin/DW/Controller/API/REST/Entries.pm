#!/usr/bin/perl
#
# DW::Controller::API::REST::Entries
#
# API controls for entries
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::REST::Entries;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;

################################################
# /journals/{journal}/entries
#
# Get recent entries or post a new entry.
################################################

my $entries_all = DW::Controller::API::REST->path('entries_all.yaml', 1, { get => \&rest_get, post => \&new_entry});

################################################
# /journals/{journal}/entries/{entry_id}
#
# Get single entry or update existing entry.
################################################

my $entries = DW::Controller::API::REST->path('entries.yaml', 1, { get => \&rest_get, patch => \&edit_entry});

###################################################
#
# Handles get requests for both routes
#
###################################################


sub rest_get {
    my ( $self, $args) = @_;
    my $journal = LJ::load_user( $args->{path}{username} );
    my $remote = $args->{user};
    my $ditemid = $args->{path}{entry_id};
    my $opts = $args->{query};

    return $self->rest_error( '404' ) unless $journal;

    if (defined $ditemid && $ditemid ne "") {
        my $item = LJ::Entry->new($journal, ditemid => $ditemid);

        # $item will always exist, even if it's not actually a real entry id
        # however, entries must have content, so no content means it's a bad object.
        return $self->rest_error('404') unless $item->event_html;

        return $self->rest_error('403') unless $item->visible_to($remote);

        my $entry = $item->as_json($remote);
        return $self->rest_ok( $entry );

    } else {
    
        my $skip = $opts->{offset} ? $opts->{offset} : 0;
       
        my $itemshow = $opts->{count} ? $opts->{count} : 25;
        my $poster;
        my @items = ();

        # a non-existant poster can never have posted entries, so return an empty list.
        # necessary because an undef posterid removes that filter, returning all an unfiltered entry list
        # which is not the expected behavior.
        if ($opts->{poster} && $journal->is_community ) {
            $poster = LJ::load_user( $opts->{poster} );
            return $self->rest_ok( \@items ) unless $poster;
        }

        my @tags = ();
        if (defined($opts->{tag})) {
            my $usertags = LJ::Tags::get_usertags( $journal, { remote => $remote } );
            foreach my $tag (keys %{$usertags}) {
                if ($usertags->{$tag}{name} eq $opts->{tag}) {
                    push @tags, $tag;
                }
            }
            return $self->rest_ok( \@items ) unless @tags > 0; # a non-existant tag can't have entries, either.
        }

        my @itemids;
        my $err;
        @items = $journal->recent_items(
            clusterid     => $journal->{clusterid},
            clustersource => 'slave',
            remote        => $remote,
            itemshow      => $itemshow,
            skip          => $skip,
            tagids        => \@tags,
            tagmode       => $opts->{tagmode},
            security      => $opts->{security},
            itemids       => \@itemids,
            dateformat    => 'S2',
            order         => $journal->is_community ? 'logtime' : '',
            err           => \$err,
            posterid      => $journal->is_community && $poster ? $poster->id : undef,
            );

        my @entries;
        foreach my $it ( @items ) {
            my $item = LJ::Entry->new( $journal, jitemid => $it->{itemid});
            my $entry = $item->as_json($remote);
            push @entries, $entry;
        }
        return $self->rest_ok( \@entries );
    }
}



###################################################
#
# Handles post of new entries, given a journal name
#
# FIXME: Doesn't handle crossposts yet.


sub new_entry {
    my ( $self, $args) = @_;

    my $usejournal = LJ::load_user( $args->{path}{username} );
    my $remote = $args->{user};
   
    my $post = $args->{body};

    return $self->rest_error( '404' ) unless $usejournal;

        # these kinds of errors prevent us from initializing the form at all
    # so abort and return it without the form
    if ( $remote ) {
        return $self->rest_error('402')
                if $remote->is_identity;

        return $self->rest_error('400')
                unless $remote->can_post;

        return $self->rest_error('403')
                if $remote->can_post_disabled;
    }


    # figure out times
    my $datetime;
    my $trust_datetime_value = 0;

    if ( $post->{entrytime_date} && $post->{entrytime_time} ) {
        $datetime = "$post->{entrytime_date} $post->{entrytime_time}";
        $trust_datetime_value = 1;
    } else {
        my $now = DateTime->now;

        # if user has timezone, use it!
        if ( $remote && $remote->prop( "timezone" ) ) {
            my $tz = $remote->prop( "timezone" );
            $tz = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
            $now = eval { DateTime->from_epoch( epoch => time(), time_zone => $tz ); }
               if $tz;
        }

        $datetime = $now->strftime( "%F %R" ),
        $trust_datetime_value = 0;  # may want to override with client-side JS
    }

        return $self->rest_error('400')
            unless $post->{text} ne '';

        return $self->rest_error('403')
            unless $remote->can_post_to($usejournal);

        _map_to_standard($post);

        my $flags = {};
        $flags->{noauth} = 1;
        $flags->{u} = $remote;
        $flags->{xpost} = $post->{crosspost}

        my %auth;
        $auth{poster} = $remote;
        $auth{journal} = $usejournal ? $usejournal : $remote;


        my $form_req = {};
        DW::Controller::Entry::_form_to_backend( $form_req, $post);


        # if we didn't have any errors with decoding the form, proceed to post
        my $post_res = _do_post( $form_req, $flags, \%auth);

        return $self->rest_ok( $post_res ) if $post_res->{success} == 1;

        # oops errors when posting: show error, fall through to show form
        return $self->rest_error( '500', $post_res->{errors} ) if $post_res->{errors};

}

sub _map_to_standard {
    my ($post) = @_;

    # we use slightly different names for a few fields compared to the entry page
    # so map those to the 'expected' names.
    $post->{flags_adminpost} = $post->{admin_post} || 0;
    $post->{taglist} = $post->{tags};
    $post->{flags_adminpost} = $post->{admin_post};

    return;
}


sub _do_post {
    my ( $form_req, $flags, $auth, %opts ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{poster} ? $auth->{poster}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        tz          => 'guess',
        xpost       => $flags->{xpost} == 0 ? '0' : $flags->{xpost},
        %$form_req
    };


    my $err = 0;
    my $res = LJ::Protocol::do_request( "postevent", $req, \$err, $flags );

    return { { success=> 0, errors => LJ::Protocol::error_message( $err )} } unless $res;


    # post succeeded, time to do some housecleaning

    my $render_ret;


    # special-case moderated: no itemid, but have a message
    if ( ! defined $res->{itemid} && $res->{message} ) {
        $render_ret = { success => 1,
                        message => $res->{message} };
    } else {
        my $ditemid = $res->{itemid}*256 + $res->{anum};
        $render_ret = { success => 1,
                        url => $res->{url},
                        entry_id => $ditemid};

        my $u       = $auth->{poster};
        my $journal = $auth->{journal};
        my $edititemlink = "$LJ::SITEROOT/entry/${journal->user}/$ditemid/edit";

    }

    return ($render_ret);
}


###################################################
#
# Handles post of new entries, given a journal name
#

sub edit_entry {

    my ( $self, $args) = @_;

    my $usejournal = LJ::load_user( $args->{path}{username} );
    my $ditemid = $args->{path}{entry_id};
    my $remote = $args->{user};
   
    my $post = $args->{body};

    return $self->rest_error('401') unless $remote;
    return $self->rest_error('404') unless $usejournal;


    # we can always trust this value:
    # it either came straight from the entry
    # or it's from the user's POST
    my $trust_datetime_value = 1;

    my $entry_obj = LJ::Entry->new( $usejournal, ditemid => $ditemid );

    # are you authorized to view this entry
    # and does the entry we got match the provided ditemid exactly?
    my $anum = $ditemid % 256;
    my $itemid = $ditemid >> 8;
    return $self->rest_error('404')
        unless $entry_obj->editable_by( $remote )
            && $anum == $entry_obj->anum && $itemid == $entry_obj->jitemid;


    return $self->rest_error('400')
        unless $post->{text} ne '';

    _map_to_standard($post);

    # so at this point, we know that we are authorized to edit this entry
    # but we need to handle things differently if we're an admin
    # FIXME: handle communities
    # return $self->rest_error('POST', 401, "IS AN ADMIN") unless $entry_obj->poster->equals( $remote );

    my $form_req = DW::Controller::Entry::_backend_to_form($entry_obj);

    # keep the form formatter sub from removing subject/body/security if
    # the edit doesn't specify them.
    $post->{subject} = $post->{subject} || $form_req->{subject};
    $post->{event} = $post->{text} || $form_req->{event};
    $post->{security} = $post->{security} || $form_req->{security} || "";
    
    _form_to_backend( $form_req, $post);

        my $edit_res = _do_edit(
                $ditemid,
                $form_req,
                { remote => $remote, journal => $usejournal },
                {xpost => $post->{crosspost}}
                );
        return $self->rest_nocontent() if $edit_res->{success} == 1;

        # oops errors when posting: show error, fall through to show form
        return $self->rest_error( 500, $edit_res->{errors} ) if $edit_res->{errors};
    }



sub _do_edit {
    my ( $ditemid, $form_req, $auth, $opts ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{remote} ? $auth->{remote}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        xpost       => $flags->{xpost} == 0 ? '0' : $flags->{xpost},
        itemid      => $ditemid >> 8,
        %$form_req
    };

    my $err = 0;
    my $res = LJ::Protocol::do_request( "editevent", $req, \$err, {
            noauth => 1,
            u =>  $auth->{remote},
        } );

    return { { success => 0, errors => LJ::Protocol::error_message($err) } } unless $res;

    my $remote = $auth->{remote};
    my $journal = $auth->{journal};
    my $edit_url      = "$LJ::SITEROOT/entry/${journal->user}/$ditemid/edit";

    my $render_ret = {success => 1,
                        url => $res->{url},
                        entry_id => $ditemid};

    return ( $render_ret );
}


1;
