#!/usr/bin/perl
#
# DW::ContentImporter
#
# Web backend functions for Content Importing
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::ContentImporter;

=head1 NAME

DW::ContentImporter - Web backend functions for Content Importing

=cut

use strict;
use Carp qw/ croak /;
use DW::XML::Parser;

=head1 API

=head2 C<< $class->queue_import( $user, $importer, $data ); >>

This function sets up an import for the specified user if one is currently
not in progress.  The contents of data are importer specific, and $importer
is specified as a string version of the full class name.

This returns undef if there is currently a import job queued/running for
the user, otherwise returns the new job handle.

=cut

sub queue_import {
    my ( $class, $u, $importer, $data ) = @_;
    $u = LJ::want_user($u)
        or croak 'invalid user object passed to queue_import';

    # job is already in progress
    return undef
        if $class->current_job($u);

    my $sh = LJ::theschwartz()
        or croak 'content importer requires TheSchwartz';

    my $new_job = TheSchwartz::Job->new(
        funcname => $importer,
        uniqkey  => "import-" . $u->id,
        arg      => {
            %$data, target => $u->id
        }
    ) or croak 'unable to create importer job';

    my $h = $sh->insert($new_job)
        or croak 'unable to insert importer job';

    my $jobid = $h->dsn_hashed . "-" . $h->jobid;
    $u->set_prop( import_job => $jobid );
    return $h;
}

=head2 C<< $class->current_job( $user ); >>

This function returns the current import job for the user.

=cut

sub current_job {
    my ( $class, $u ) = @_;
    $u = LJ::want_user($u)
        or croak 'invalid user object passed to queue_import';

    my $jobid = $u->prop('import_job')
        or return undef;

    my $sh = LJ::theschwartz()
        or croak 'unable to contact TheSchwartz';
    my $job = eval { $sh->lookup_job($jobid); };
    return $job if $job;

    # Job seems to not exist
    $u->set_prop( import_job => '' );
    return undef;
}

1;
