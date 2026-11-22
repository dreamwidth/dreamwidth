#!/usr/bin/perl
#
# t/browser/fixtures/entry-community.pl
#
# Fixture for t/browser/entry-community-reading.js: a throwaway account that
# can post to a throwaway community, with the entry form's Display Date panel
# turned on. Prints the details as JSON. With --delete USER, purges an account
# this script created.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use JSON;

my $PREFIX = 'tbrowser_';

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {

    # Refuse to purge anything this script didn't create.
    croak "not a fixture account: $ARGV[1]" unless index( $ARGV[1], $PREFIX ) == 0;
    my $u = LJ::load_user( $ARGV[1] ) or exit 0;
    $u->delete_and_purge_completely;
    exit 0;
}

my $password = LJ::rand_chars(16);
my $u;
until ($u) {
    $u = LJ::User->create_personal(
        user     => $PREFIX . LJ::rand_chars(6),
        email    => "browser-test\@example.com",
        password => $password,
        name     => 'Browser test',
    );
}
$u->update_self( { status => 'A', statusvis => 'V' } );

# New accounts hide the Display Date panel until it is enabled in Entry Options.
my $panels = $u->entryform_panels;
$panels->{show}->{displaydate} = 1;
$u->entryform_panels($panels);

# The creator becomes a maintainer and a member with posting access.
my $comm;
until ($comm) {
    $comm = LJ::User->create_community(
        user         => $PREFIX . LJ::rand_chars(6),
        name         => 'Browser test community',
        admin_userid => $u->id,
        membership   => 'open',
        postlevel    => 'members',
    );
}
croak "fixture account cannot post to its community" unless $u->can_post_to($comm);

print encode_json(
    {
        user      => $u->user,
        password  => $password,
        community => $comm->user,
    }
);
print "\n";
