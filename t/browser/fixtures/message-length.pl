#!/usr/bin/perl
# t/browser/fixtures/message-length.pl
#
# Create a validated account for the private-message length browser test.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Carp qw(croak);
use JSON;

my $prefix = 'tbrowser_';
if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    croak 'not a message-length fixture'
        unless $ARGV[1] =~ /^tbrowser_[a-zA-Z0-9]{6}$/;
    my $u = LJ::load_user( $ARGV[1] ) or exit 0;
    croak 'not a message-length fixture'
        unless $u->name_orig eq 'Message length browser test';
    $u->delete_and_purge_completely;
    exit 0;
}
croak 'unexpected arguments' if @ARGV;

my $password = LJ::rand_chars(16);
my $u;
until ($u) {
    $u = LJ::User->create_personal(
        user     => $prefix . LJ::rand_chars(6),
        email    => 'message-length-test@example.invalid',
        password => $password,
        name     => 'Message length browser test',
    );
}
$u->update_self( { status => 'A', statusvis => 'V' } );

print encode_json(
    {
        user     => $u->user,
        password => $password,
        limit    => 0 + $u->count_usermessage_length,
    }
) . "\n";
