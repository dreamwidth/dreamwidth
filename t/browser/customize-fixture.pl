#!/usr/bin/perl
# Disposable authenticated fixture for browser customization acceptance.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON::MaybeXS qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

my $user     = temp_user();
my $comm     = temp_comm();
my $password = 'browser-customize-' . LJ::rand_chars(12);
$user->set_password($password);
LJ::set_rel( $comm, $user, 'A' );
$| = 1;
print encode_json( { user => $user->user, password => $password, community => $comm->user } )
    . "\n";
<STDIN>;
