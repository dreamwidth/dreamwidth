#!/usr/bin/perl
#
# DW::Entry
#
# Helper class for Entry-related methods shared between both web UI and API controllers.
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Entry;

use strict;
use Carp qw/ croak confess /;

my %form_to_props = (

    # currents / metadata
    current_mood       => "current_moodid",
    current_mood_other => "current_mood",
    current_music      => "current_music",
    current_location   => "current_location",
);

# given an LJ::Entry object, returns a hashref populated with data suitable for use in generating the form
sub _backend_to_form {
    my $for_api = shift;
    my ($entry) = @_;

    # direct translation of prop values to the form

    my $event = $entry->event_raw;
    unless ($for_api) {

        # Look up formatting for newer entries...
        my $editor = $entry->prop('editor');

        # ...or, figure out formatting when editing old entries.
        # TODO: This duplicates some logic from LJ::CleanHTML for guessing an editor
        # value for old posts. Would be nice to centralize it in the Entry class,
        # except that if we're detecting old-style !markdown, we DO want to also
        # mutate the body text, which makes it hairy.
        unless ($editor) {
            if ( LJ::CleanHTML::legacy_markdown( \$event ) ) {    # mutates $event
                $editor = 'markdown0';
            }
            elsif ( $entry->prop('used_rte') ) {
                $editor = 'rte0';
            }
            elsif ( $entry->prop('opt_preformatted') ) {
                $editor = 'html_raw0';
            }
            elsif ( $entry->prop('import_source') ) {
                $editor = 'html_casual0';
            }
            elsif ( $entry->logtime_mysql lt '2019-05' ) {
                $editor = 'html_casual0';
            }
            else {
                $editor = 'html_casual1';    # For accurate state when editing posts.
            }
        }
    }
    my %formprops = map { $_ => $entry->prop( $form_to_props{$_} ) } keys %form_to_props;

    # some properties aren't in the hash above, so go through them manually
    my %otherprops = (
        taglist => join( ', ', $entry->tags ),

        entrytime_outoforder => $entry->prop("opt_backdated"),

        age_restriction => {
            ''         => '',
            'none'     => 'none',
            'concepts' => 'discretion',
            'explicit' => 'restricted',
        }->{ $entry->prop("adult_content") || '' },
        age_restriction_reason => $entry->prop("adult_content_reason"),

        entry_slug => $entry->slug,

        flags_adminpost => $entry->prop("admin_post"),

        # FIXME: remove before taking the page out of beta
        opt_screening      => $entry->prop("opt_screening"),
          comment_settings => $entry->prop("opt_nocomments") ? "nocomments"
        : $entry->prop("opt_noemail") ? "noemail"
        :                               undef,
    );

    unless ($is_api) {

        # At this point we know enough to get the full list of editors (and
        # selection state) for the dropdown, but because of how the template
        # variables are laid out, we shouldn't really do that from here. (This
        # function's whole return value becomes 'formdata' in the template
        # vars.) So we'll pass this along, and the caller (currently just _edit)
        # will use it to get the list for the dropdown.
        $otherprops{editor} = DW::Formats::validate($editor);
    }

    my $security = $entry->security || "";
    my @custom_groups;
    if ( $security eq "usemask" ) {
        my $amask = $entry->allowmask;

        if ( $amask == 1 ) {
            $security = "access";
        }
        else {
            $security      = "custom";
            @custom_groups = grep { $amask & ( 1 << $_ ) } 1 .. 60;
        }
    }

    # allow editing of embedded content
    my $event = $entry->event_raw;
    my $ju    = $entry->journal;
    LJ::EmbedModule->parse_module_embed( $ju, \$event, edit => 1 );

    my $form = {
        subject => $entry->subject_raw,
        event   => $event,

        security   => $security,
        custom_bit => \@custom_groups,
        is_sticky  => $entry->journal->sticky_entries_lookup->{ $entry->ditemid },

        %formprops,
        %otherprops,
    };

    if ($is_api) {
        $form->{icon} = $entry->userpic_kw;
    }
    else {
        $form->{prop_picture_keyword} = $entry->userpic_kw;
    }
    return $form;
}

