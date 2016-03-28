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

# There is no reason for this to not be loaded, but making sure
#   Not 'use' to prevent calling an empty import().
require lib;

# Please do not yank in anything else LJ/DW:: related in this file.
#  It loaded very very early in the startups process and anything else
#  being included here ( including ljlib ) may cause very fun and interesting
#  bugs.
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

sub resolve_file {
    return ( get_all_files(@_) )[0];
}

sub resolve_directory {
    return ( get_all_directories(@_) )[0];
}

my %SCOPE_ORDER = (
    general => 0,
    'local' => 1,
    private => 2,
    highest => 1000,
);

my @SCOPES =
    sort { $SCOPE_ORDER{$b} <=> $SCOPE_ORDER{$a} } keys %SCOPE_ORDER;

lib->import( $ENV{LJHOME} . "/src/DSMS/lib" );

{
    my @dirs = ();
    my $ext_path = abs_path( $ENV{LJHOME} . "/ext" );
    die "ext directory missing" unless defined $ext_path;

    my %dir_scopes = (
        'general' => [
            abs_path($ENV{LJHOME})
        ]
    );

    foreach ( glob( $ext_path . "/*" ) ) {
        my $dir = abs_path($_);
        next unless -d $dir;
        my $scope = 'general';
        if ( -e "$dir/.dir_scope" ) {
            open my $fh, "<", "$dir/.dir_scope";
            $scope = <$fh>;
            chomp $scope;
            close $fh;
        }
        die "$dir has invalid scope '$scope'" unless exists $SCOPE_ORDER{$scope};
        push @{ $dir_scopes{$scope} }, $dir;
    }

    @FILE_DIRS = map { @{ $dir_scopes{$_} || [] } } @SCOPES;

    use lib "$ENV{LJHOME}/extlib/lib/perl5";
    foreach my $dir ( reverse map { abs_path($_."/cgi-bin") } @FILE_DIRS ) {
        lib->import($dir) if defined $dir;
    }
}

1;
