#!/usr/bin/perl
#
# d10-passwords.pl
#
# Migration tool to migrate users to dversion 10, with bcrypted passwords.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
#
use v5.10;
use strict;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $dbh = LJ::get_db_writer();

use DW::Auth::Password;

while (1) {
    sleep(1);
    print "FINDING_USERS\n";

    # Get 1000 users at a time to do the migration.
    my $sth = $dbh->prepare(q{SELECT userid FROM user WHERE dversion = 9 LIMIT 1000});
    $sth->execute;
    die $sth->errstr if $sth->err;

    # Iterate each user, load, update, save
    while ( my ($uid) = $sth->fetchrow_array ) {
        my $u = LJ::load_userid($uid)
            or die "Invalid userid: $uid\n";

        # If this is not a person, there's nothing to do, so just upgrade their dversion
        # and move on.
        unless ( $u->is_person ) {
            $u->update_self( { dversion => 10 } );
            print "UPGRADED $u->{user}($uid) NOT_PERSON\n";
            continue;
        }

        # If they're expunged, we also just auto-upgrade.
        if ( $u->is_expunged ) {
            $u->update_self( { dversion => 10 } );
            print "UPGRADED $u->{user}($uid) EXPUNGED\n";
            continue;
        }

        # Valid user, get their password, set it, move on.
        my $password = DW::Auth::Password->_get_password($u)
            or die "Failed to get password on $u->{user}($uid)!\n";
        $u->set_password( $password, force_bcrypt => 1 );
        $u->update_self( { dversion => 10 } );

        # And nuke memcache, so we don't keep passwords
        # floating around there
        LJ::memcache_kill( $uid, "userid" );
        $u->memc_delete('pw');

        print "UPGRADED $u->{user}($uid) MIGRATED\n";
    }
}
