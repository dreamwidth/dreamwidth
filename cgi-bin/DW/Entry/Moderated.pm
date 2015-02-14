#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Entry::Moderated;

use strict;

=head1 NAME

DW::Entry::Moderated - Entry in the moderation queue

=head1 SYNOPSIS

=cut

sub new
{
    my ( $class, $cu, $modid ) = @_;

    # use dbcm to read to minimize collisions between moderators due to replication lag
    my $dbcm = LJ::get_cluster_master( $cu );

    my ( $posterid, $frozen ) = $dbcm->selectrow_array( "SELECT l.posterid, b.request_stor FROM modlog l, modblob b " .
                                                        "WHERE l.journalid=? AND l.modid=? AND l.journalid=b.journalid AND l.modid=b.modid",
                                        undef, $cu->userid, $modid );

    # not in modlog
    return unless $posterid;

    # there's no entry. maybe there was a modlog row, but not a modblob row
    # for whatever reason. let's lazy-clean. don't care if it returns a value
    # or not, because they may have legitimately just raced another moderator
    unless ( $frozen ) {
        my $sth = $dbcm->prepare( "DELETE FROM modlog WHERE journalid=? AND modid=?" );
        $sth->execute( $cu->userid, $modid );
        return;
    }

    my $raw_data = Storable::thaw( $frozen );
    my $self = bless {
        _raw_data => $raw_data,

        id        => $modid,
        journal   => $cu,
        poster    => LJ::load_userid( $posterid ),
    };

    return $self;
}

=head2 C<< $self->id >>

Returns the modid.

=cut
sub id {
    my ( $self ) = @_;

    return $self->{id};
}

=head2 C<< $self->event >>

Returns the event text cleaned, with anything that should be expanded also processed (e.g., polls)

=cut
sub event {
    my ( $self ) = @_;

    my $raw_data = $self->{_raw_data};

    # cleaning
    my $event = $raw_data->{event};
    $event =~ s/^\s+//;
    $event =~ s/\s+$//;

    if ( ( $raw_data->{lineendings} || "" ) eq "mac" ) {
        $event =~ s/\r/\n/g;
    } else {
        $event =~ s/\r//g;
    }

    my $error;
    my @polls = LJ::Poll->new_from_html( \$event, \$error, {
        journalid   => $self->journal->userid,
        posterid    => $self->poster->userid,
    });

    my $poll_preview = sub {
        my $poll = shift @polls;
        return '' unless $poll;
        return $poll->preview;
    };

    $event =~ s/<poll-placeholder>/$poll_preview->()/eg;
    LJ::CleanHTML::clean_event(\$event, { preformatted  => $raw_data->{props}->{opt_preformatted},
                                          cutpreview    => 1,
                                          cuturl        => '#',
                                     });

    # create iframe from <lj-embed> tag
    LJ::EmbedModule->expand_entry( $self->journal, \$event ) ;

    return $event;
}

=head2 C<< $self->subject >>

Returns the cleaned subject for this moderated entry.

=cut
sub subject {
    my ( $self ) = @_;

    my $subject = $self->{_raw_data}->{subject};
    LJ::CleanHTML::clean_subject( \$subject );
    return $subject;
}

=head2 C<< $self->time >>

Returns the date / time, already formatted

=cut
sub time {
    my ( $self, %opts ) = @_;

    my $raw_data = $self->{_raw_data};
    my $datestr = sprintf( "%04d-%02d-%02d", $raw_data->{year}, $raw_data->{mon}, $raw_data->{day} );
    my $etime = sprintf( "%s %02d:%02d",
                         $opts{linkify} ? LJ::date_to_view_links( $self->journal, $datestr ) : $datestr,
                         $raw_data->{hour}, $raw_data->{min} );
    return $etime;
}

=head2 C<< $self->journal >>

The journal this entry was posted in. LJ::User object.

=cut
sub journal {
    my ( $self ) = @_;

    return $self->{journal};
}

=head2 C<< $self->poster >>

