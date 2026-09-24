#!/usr/bin/perl
# Disposable access-filter browser fixture.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);

my $user     = temp_user();
my $password = 'access-filter-browser-' . LJ::rand_chars(12);

$user->set_password($password);

$| = 1;
print encode_json( { user => $user->user, password => $password } ) . "\n";

<STDIN>;
