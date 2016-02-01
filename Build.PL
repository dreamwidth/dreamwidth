# Build.PL - sets up and generates a test coverage report
#
# Author: szabgab
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;
use Module::Build;

# Requirements
# See bin/checkconfig.pl
# as explained in:
# http://wiki.dreamwidth.net/notes/Dreamwidth_Scratch_Installation#Make_sure_things_are_working_with_checkconfig.pl

# Setting Up
# Run this script to generate the Build script:
#   perl Build.PL
#
# Run the generated file to copy some files and set things up for tests:
#   ./Build

# Running
# Run the tests in regular mode with this:
#   ./Build test # runs the tests in regular mode; not really needed here
#
# Generate test coverage with this:
#   DEVEL_COVER_OPTIONS=-ignore,/usr/local ./Build testcover
#
# or add 
#   export DEVEL_COVER_OPTIONS=-ignore,/usr/local
#   to .bashrc and then you can use
# ./Build testcover


my $builder = Module::Build->new(
    module_name       => 'DW',
    #license           => 'gpl',
    #dist_author       => '',
    #dist_version_from => 'lib/Test/Most.pm',
    dist_version => '0.01',
    # TODO: see above
    requires          => {
        'DBI'           => 0,
        'perl'              => '5.006',
    },
    #add_to_cleanup     => ['DW-*'],
    create_makefile_pl => 'none',
);

$builder->create_build_script();

