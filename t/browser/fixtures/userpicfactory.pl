#!/usr/bin/perl
#
# t/browser/fixtures/userpicfactory.pl
#
# Throwaway account for the icon factory browser test.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Carp qw(croak);
use DW::BlobStore;
use JSON;

my $prefix = 'tbrowser_crop';

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    croak "not a crop fixture account: $ARGV[1]" unless index( $ARGV[1], $prefix ) == 0;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    DW::BlobStore->delete( temp => 'upf_0:' . $user->id );
    $user->delete_and_purge_completely;
    exit 0;
}

my $password = LJ::rand_chars(16);
my $user;
until ($user) {
    $user = LJ::User->create_personal(
        user     => $prefix . LJ::rand_chars(5),
        email    => 'browser-test@example.com',
        password => $password,
        name     => 'Browser test',
    );
}
$user->update_self( { status => 'A', statusvis => 'V' } );
print encode_json( { user => $user->user, password => $password } ), "\n";
