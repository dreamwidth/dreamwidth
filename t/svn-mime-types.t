#!/usr/bin/perl

use strict;
use Test::More;

unless ($ENV{TEST_SVN_MIME}) {
    plan skip_all => "Run with env TEST_SVN_MIME set true to run this test.";
    exit 0;
}

my %check;
my @files = `$ENV{LJHOME}/bin/cvsreport.pl --map`;
foreach my $line (@files) {
    chomp $line;
    $line =~ s!//!/!g;
    my ($rel, $path) = split(/\t/, $line);
    next unless $path =~ /\.(gif|jpe?g|png|ico)$/i;
    $check{$path} = 1;
}

plan tests => scalar keys %check;

my %badfiles;

foreach my $f (sort keys %check) {
    $f =~ s!^(\w+)/!!;
    my $dir = $1;
    chdir("$ENV{LJHOME}/cvs/$dir") or die;
    unless (-d ".svn") {
        ok(1, "$f: isn't svn");
        next;
    }
    my @props = `svn pl -v $f`;
    my %props;
    foreach my $line (@props) {
        next unless $line =~ /^\s+(\S+)\s*:\s*(.+)/;
        $props{$1} = $2;
    }

    my $mtype = $props{'svn:mime-type'} || "";
    my @errors;
    if ($props{'svn:eol-style'}) {
        push @errors, "EOL set";
    }
    if (! $mtype || $mtype =~ /^text/) {
        push @errors, "MIME=$mtype";
    }

    ok(! @errors, "$f: @errors");

    if (@errors) {
        my $oldfile = eval { slurp("$ENV{LJHOME}/cvs/$dir-oldcvs/$f") };
        my $newfile = slurp("$ENV{LJHOME}/cvs/$dir/$f");
        if ($oldfile && $oldfile eq $newfile) {
            # we can safely just fixup the mime types
            system("svn", "pdel", "svn:eol-style", $f);
            system("svn", "pset", "svn:mime-type", "application/octet-stream", $f);
            next;
        }

        push @errors, "Files don't match" if $oldfile && $oldfile ne $newfile;

        $badfiles{$f} = \@errors;


    }
}

sub slurp {
    my $f = shift;
    open(my $fh, $f) or die;
    return do { local $/; <$fh>; };
}

use Data::Dumper;
if (%badfiles) {
    warn Dumper(\%badfiles);
}

exit 0;
