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
use Data::Dumper;

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

my $entries = DW::Controller::API::REST->path('entries.yaml', 1, { get => \&rest_get, post => \&edit_entry});

###################################################
#
# Handles post of new entries, given a journal name
#
# FIXME: Doesn't handle crossposts yet.

my %form_to_props = (
    # currents / metadata
    current_mood        => "current_moodid",
    current_mood_other  => "current_mood",
    current_music       => "current_music",
    current_location    => "current_location",
);


my @modules = qw(
    tags displaydate slug
    currents comments age_restriction
    icons crosspost sticky
);


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


        my $flags = {};
        $flags->{noauth} = 1;
        $flags->{u} = $remote;

        my %auth;
        $auth{poster} = $remote;
        $auth{journal} = $usejournal ? $usejournal : $remote;


        my $form_req = {};
        _form_to_backend( $form_req, $post);


        # if we didn't have any errors with decoding the form, proceed to post
        my $post_res = _do_post( $form_req, $flags, \%auth);

        return $self->rest_ok( $post_res ) if $post_res->{success} == 1;

        # oops errors when posting: show error, fall through to show form
        return $self->rest_error( '500', $post_res->{errors} ) if $post_res->{errors};



}


# decodes the posted form into a hash suitable for use with the protocol
# $post is expected to be an instance of Hash::MultiValue
sub _form_to_backend {
    my ( $req, $post, %opts ) = @_;

    # handle event subject and body
    $req->{subject} = $post->{subject} || $req->{subject};
    $req->{event} = $post->{text} || $req->{event} || "";


    # initialize props hash
    $req->{props} ||= {};
    my $props = $req->{props};

    while ( my ( $formname, $propname ) = each %form_to_props ) {
        $props->{$propname} = $post->{$formname}
            if defined $post->{$formname};
    }
    $props->{taglist} = $post->{tags} if defined $post->{tags};
    $props->{picture_keyword} = $post->{icon} if defined $post->{icon};
    $props->{opt_backdated} = $post->{entrytime_outoforder} ? 1 : 0;
    # FIXME

    # old implementation of comments
    # FIXME: remove this before taking the page out of beta
    $props->{opt_screening}  = $post->{opt_screening};
    $props->{opt_nocomments} = $post->{comment_settings} && $post->{comment_settings} eq "nocomments" ? 1 : 0;
    $props->{opt_noemail}    = $post->{comment_settings} && $post->{comment_settings} eq "noemail" ? 1 : 0;


    # see if an "other" mood they typed in has an equivalent moodid
    if ( $props->{current_mood} ) {
        if ( my $moodid = DW::Mood->mood_id( $props->{current_mood} ) ) {
            $props->{current_moodid} = $moodid;
            delete $props->{current_mood};
        }
    }

    # nuke taglists that are just blank
    $props->{taglist} = "" unless $props->{taglist} && $props->{taglist} =~ /\S/;

    if ( LJ::is_enabled( 'adult_content' ) ) {
        my $restriction_key = $post->{age_restriction} || '';
        $props->{adult_content} = {
            ''              => '',
            'none'          => 'none',
            'discretion'    => 'concepts',
            'restricted'    => 'explicit',
        }->{$restriction_key} || "";

        $props->{adult_content_reason} = $post->{age_restriction_reason} || "";
    }

    # Set entry slug if it's been specified
    $req->{slug} = LJ::canonicalize_slug( $post->{entry_slug} // '' );

    # Check if this is a community.
    $props->{admin_post} = $post->{flags_adminpost} || $props->{admin_post} || 0;

    # entry security
    my $sec = "public";
    my $amask = 0;
    {
        my $security = $post->{security} || $req->{security} || "";
        if ( $security eq "private" ) {
            $sec = "private";
        } elsif ( $security eq "access" ) {
            $sec = "usemask";
            $amask = 1;
        } elsif ( $security eq "custom" ) {
            $sec = "usemask";
            foreach my $bit ( $post->get_all( "custom_bit" ) ) {
                $amask |= (1 << $bit);
            }
        }
    }
    $req->{security} = $sec;
    $req->{allowmask} = $amask;


    # date/time
    my ( $year, $month, $day ) = split( /\D/, $post->{entrytime_date} || "" );
    my ( $hour, $min ) = split( /\D/, $post->{entrytime_time} || "" );

    # if we trust_datetime, it's because we either are in a mode where we've saved the datetime before (e.g., edit)
    # or we have run the JS that syncs the datetime with the user's current time
    # we also have to trust the datetime when the user has JS disabled, because otherwise we won't have any fallback value
    if ( $post->{trust_datetime} || $post->{nojs} ) {
        delete $req->{tz};
        $req->{year}    = $year;
        $req->{mon}     = $month;
        $req->{day}     = $day;
        $req->{hour}    = $hour;
        $req->{min}     = $min;
    }

    $req->{update_displaydate} = $post->{update_displaydate};

    # crosspost
    $req->{crosspost_entry} = $post->{crosspost_entry} ? 1 : 0;
    if ( $req->{crosspost_entry} ) {
        foreach my $acctid ( $post->get_all( "crosspost" ) ) {
            $req->{crosspost}->{$acctid} = {
                id          => $acctid,
                password    => $post->{"crosspost_password_$acctid"},
                chal        => $post->{"crosspost_chal_$acctid"},
                resp        => $post->{"crosspost_resp_$acctid"},
            };
        }
    }

    $req->{sticky_entry} = $post->{sticky_entry};

    return 1;
}

# given an LJ::Entry object, returns a hashref populated with data suitable for use in generating the form
sub _backend_to_form {
    my ( $entry ) = @_;

    # direct translation of prop values to the form

    my %formprops = map { $_ => $entry->prop( $form_to_props{$_} ) } keys %form_to_props;

    # some properties aren't in the hash above, so go through them manually
    my %otherprops = (
        taglist => join( ', ', $entry->tags ),

        entrytime_outoforder => $entry->prop( "opt_backdated" ),

        age_restriction     =>  {
                                    ''          => '',
                                    'none'      => 'none',
                                    'concepts'  => 'discretion',
                                    'explicit'  => 'restricted',
                                }->{ $entry->prop( "adult_content" ) || '' },
        age_restriction_reason => $entry->prop( "adult_content_reason" ),

        entry_slug => $entry->slug,

        flags_adminpost => $entry->prop("admin_post"),

        # FIXME: remove before taking the page out of beta
        opt_screening       => $entry->prop( "opt_screening" ),
        comment_settings    => $entry->prop( "opt_nocomments" ) ? "nocomments"
                            :  $entry->prop( "opt_noemail" ) ? "noemail"
                            : undef,
    );


    my $security = $entry->security || "";
    my @custom_groups;
    if ( $security eq "usemask" ) {
        my $amask = $entry->allowmask;

        if ( $amask == 1 ) {
            $security = "access";
        } else {
            $security = "custom";
            @custom_groups = grep { $amask & ( 1 << $_ ) } 1..60;
        }
    }

    # allow editing of embedded content
    my $event = $entry->event_raw;
    my $ju = $entry->journal;
    LJ::EmbedModule->parse_module_embed( $ju, \$event, edit => 1 );

    return {
        subject => $entry->subject_raw,
        event   => $event,

        icon        => $entry->userpic_kw,
        security    => $security,
        custom_bit  => \@custom_groups,
        is_sticky   => $entry->journal->sticky_entries_lookup->{$entry->ditemid},

        %formprops,
        %otherprops,
    };
}

sub _do_post {
    my ( $form_req, $flags, $auth, %opts ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{poster} ? $auth->{poster}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        tz          => 'guess',
        xpost       => '0', # don't crosspost by default; we handle this ourselves later
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
    }

    return ($render_ret);
}




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

        my $entry = json_from_entry($remote, $item);
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
            my $entry = json_from_entry($journal, $item);
            push @entries, $entry;
        }
        return $self->rest_ok( \@entries );
    }
}

