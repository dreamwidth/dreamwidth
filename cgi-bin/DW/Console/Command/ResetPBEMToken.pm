#!/usr/bin/perl
#
# DW::Console::Command::ResetPBEMToken
#
# Console command for resetting PBEM tokens
#
# Authors:
#      Adam Bernard <https://pseudomonas.dreamwidth.org>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Console::Command::ResetPBEMToken;
use strict;

use base qw/ LJ::Console::Command /;

sub cmd  { 'reset_token' }
sub desc { 'Reset post-by-email token. Requires priv: reset_email.' }

sub args_desc {
    [
        'username' => 'Username of the account whose token is to be reset',
        'reason'   => 'Reason for resetting it.',
    ]
}
sub usage { '<username> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("reset_email");
}

sub execute {
    my ( $self, $username, $reason, @args ) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $username && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($username);
    return $self->error("Invalid user $username")
        unless $u;

    my $newauth = $u->generate_emailpost_auth();

    return $self->error("Token not reset") unless $newauth;

    my $sitename = $LJ::SITENAME;
    my $rv       = LJ::send_mail(
        {
            to       => $u->email_raw,
            from     => $LJ::ANTISPAM_EMAIL,
            fromname => "The $sitename Team",
            subject  => "Your Dreamwidth reply-by-email token has been reset",
            body     => qq{
Dear username,

A $sitename administrator has reset the secret token for your account to use to post comments by email. We had to reset the token, because your account was being used to email spam to the unique reply-to address for one or more comment notifications you received.

Usually this happens because someone got access to your email account and 'harvested' the addresses from messages that were in your inbox. We strongly suggest that you change the password for your email account. We don't know for sure that a spammer broke into your account, but that's usually how a situation like this happens, and it's better to be safe than sorry.

Any old comment notification emails you have in your inbox that were sent to you before your token was changed will no longer work to reply by email. You'll need to follow the links in those notification emails to reply directly on the website. Any comment notification email sent to you after the token was changed will work as usual.

If you have any questions, you can reply to this email.

Best,
The $sitename Team
}

        }
    );

    $self->info("Notification email not sent") unless $rv;

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, "reset_token", $reason );

    return $self->print("Post-by-email token for '$username' reset.");
}

1;
