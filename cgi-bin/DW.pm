#!/usr/bin/perl
#
# DW
#
# This file contains basic information which is always required when running Dreamwidth
#
# Authors:
#      Gabor Szabo <szabgab@gmail.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW;

use strict;
use warnings;

=head1 NAME

DW - Dreamwidth web application

=cut

our $VERSION = '0.01';

=head1 METHODS


=cut

# FIXME the plan is that at one point we will use File::ShareDir->dist_dir('DW')
# or some similar way to return the home directory
# Use of $LJ::HOME is definitely a bug.  See also Bugzilla discussion
# dump at https://gist.github.com/anonymous/b4fcad0ba27cc6cd1c5f#file-1760
sub home {
    return $LJ::HOME || $ENV{LJHOME};
}


1;
