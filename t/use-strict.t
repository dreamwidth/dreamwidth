#!/usr/bin/perl

use strict;
use Test::More;

unless ($ENV{TEST_TODO}) {
    plan skip_all => "This test fails too much to be run for everyone.";
    exit;
}

my %check;
my @files = `$ENV{LJHOME}/bin/cvsreport.pl --map`;
foreach my $line (@files) {
    chomp $line;
    $line =~ s!//!/!g;
    my ($rel, $path) = split(/\t/, $line);
    next unless $path =~ /\.(pl|pm)$/;
    $check{$rel} = 1;
}

plan tests => scalar keys %check;

my @bad;
foreach my $f (sort keys %check) {
    my $strict = 0;
    open (my $fh, $f) or die;
    while (<$fh>) {
        $strict = 1 if /^use strict;/;
    }
    ok($strict, "strict in $f");
    push @bad, $f unless $strict;
}

foreach my $bad (@bad) {
    diag("Missing strict: $bad");
}

