# t/browser/fixtures/create-location.pl
#
# Create and remove an account for the signup location browser test.
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
use LJ::Subscription;

my $name = 'Signup Location Test';
if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    croak 'not a signup location fixture' unless $ARGV[1] =~ /^tbrowser_[a-zA-Z0-9]{6}$/;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    croak 'not a signup location fixture' unless $user->name_orig eq $name;
    $user->kill_all_sessions;
    LJ::Subscription->delete_all_subs($user);
    $user->delete_and_purge_completely;
    exit 0;
}
croak 'unexpected arguments' if @ARGV;

my $password = LJ::rand_chars(16);
my $user;
until ($user) {
    $user = LJ::User->create_personal(
        user     => 'tbrowser_' . LJ::rand_chars(6),
        email    => 'signup-location-test@example.invalid',
        password => $password,
        name     => $name,
        bdate    => '2000-01-01',
    );
}
$user->update_self( { status => 'A', statusvis => 'V' } );

print encode_json( { user => $user->user, password => $password } ) . "\n";