sub json_from_entry {
    my ($remote, $item) = @_;

    my $entry = {};
    $entry->{subject_html} = $item->subject_html();
    $entry->{body_html} = $item->event_html(0);
    $entry->{poster} = $item->poster()->{user};
    $entry->{url} = $item->url();
    $entry->{security} = $item->security();
    $entry->{datetime} = $item->{eventtime};
    my @entry_tags = $item->tags();
    $entry->{tags} = (\@entry_tags);
    $entry->{icon} = $item->userpic_kw || '';
    $entry->{entry_id} = delete $item->{ditemid};
    #$item->{metadata} = $item->currents;

    if($item->editable_by($remote)) {
        $entry->{body_raw} = $item->event_raw();
        $entry->{subject_raw} = $item->subject_raw();
        $entry->{allowmask} = $item->allowmask;
    }

    return $entry;
}

###################################################
#
# Handles post of new entries, given a journal name
#
# FIXME: Doesn't handle crossposts yet.

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

    # so at this point, we know that we are authorized to edit this entry
    # but we need to handle things differently if we're an admin
    # FIXME: handle communities
    # return $self->rest_error('POST', 401, "IS AN ADMIN") unless $entry_obj->poster->equals( $remote );

            my $form_req = _backend_to_form($entry_obj);
            _form_to_backend( $form_req, $post);

                my $edit_res = _do_edit(
                        $ditemid,
                        $form_req,
                        { remote => $remote, journal => $usejournal },
                        );
                return $self->rest_ok($edit_res) if $edit_res->{success} == 1;

                # oops errors when posting: show error, fall through to show form
                return $self->rest_error( 500, $edit_res->{errors} ) if $edit_res->{errors};
            }



sub _do_edit {
    my ( $ditemid, $form_req, $auth, %opts ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{remote} ? $auth->{remote}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        xpost       => '0', # don't crosspost by default; we handle this ourselves later
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

    my $render_ret = {success => 1,
                        url => $res->{url},
                        entry_id => $ditemid};

    return ( $render_ret );
}


1;
