#!/usr/bin/perl

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

use Test::More;
use LJ::Directories;

my %check;

# bit of a hack. We assume that everything we care about is in a git repo
# which could be under $LJHOME, or $LJHOME/ext
foreach my $repo ( LJ::get_all_directories( ".git" ) ) {
    my @files = eval{ split( /\n/, qx`git --git-dir "$repo" ls-tree -r --full-tree --name-only HEAD` ) };
    next unless @files;

    $repo =~ s!/\.git!!;
    foreach my $line (@files) {
        chomp $line;
        $line =~ s!//!/!g;
        my $path = "$repo/$line";
        next unless $path =~ /\.(pl|pm)$/;
        # skip stuff we're less concerned about or don't control
        next if $path =~ m:\b(doc|etc|fck|miscperl|src|s2)/:;
        $check{$path} = 1;
    }
}
plan tests => scalar keys %check;

my @bad;
foreach my $f (sort keys %check) {
    my $strict = 0;
    open (my $fh, $f) or die "Could not open $f: $!";
    while (<$fh>) {
        if( /^use strict;/ ) {
            $strict = 1;
            last;
        }
    }
    close $fh;
    ok($strict, "strict in $f");
    push @bad, $f unless $strict;
}

foreach my $bad (@bad) {
    diag("Missing strict: $bad");
}

