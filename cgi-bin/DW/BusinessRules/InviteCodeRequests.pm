#!/usr/bin/perl
#
# DW::BusinessRules::InviteCodeRequests
#
# This module implements business rules for invite code requests (both
# default/stub and site-specific through DW::BusinessRules and
# DW::BusinessRules::InviteCodeRequests::*).
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::BusinessRules::InviteCodeRequests;
use strict;
use warnings;
use base 'DW::BusinessRules';

=head1 NAME

DW::BusinessRules::InviteCodeRequests - business rules for invite code requests handling

=head1 SYNOPSIS

  my $can_request = DW::BusinessRules::InviteCodeRequests::can_request( user => $u );

=cut

=head1 API

=head2 C<< DW::BusinessRules::InviteCodeRequests::can_request( user => $u ) >> 

Return whether the user can make a request for more invite codes. Default implementation allows the user
to make a new request if they have no unused invite codes, they have no pending requests for review, and
are not sysbanned from using the invites system.

=cut

sub can_request {
    my (%opts) = @_;
    return 0 unless $opts{user}->is_person;
    my $userid = $opts{user}->id;

    my $unused_count = DW::InviteCodes->unused_count( userid => $userid );
    return 0 if $unused_count;

    my $outstanding_count = DW::InviteCodeRequests->outstanding_count( userid => $userid );
    return 0 if $outstanding_count;

    return 0 if DW::InviteCodeRequests->invite_sysbanned( user => $opts{user} );

    return 1;
}

DW::BusinessRules::install_overrides( __PACKAGE__, qw( can_request ) );

1;

=head1 BUGS

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut
