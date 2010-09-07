#!/usr/bin/perl

use strict;
use Test::More;

my %check;
my @files = `$ENV{LJHOME}/bin/cvsreport.pl --map`;
foreach my $line (@files) {
    chomp $line;
    $line =~ s!//!/!g;
    my ($rel, $path) = split(/\t/, $line);
    next unless $path =~ /\.(pl|pm)$/;
    # skip stuff we're less concerned about or don't control
    next if $path =~ m:\b(doc|etc|fck|miscperl|src|s2)/:;
    $check{$rel} = 1;
}

plan tests => scalar keys %check;

my @bad;
foreach my $f (sort keys %check) {
    my $strict = 0;
    open (my $fh, $f) or die "Could not open $f: $!";
    while (<$fh>) {
        $strict = 1 if /^use strict;/;
    }
    ok($strict, "strict in $f");
    push @bad, $f unless $strict;
}

foreach my $bad (@bad) {
    diag("Missing strict: $bad");
}

