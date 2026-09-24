#!/usr/bin/perl
#
# t/no-bml-references.t
#
# Calls into the deleted BML:: package compile but die at runtime.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use Test::More;
use File::Find;

my @offenders;
File::Find::find(
    {
        wanted => sub {
            return unless -f $_ && /\.(?:pm|pl|t|tt)$/;
            open my $fh, '<', $_ or return;
            local $/;
            my $content = <$fh>;
            push @offenders, $File::Find::name
                if $content =~ /(?<!\w)(?:\$)?BML::/;
        },
        no_chdir => 1,
    },
    "$ENV{LJHOME}/cgi-bin",
    "$ENV{LJHOME}/views",
    "$ENV{LJHOME}/bin",
    "$ENV{LJHOME}/ext/dw-nonfree",
);

is_deeply( \@offenders, [], 'no file references the deleted BML:: package or $BML:: globals' );

done_testing;
