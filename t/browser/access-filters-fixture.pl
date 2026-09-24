#!/usr/bin/perl
# Disposable access-filter browser fixture.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user temp_comm);

my $user     = temp_user();
my $friend   = temp_user();
my $comm     = temp_comm();
my $outsider = temp_user();
my $password = 'access-filter-browser-' . LJ::rand_chars(12);

$user->set_password($password);
$user->add_edge( $friend, trust => { mask => 1, nonotify => 1 } );
LJ::set_rel( $comm, $user, 'A' );

$| = 1;
print encode_json(
    {
        user      => $user->user,
        password  => $password,
        friend    => $friend->user,
        community => $comm->user,
        outsider  => $outsider->user,
    }
) . "\n";

<STDIN>;
