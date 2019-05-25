#!/usr/bin/perl
#
# DW::EmailPost::Comment
#
# Reply to a comment via email
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::EmailPost::Comment;

use base qw(DW::EmailPost::Base);
use strict;

use Digest::SHA;

use LJ::Protocol;
use DW::CleanEmail;
use LJ::Comment;

=head1 NAME

DW::EmailPost::Comment - Handle comment replies via email

=HEAD1 SYNOPSIS

    # when generating the email:
    DW::EmailPost::Comment->replyto_address( $poster_u, $journal_u, $ditemid, $dtalkid );
=cut

sub _find_destination {
    my ( $class, @to_addresses ) = @_;

    foreach my $dest (@to_addresses) {
        next unless $dest =~ /^
                                (\S+?)          # any prefix
                                \@\Q$LJ::EMAIL_REPLY_DOMAIN\E
                                $
                                /ix;
        return $1;
    }
    return;
}

# Checks the validity of the replyto (left side of the email address).
# String is in the format of: userid-journalid-ditemid-dtalkid-auth
# Return 1 if success
sub _parse_destination {
    my ( $self, $replyto_token ) = @_;

    my ( $remote_userid, $journalid, $ditemid, $dtalkid, $message_auth ) = split "-",
        $replyto_token;

    my $u = LJ::load_userid($remote_userid);
    return unless $u;

    my $ju = LJ::load_userid($journalid);
    return unless $ju;

    $self->{u}       = $u;
    $self->{ju}      = $ju;
    $self->{journal} = $ju->user;

    # shouldn't happen but just in case
    return unless $u->emailpost_auth;

    my $class     = ref $self;
    my $real_auth = $class->_hash( $u, $ju, $ditemid, $dtalkid );
    return $self->err("Invalid secret address. Unable to post as $u->{user}.")
        unless $message_auth eq $real_auth;

    $self->{ditemid} = $ditemid;
    $self->{parent}  = $dtalkid;

    return 1;
}

sub _process {
    my $self = $_[0];

    $self->_check_sender or return $self->send_error;

    $self->_set_props( $self->{u}, %{ $self->{post_headers} || {} } );

    # remove reply cruft
    $self->{body} = DW::CleanEmail->nonquoted_text( $self->{body} );
    $self->{subject} =
        DW::EmailPost::Comment->determine_subject( $self->{subject}, $self->{ju}, $self->{ditemid},
        $self->{parent} );

    $self->cleanup_body_final;

    # build the comment
    my $req = {
        ver => 1,

        username => $self->{u}->username,
        journal  => $self->{ju}->username,
        ditemid  => $self->{ditemid},
        parent   => $self->{parent},

        body                 => $self->{body},
        subject              => $self->{subject},
        prop_picture_keyword => $self->{props}->{picture_keyword},

        useragent => "emailpost",
        editor    => "markdown",
    };

    # post!
    my $post_error;
    LJ::Protocol::do_request( "addcomment", $req, \$post_error, { noauth => 1, nocheckcap => 1 } );
    return $self->send_error( LJ::Protocol::error_message($post_error) ) if $post_error;

    return ( 1, "Comment success" );

}

# check that this either from their raw address, or one of their allowed senders
# we use raw address so that they don't need to do additional setup to reply as mobile post
sub _check_sender {
    my $self = $_[0];

    my $addrlist = LJ::Emailpost::Web::get_allowed_senders( $self->{u}, 1 );

    # well this shouldn't happen because we include their raw email in the allowed senders
    unless ( ref $addrlist && keys %$addrlist ) {
        return $self->err( "No allowed senders have been saved for your account.",
            { nomail => 1 } );
    }

    my $from = $self->{from};
    return $self->err("Unauthorized sender address: $from")
        unless grep { lc $from eq lc $_ } keys %$addrlist;

    return 1;
}

sub _set_props {
    my ( $self, $u, %post_headers ) = @_;

    my $props = {};
    $props->{picture_keyword} = $post_headers{userpic}
        || $post_headers{icon};
    $self->{props} = $props;

    return 1;
}

sub dblog_opts {
    return ( t => "reply" );
}

=head1 Class Methods

=cut

# Generates the hash to be used in the reply to address
sub _hash {
    my ( $class, $u, $ju, $ditemid, $dtalkid ) = @_;
    return Digest::SHA::sha256_hex( $ju->id . $ditemid . $dtalkid . $u->emailpost_auth );
}

=head2 C<< $class->replyto_address( $u, $journal, $ditemid, $dtalkid ) >>

Get the reply-to address for this user + journal + entry + comment combination

=cut

sub replyto_address {
    my ( $class, $u, $journalu, $ditemid, $dtalkid ) = @_;
    return join( "-",
        $u->userid, $journalu->userid, $ditemid, $dtalkid,
        $class->_hash( $u, $journalu, $ditemid, $dtalkid ) )
        . "\@$LJ::EMAIL_REPLY_DOMAIN";
}

=head2 C<< $class->replyto_address_header( $u, $journal, $ditemid, $dtalkid ) >>

Returns the reply-to address with a pretty name, suitable for use in the reply-to-address header

=cut

sub replyto_address_header {
    my ( $class, $u, $journal, $ditemid, $dtalkid ) = @_;

    my $reply_as = LJ::Lang::get_default_text(
        "emailpost.reply.address",
        {
            user => $u->display_username,
        }
    );
    my $email = $class->replyto_address( $u, $journal, $ditemid, $dtalkid );
    return qq{"$reply_as" <$email>};
}

=head2 C<< $class->determine_subject( $email_subject, $ju, $ditemid, $parent ) >>

Decide what the subject should be (either from the email or the parent comments)

=cut

sub determine_subject {
    my ( $class, $email_subject, $ju, $ditemid, $parent ) = @_;

    my $generated_subject_id = ' [ ' . $ju->display_name . ' - ' . $ditemid . ' ]';

    # use subject from email first
    my $subject = $email_subject;

    # does the email subject look like we generated it?
    # if so, then we assume we want to use the parent comment's subject (if any)
    # otherwise we assume they've set their own comment subject (no need to clean then)
    if ( $subject =~ /\Q$generated_subject_id\E$/ ) {

        # we always have a parent comment, because that's the only way we can get an auth hash
        # if that changes, we'll have to add checking here
        my $parent_obj = LJ::Comment->new( $ju, dtalkid => $parent );
        $subject = DW::CleanEmail->reply_subject( $parent_obj->subject_text );
    }

    return $subject;
}

=head1 User Methods

=head2 C<< $u->generate_emailpost_auth() >>

Generates an auth to be used when replying to a comment via email

=cut

sub generate_auth {
    my ($u) = $_[0];

    my $auth = LJ::rand_chars(32);
    $u->set_prop( emailpost_auth => $auth );

    # just log that the emailpost_auth has changed
    # automatically records remote / uniq / ip if available
    $u->log_event('emailpost_auth');

    return $auth;
}

=head2 C<< $u->emailpost_auth >>

Gets the auth to be used when replying to a comment via email.

If you don't have one yet, generate one automatically.

=cut

sub emailpost_auth {
    my ($u) = $_[0];

    return $u->prop("emailpost_auth") || $u->generate_emailpost_auth;
}

*LJ::User::generate_emailpost_auth = \&generate_auth;
*LJ::User::emailpost_auth          = \&emailpost_auth;
