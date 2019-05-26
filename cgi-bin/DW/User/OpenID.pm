#!/usr/bin/perl
#
# DW::User::OpenID
#
# Adds OpenID claim functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

package DW::User::OpenID;
use strict;

# get the claims that a user has. this returns an array of user objects for
# the relevant OpenID accounts.
sub get_openid_claims {
    my $u = LJ::want_user( $_[0] )
        or die "need a user!\n";

    my $dbh = LJ::get_db_writer()
        or die "need database\n";
    my $claims = $dbh->selectall_arrayref(
        'SELECT userid, claimed_userid FROM openid_claims WHERE userid = ?',
        undef, $u->id );
    return () unless $claims && ref $claims eq 'ARRAY';
    return map { LJ::load_userid( $_->[1] ) } @$claims;
}
*LJ::User::get_openid_claims = \&get_openid_claims;

# if we're claimed, return a user object of the claimant
sub claimed_by {
    my $u = LJ::want_user( $_[0] )
        or die "need a user!\n";
    return undef unless $u->is_identity;

    my $dbh = LJ::get_db_writer()
        or die "need database\n";
    my $userid = $dbh->selectrow_array( 'SELECT userid FROM openid_claims WHERE claimed_userid = ?',
        undef, $u->id );
    return undef unless $userid;
    return LJ::load_userid($userid);
}
*LJ::User::claimed_by = \&claimed_by;

# do a claim
sub claim_identity {
    my $u = LJ::want_user( $_[0] )
        or die "need a user!\n";
    my $ou = LJ::want_user( $_[1] )
        or die "need an identity!\n";

    die "account types not right in claiming\n"
        unless $u->is_person && $ou->is_identity;

    # Insert this into the database. We do this first in case it fails,
    # then we don't want to kick off the job below.
    my $dbh = LJ::get_db_writer()
        or die "need database\n";
    $dbh->do( 'INSERT INTO openid_claims (userid, claimed_userid) VALUES (?, ?)',
        undef, $u->id, $ou->id );
    die "database error claiming: " . $dbh->errstr . "\n"
        if $dbh->err;

    # Now we need to kick off the job that actually goes and reclaims things.
    my $sclient = LJ::theschwartz()
        or die "openid claiming requires TheSchwartz\n";
    $sclient->insert( 'DW::Worker::ChangePosterId',
        { from_userid => $ou->id, to_userid => $u->id } );
    return 1;
}
*LJ::User::claim_identity = \&claim_identity;

1;
