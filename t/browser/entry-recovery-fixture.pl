#!/usr/bin/perl
# Disposable account for the recovery-page browser characterization.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON::MaybeXS qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
die 'Development server required' unless $LJ::IS_DEV_SERVER;
my $user     = temp_user();
my $password = 'recovery-browser-' . LJ::rand_chars(12);
$user->set_password($password);
$user->update_self( { status => 'A' } );
$| = 1;
print encode_json( { user => $user->user, password => $password } ) . "\n";
<STDIN>;
