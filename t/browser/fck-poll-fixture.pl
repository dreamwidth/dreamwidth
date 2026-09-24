#!/usr/bin/perl
# t/browser/fck-poll-fixture.pl
#
# Disposable accounts for the FCK poll dialog browser characterization: one
# with poll capability (the standard editor flow) and one without it (the
# no-capability notice regression).
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
use strict;
use warnings;
use JSON::MaybeXS qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
die 'Development server required' unless $LJ::IS_DEV_SERVER;

my $password = 'fck-poll-browser-' . LJ::rand_chars(12);

my $user = temp_user();
$user->set_password($password);
$user->update_self( { status => 'A' } );
$user->modify_caps( [3], [] );    # bit 3: Paid, grants can_create_polls

my $no_poll_user = temp_user();
$no_poll_user->set_password($password);
$no_poll_user->update_self( { status => 'A' } );

$| = 1;
print encode_json(
    {
        user         => $user->user,
        no_poll_user => $no_poll_user->user,
        password     => $password,
    }
) . "\n";
<STDIN>;
