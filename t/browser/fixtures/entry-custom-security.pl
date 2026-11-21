#!/usr/bin/perl
#
# t/browser/fixtures/entry-custom-security.pl
#
# Create or purge a synthetic journal with three custom access groups, or read
# the saved security of a test entry belonging to that journal.
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
use LJ::Entry;

my $prefix = 'tbrowser_sec_';

if (@ARGV) {
    my ( $action, $name, $subject ) = @ARGV;
    croak 'Not a custom security fixture' unless index( $name, $prefix ) == 0;
    my $user = LJ::load_user($name);
    if ( $action eq '--delete' ) {
        if ($user) {
            foreach my $entry ( $user->recent_entries( filtered_for => $user ) ) {
                LJ::delete_entry( $user, $entry->jitemid );
            }
            $user->delete_trust_group( id => $_->{groupnum} ) for $user->trust_groups;
            $user->kill_all_sessions;
            $user->delete_and_purge_completely;
        }
        exit 0;
    }
    croak 'Expected --entry USER SUBJECT' unless $action eq '--entry' && $user && $subject;
    my ($entry) =
        grep { $_->subject_orig eq $subject } $user->recent_entries( filtered_for => $user );
    croak 'Test entry was not saved' unless $entry;
    print encode_json( { security => $entry->security, mask => 0 + $entry->allowmask } ), "\n";
    exit 0;
}

my $password = LJ::rand_chars(16);
my $user;
until ($user) {
    $user = LJ::User->create_personal(
        user     => $prefix . LJ::rand_chars(4),
        email    => 'browser-test@example.com',
        password => $password,
        name     => 'Custom access browser test',
    );
}
$user->update_self( { status => 'A', statusvis => 'V' } );

my @bits = map { $user->create_trust_group( groupname => $_ ) }
    ( 'Book Club', 'Neighbors', 'Writing Group' );

print encode_json( { user => $user->user, password => $password, bits => \@bits } ), "\n";