# decodes the posted form into a hash suitable for use with the protocol
# $post is expected to be an instance of Hash::MultiValue
# There are some flags here because the API and web ui handle edits differently:
# in the web ui, old values are automatically prefilled into the form, and the lack
# of a value means it has been explicitly removed by the user.
# In the the API, missing values are assumed to be unchanged, and the controller
# through explicit empty values (while they aren't included in POSTs to the web controller)
sub _form_to_backend {
    my ( $is_api, $req, $post, %opts ) = @_;

    # handle event subject and body
    if ($is_api) {
        $req->{subject} = $post->{subject} || $req->{subject};
        $req->{event}   = $post->{text}    || $req->{event} || "";
    }
    else {
        # handle event subject and body
        $req->{subject} = $post->{subject};
        $req->{event}   = $post->{event} || "";

        $errors->add( undef, ".error.noentry" )
            if $errors && $req->{event} eq "" && !$opts{allow_empty};

        # warn the user of any bad markup errors
        my $clean_event = $post->{event};
        my $errref;

        my $editor = undef;
        my $verbose_err;

        LJ::CleanHTML::clean_event( \$clean_event,
            { errref => \$errref, editor => $editor, verbose_err => \$verbose_err } );

        if ( $errors && $verbose_err ) {
            if ( ref($verbose_err) eq 'HASH' ) {
                $errors->add( undef, $verbose_err->{error}, $verbose_err->{opts} );
            }
            else {
                $errors->add( undef, $verbose_err );
            }
        }
    }

    # initialize props hash
    $req->{props} ||= {};
    my $props = $req->{props};

    while ( my ( $formname, $propname ) = each %form_to_props ) {
        if ($is_api) {
            $props->{$propname} = $post->{$formname}
                if defined $post->{$formname};
        }
        else {
            $props->{$propname} = $post->{$formname} // '';
        }
    }

    # a few of the fields have different names between the web UI and the API
    my $tag_name     = $is_api ? 'taglist'      : 'tags';
    my $userpic_name = $is_api ? 'icon_keyword' : 'prop_picture_keyword';
    $props->{taglist}         = $post->{$tag_name}     if defined $post->{$tag_name};
    $props->{picture_keyword} = $post->{$userpic_name} if defined $post->{$userpic_name};
    $props->{opt_backdated} = $post->{entrytime_outoforder} ? 1 : 0;

    unless ($is_api) {

        # This form always uses the editor prop instead of opt_preformatted.
        $props->{opt_preformatted} = 0;
        $props->{editor}           = DW::Formats::validate( $post->{editor} );
    }

    # old implementation of comments
    # FIXME: remove this before taking the page out of beta
    $props->{opt_screening} = $post->{opt_screening};
    $props->{opt_nocomments} =
        $post->{comment_settings} && $post->{comment_settings} eq "nocomments" ? 1 : 0;
    $props->{opt_noemail} =
        $post->{comment_settings} && $post->{comment_settings} eq "noemail" ? 1 : 0;

    # see if an "other" mood they typed in has an equivalent moodid
    if ( $props->{current_mood} ) {
        if ( my $moodid = DW::Mood->mood_id( $props->{current_mood} ) ) {
            $props->{current_moodid} = $moodid;
            if ($is_api) {
                delete $props->{current_mood};
            }
            else {
                $props->{current_mood} = '';
            }
        }
    }

    # nuke taglists that are just blank
    $props->{taglist} = "" unless $props->{taglist} && $props->{taglist} =~ /\S/;

    if ( LJ::is_enabled('adult_content') ) {
        my $restriction_key = $post->{age_restriction} || '';
        $props->{adult_content} = {
            ''           => '',
            'none'       => 'none',
            'discretion' => 'concepts',
            'restricted' => 'explicit',
        }->{$restriction_key}
            || "";

        $props->{adult_content_reason} = $post->{age_restriction_reason} || "";
    }

    # Set entry slug if it's been specified
    $req->{slug} = LJ::canonicalize_slug( $post->{entry_slug} // '' );

    # Check if this is a community.
    $props->{admin_post} =
        $is_api
        ? ( $post->{flags_adminpost} || $props->{admin_post} || 0 )
        : ( $post->{flags_adminpost} || 0 );

    # entry security
    my $sec   = "public";
    my $amask = 0;
    {
        my $security =
            $is_api
            ? ( $post->{security} || $req->{security} || "" )
            : ( $post->{security} || "" );
        if ( $security eq "private" ) {
            $sec = "private";
        }
        elsif ( $security eq "access" ) {
            $sec   = "usemask";
            $amask = 1;
        }
        elsif ( $security eq "custom" ) {
            $sec = "usemask";
            foreach my $bit ( $post->get_all("custom_bit") ) {
                $amask |= ( 1 << $bit );
            }
        }
    }
    $req->{security}  = $sec;
    $req->{allowmask} = $amask;

    # date/time
    my ( $year, $month, $day ) = split( /\D/, $post->{entrytime_date} || "" );
    my ( $hour, $min ) = split( /\D/, $post->{entrytime_time} || "" );

# if we trust_datetime, it's because we either are in a mode where we've saved the datetime before (e.g., edit)
# or we have run the JS that syncs the datetime with the user's current time
# we also have to trust the datetime when the user has JS disabled, because otherwise we won't have any fallback value
    if ( $post->{trust_datetime} || $post->{nojs} ) {
        delete $req->{tz};
        $req->{year} = $year;
        $req->{mon}  = $month;
        $req->{day}  = $day;
        $req->{hour} = $hour;
        $req->{min}  = $min;
    }

    $req->{update_displaydate} = $post->{update_displaydate};

    # crosspost
    $req->{crosspost_entry} = $post->{crosspost_entry} ? 1 : 0;
    if ( $req->{crosspost_entry} ) {
        foreach my $acctid ( $post->get_all("crosspost") ) {
            $req->{crosspost}->{$acctid} = {
                id       => $acctid,
                password => $post->{"crosspost_password_$acctid"},
                chal     => $post->{"crosspost_chal_$acctid"},
                resp     => $post->{"crosspost_resp_$acctid"},
            };
        }
    }

    $req->{sticky_entry}  = $post->{sticky_entry};
    $req->{sticky_select} = $post->{sticky_select};

    return 1;
}

sub _save_new_entry {
    my ( $form_req, $flags, $auth ) = @_;

    my $req = {
        ver        => $LJ::PROTOCOL_VER,
        username   => $auth->{poster} ? $auth->{poster}->user : undef,
        usejournal => $auth->{journal} ? $auth->{journal}->user : undef,
        tz         => 'guess',
        xpost => '0',    # don't crosspost by default; we handle this ourselves later
        %$form_req
    };

    my $err = 0;
    my $res = LJ::Protocol::do_request( "postevent", $req, \$err, $flags );

    return { errors => LJ::Protocol::error_message($err) } unless $res;
    return $res;
}

sub _save_editted_entry {
    my ( $ditemid, $form_req, $auth ) = @_;

    my $req = {
        ver        => $LJ::PROTOCOL_VER,
        username   => $auth->{poster} ? $auth->{poster}->user : undef,
        usejournal => $auth->{journal} ? $auth->{journal}->user : undef,
        xpost  => '0',             # don't crosspost by default; we handle this ourselves later
        itemid => $ditemid >> 8,
        %$form_req
    };

    my $err = 0;
    my $res = LJ::Protocol::do_request(
        "editevent",
        $req,
        \$err,
        {
            noauth => 1,
            u      => $auth->{poster},
        }
    );

    return { errors => LJ::Protocol::error_message($err) } unless $res;
    return $res;
}

1;
