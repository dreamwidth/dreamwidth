# cgi-bin/LJ/Console/Command/MakeInvites.pm
#
# Adds console setting to create invites.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Console::Command::MakeInvites;

use strict;
use warnings;
use base qw(LJ::Console::Command);
use Carp qw(croak);
use DW::InviteCodes ();

sub cmd { "make_invites" }

sub desc { "Make invite codes. Requires priv: payments." }

sub args_desc { [
                 owner => "The username of the account on whose behalf the invite codes are generated",
                 count => "Number of invite codes to generate",
                 reason => "Why you're generating those invite codes",
                 ] }

sub usage { '<username> <count> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "payments" );
}

sub execute {
    my ($self, $username, $count, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $username && $count && $reason && scalar(@args) == 0;

    my $owner = LJ::load_user($username);

    return $self->error("Unable to load '$username'") unless $owner;

    return $self->error("$username is not a visible personal account")
        unless $owner->is_visible && $owner->is_person;

    return $self->error("'$count' isn't a positive integer")
        unless ($count =~ /^\s*\d+\s*$/) && ($count += 0);

    my $remote = LJ::get_remote();
    $reason = $remote->user . " ran make_invites $username $count '$reason'";

    my @codes = DW::InviteCodes->generate( owner => $owner, count => $count, reason => $reason );
    $self->info("Invite code: $_") foreach @codes;

    return 1;
}

1;