The poster of this entry. LJ::User object.

=cut
sub poster {
    my ( $self ) = @_;

    return $self->{poster};
}

=head2 C<< $self->props >>

Returns all props

=cut
sub props {
    my ( $self ) = @_;

    return $self->{_raw_data}->{props};
}

=head2 C<< $self->icon >>

Returns the icon used for this entry

=cut
sub icon {
    my ( $self ) = @_;

    my $kw = $self->{props}->{picture_keyword};
    my $icon = LJ::Userpic->new_from_keyword( $self->poster, $kw );

    return $icon;
}

=head2 C<< $self->currents_html >>

Return HTML for the currents (should see if we can move this view-related code out of here)

=cut
sub currents_html {
    my ( $self ) = @_;

    my $props = $self->props;
    my %current = LJ::currents( $props, $self->poster );

    $current{Tags} = join( ", ", sort split(/\s*,\s*/, $props->{taglist} ) )
        if $props->{taglist};

    return LJ::currents_table( %current );
}

=head2 C<< $self->security_html >>

Return HTML for the security icon (should see if we can move this view-related code out of here)

=cut
sub security_html {
    my ( $self ) = @_;

    my $security = $self->{_raw_data}->{security};

    return LJ::img( "security-private" ) if $security eq "private";
    return LJ::img( "security-protected" ) if $security eq "usemask";

    return "";
}

=head2 C<< $self->age_restriction_html >>

Returns HTML for age restrictions icon (should see if we can move this view-related code out of here)

=cut
sub age_restriction_html {
    my ( $self ) = @_;

    my $age_restriction = $self->props->{adult_content};

    return LJ::img( "adult-18" ) if $age_restriction eq "explicit";
    return LJ::img( "adult-nsfw" ) if $age_restriction eq "concepts";

    return "";
}

=head2 C<< $self->age_restriction_reason >>

Returns the reason provided for the age restriction status

=cut
sub age_restriction_reason {
    my ( $self ) = @_;

    return $self->props->{adult_content_reason};
}

=head2 C<< $self->authcode >>

Return the authcode for this moderated entry

=cut
sub auth {
    my ( $self ) = @_;

    return $self->{_raw_data}->{_moderate}->{authcode};
}

=head2 C<< $self->request_data >>

Hash of the entry text / metadata. Can be used with postevent

=cut
sub request_data {
    my ( $self ) = @_;

    my %req = %{$self->{_raw_data}};
    my $poster = $self->poster;

    # in case the user renamed while the submission was in the queue
    # we need to fix up the username based on the userid we stored
    $req{user} = $poster->user;
    $req{username} = $poster->user;

    return %req;
}

=head2 C<< $self->approve >>

Approves the moderated entry and posts it to the community.
Returns ( 1, $entry_url ) on success, ( 0, $error ) on failure.

=cut
sub approve {
    my ( $self ) = @_;

    my $req = { $self->request_data };

    # allow all system logprops
    # we've already made sure that the original user didn't provide any system ones
    my $protocol_error;
    my $res = LJ::Protocol::do_request( 'postevent', $req, \$protocol_error, {
                        nomod => 1,
                        noauth => 1,
                        allow_system => 1,
              });

    if ( $res ) {
        $self->delete_from_queue;
        my $entry = LJ::Entry->new( $self->journal, jitemid => $res->{itemid}, anum => $res->{anum} );
        return ( 1, $entry->url );
    }

    my $error = "";
    $error = LJ::Protocol::error_message( $protocol_error ) if $protocol_error;
    return ( 0, $error );
}

=head2 C<< $self->reject >>

Reject the moderated entry. Returns 1 on success, 0 on failure.

=cut
sub reject {
    my ( $self ) = @_;

    $self->delete_from_queue;

    return 1;
}

=head2 C<< $self->reject_as_spam >>

Reject the moderated entry as spam. Returns 1 on success, 0 on failure.

