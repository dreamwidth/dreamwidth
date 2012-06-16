#!/usr/bin/perl
#
# LJ::Directories
# 
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package LJ;

use strict;
use Cwd 'abs_path';
use List::MoreUtils 'uniq';

# There is no reason this be loaded, but making sure
#   Not 'use' to prevent calling an empty import().
require lib;

# Please do not yank in anything else LJ/DW:: related in this file.
#  It loaded very very early in the startups process and anything else
#  being included here ( including ljlib ) may cause very fun and interesting
#  bugs.

my $INC_PATCHED = 0;
my @FILE_DIRS;

sub get_all_paths {
    my ( $dirname, %opts ) = @_;

    my @dirs = @FILE_DIRS;

    if ( $opts{home_first} ) {
        unshift @dirs, abs_path($LJ::HOME);
    }

    return grep { -e $_ } map { $_ . "/" . $dirname } uniq @dirs;
};

sub get_all_files {
    return grep { -f $_ } get_all_paths(@_);
}

sub get_all_directories {
    return grep { -d $_ } get_all_paths(@_);
}

unless ( $INC_PATCHED ) {
    lib->import( $LJ::HOME . "/src/DSMS/lib" );

    {
        my @dirs = ();
        my $ext_path = abs_path( $LJ::HOME . "/ext" );
        die "ext directory missing" unless defined $ext_path;

        push @dirs, abs_path($LJ::HOME);
        foreach ( glob( $ext_path . "/*" ) ) {
            my $dir = abs_path($_);
            next unless -d $dir;
            push @dirs, $dir;
        }

        # FIXME: Sort the directories in some way
        @FILE_DIRS = @dirs;


        foreach my $dir ( reverse map { abs_path($_."/cgi-bin") } @dirs ) {
            lib->import($dir) if defined $dir;
        }
    }

    $INC_PATCHED = 1;
}
