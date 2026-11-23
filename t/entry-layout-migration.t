#!/usr/bin/perl
#
# t/entry-layout-migration.t
#
# bin/upgrading/migrate-updatepage-beta.pl gives people in the retired
# "updatepage" beta the advanced entry form layout, and leaves everyone else
# and any layout already chosen alone.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);

plan skip_all => 'The migration requires a development database' unless $LJ::IS_DEV_SERVER;

my $script = "$ENV{LJHOME}/bin/upgrading/migrate-updatepage-beta.pl";

my %users = map { $_ => temp_user() } qw(beta both other chose none);
$users{beta}->set_prop( betafeatures_list => 'updatepage' );
$users{both}->set_prop( betafeatures_list => 'nos2foundation, updatepage' );
$users{other}->set_prop( betafeatures_list => 'nos2foundation,updatepagex' );
$users{chose}->set_prop( betafeatures_list => 'updatepage' );

# choosing simple while unset (the default) must still be stored
is( $users{chose}->entryform_layout('simple'), 'simple', 'an explicit simple choice is stored' );

# only touch this test's accounts, not other beta users in the database
my @only = map { '--userid=' . $_->id } values %users;

# the script runs in its own process, so drop this one's cached users
sub layouts {
    LJ::start_request();
    return {
        map { $_ => LJ::load_userid( $users{$_}->id, 1 )->raw_prop('entryform_layout') // '' }
            keys %users
    };
}

like( `$^X $script --dry-run @only`, qr/would be set to/, 'a dry run reports what it would do' );
is_deeply(
    layouts(),
    { beta => '', both => '', other => '', chose => 'simple', none => '' },
    'and changes nothing'
);

is( system( $^X, $script, @only ), 0, 'the migration runs' );
is_deeply(
    layouts(),
    { beta => 'advanced', both => 'advanced', other => '', chose => 'simple', none => '' },
    'beta users get the advanced layout; other users and chosen layouts are untouched'
);
LJ::start_request();
is( LJ::load_userid( $users{beta}->id, 1 )->entryform_layout,
    'advanced', 'which old links then open' );

done_testing;
