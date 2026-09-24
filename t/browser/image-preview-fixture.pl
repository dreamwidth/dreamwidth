#!/usr/bin/perl
# Disposable image-preview browser fixture.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
my $user     = temp_user();
my $password = 'image-preview-browser-' . LJ::rand_chars(12);
$user->set_password($password);
$user->update_self( { status => 'A' } );
$| = 1;
print encode_json( { user => $user->user, password => $password } ) . "\n";
<STDIN>;
