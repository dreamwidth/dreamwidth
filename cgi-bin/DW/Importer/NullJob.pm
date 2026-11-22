#!/usr/bin/perl
#
# DW::Importer::NullJob
#
# A TheSchwartz job stand-in for runs that happen in-process.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::NullJob;

=head1 NAME

DW::Importer::NullJob - Does nothing with the job calls a worker makes

=head1 DESCRIPTION

Workers tell their TheSchwartz job to extend its grab, save, log and so on. A dry run
has no job, so it is given this, which accepts all of it and keeps none.

=cut

use strict;
use warnings;

sub new { return bless {}, shift }

sub arg           { $_[0]->{arg} }
sub failures      { 0 }
sub funcname      { __PACKAGE__ }
sub max_retries   { 0 }
sub debug         { }
sub grabbed_until { }
sub save          { }
sub run_after     { }
sub declined      { }

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