=cut
sub reject_as_spam {
    my ( $self ) = @_;

    my $did_reject = LJ::reject_entry_as_spam( $self->journal->userid, $self->id ) ? 1 : 0;
    $self->delete_from_queue if $did_reject;

    return $did_reject;
}

=head2 C<< $self->notify_poster( $msg_ml ) >>

Sends an email to the poster of the moderated entry. Returns 1 if it was sent.

=cut
sub notify_poster {
    my ( $self, $status, %opts ) = @_;

    my $poster = $self->poster;
    return unless $poster->is_validated && $poster->is_visible;

    my $journal = $self->journal;

    my $props = $self->props;
    my $raw_data = $self->{_raw_data};
    my $ml_scope = "/communities/queue/entries/edit.tt";

    my @metadata;
    push @metadata, LJ::Lang::ml( "$ml_scope.email.submission.music", { music => $props->{current_music} } ) if $props->{current_music};
    push @metadata, LJ::Lang::ml( "$ml_scope.email.submission.mood",  { mood  => $props->{current_mood} } ) if $props->{current_mood};
    push @metadata, LJ::Lang::ml( "$ml_scope.email.submission.icon",  { icon  => $props->{picture_keyword} } ) if $props->{picture_keyword};

    my $subject = LJ::Lang::ml( "$ml_scope.email.submission.subject", { subject => $raw_data->{subject} } );
    my $time = LJ::Lang::ml( "$ml_scope.email.submission.time", { time => $self->time } );

    # this is all ugly because we only conditionally include metadata if it's available. So we can't just do this as one string
    # the trailing spaces are unfortunately necessary to introduce line breaks...
    my $submission_text = LJ::Lang::ml( "$ml_scope.email.submission", {
                            time     => "> $time  ",
                            subject  => "> $subject  ",
                            metadata => join( "\n", map { "> $_  " } @metadata ),
                            text     => LJ::markdown_blockquote( $raw_data->{event} ),
                        } );

    my $email_body = "";
    if ( $status eq 'approved' ) {
        $email_body = LJ::Lang::ml( "$ml_scope.email.body.approved", {
                            comm      => "@" . $journal->user,
                            entry_url => $opts{entry_url},
                      } );

        $email_body .= "\n\n"
                    . LJ::Lang::ml( "$ml_scope.email.body.approved.message", {
                            message  => $opts{message}
                    } ) if $opts{message};

    } elsif ( $status eq 'error' ) {
        $email_body = LJ::Lang::ml( "$ml_scope.email.body.error", {
                            comm    => "@" . $journal->user,
                            error   => $opts{error},
                      } );
    } elsif ( $status eq 'rejected' ) {
        $email_body = $opts{message}
                            ? LJ::Lang::ml( "$ml_scope.email.body.rejected_with_message", {
                                    comm    => "@" . $journal->user,
                                    message => $opts{message}
                              } )
                            : LJ::Lang::ml( "$ml_scope.email.body.rejected", {
                                    comm    => "@" . $journal->user,
                              } );
    }

    $email_body .= "\n\n"
                . $submission_text;

    LJ::send_formatted_mail(
        to => $poster->email_raw,
        greeting_user => $poster->user,

        from => $LJ::BOGUS_EMAIL,
        fromname => qq{"$LJ::SITENAME"},

        subject => LJ::Lang::ml( "$ml_scope.email.subject" ),
        body    => $email_body,
        charset => 'utf-8',
    );

    return 1;
}

=head2 C<< $self->delete_from_queue >>

Delete from the moderation queue. It's been handled now

=cut
sub delete_from_queue {
    my ( $self ) = @_;

    my $modid = $self->id;
    my $journal = $self->journal;

    # Delete this moderated entry from the list
    $journal->do( "DELETE FROM modlog WHERE journalid=? AND modid=?",
                   undef, $journal->userid, $modid );
    $journal->do("DELETE FROM modblob WHERE journalid=? AND modid=?",
           undef, $journal->userid, $modid );

    # expire mod_queue_count memcache
    $journal->memc_delete( 'mqcount' );
}

1;