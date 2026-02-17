#!/usr/bin/perl
#
# DW::Task::IncomingEmail
#
# SQS worker task for processing incoming email via the DW::TaskQueue
# (Storable-serialized) pipeline. Delegates to DW::IncomingEmail for
# the actual processing logic.
#
# This is the LEGACY path used by bin/incoming-mail-inject.pl and
# bin/worker/dw-incoming-email. The new SES-based path uses
# bin/worker/ses-incoming-email which calls DW::IncomingEmail directly.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::IncomingEmail;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BlobStore;
use DW::IncomingEmail;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $arg = $self->args->[0];

    # Retrieve raw email: either from BlobStore (large emails) or inline
    my $raw_email;
    if ( $arg =~ /^ie:.+$/ ) {
        my $email = DW::BlobStore->retrieve( temp => $arg );
        unless ($email) {
            $log->error("Can't retrieve from BlobStore: $arg");
            return DW::Task::COMPLETED;
        }
        $raw_email = $$email;
    }
    else {
        $raw_email = $arg;
    }

    # Delegate to shared processing logic
    my $ok = DW::IncomingEmail->process($raw_email);

    return $ok ? DW::Task::COMPLETED : DW::Task::FAILED;
}

1;
