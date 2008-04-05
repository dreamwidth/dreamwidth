#!/usr/bin/perl
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::LangDatFile;
use Test::More 'no_plan';

my $trans = LJ::LangDatFile->new("$ENV{LJHOME}/t/data/sampletrans.dat");
ok($trans, "Constructed a trans object");

like($trans->value("/loldongs.bml.btn.status"), qr/thizz face/i, "Parsed translation string");
like($trans->value("/lolsquatch.bml.banner"), qr/hyphytown/, "Parsed multiline translation string");

# test foreach_key
my %foundkeys = ();
$trans->foreach_key(sub {
    my $key = shift;
    $foundkeys{$key}++;
    is($trans->value($key), $trans->{values}->{$key}, "Key found");
});

my @all_keys  = $trans->keys;
my @grep_keys = grep { $foundkeys{$_} == 1 } $trans->keys;

is(scalar @all_keys, scalar @grep_keys, "All keys found");

# change a value, write the file out, and make sure the new parsed file matches the currently parsed version
$trans->set("/loldongs.bml.btn.status", 'thizz face');
$trans->save;

# read the file back in, make sure state is the same
my $trans2 = LJ::LangDatFile->new("$ENV{LJHOME}/t/data/sampletrans.dat");
is_deeply($trans2->{values}, $trans->{values}, "State preserved between file saving");
