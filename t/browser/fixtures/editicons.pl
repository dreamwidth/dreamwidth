#!/usr/bin/perl
#
# t/browser/fixtures/editicons.pl
#
# Fixture for t/browser/editicons-rename.js: a throwaway account with one
# active icon and one suspended icon, both with keywords. Prints the details
# as JSON. With --delete USER, purges an account this script created.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use LJ::Userpic;

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

sub make_icon {
    my ( $file, $keywords ) = @_;
    open( my $fh, '<', "$ENV{LJHOME}/t/data/userpics/$file" ) or croak "Can't open $file: $!";
    binmode $fh;
    my $data = do { local $/; <$fh> };
    my $icon = LJ::Userpic->create( $u, data => \$data );
    $icon->set_keywords($keywords);
    return $icon;
}

my $active    = make_icon( 'good.png', 'browser active' );
my $suspended = make_icon( 'good.jpg', 'browser suspended' );
$u->suspend_userpic( $suspended->picid );

print encode_json(
    {
        user           => $u->user,
        password       => $password,
        active_picid   => $active->picid,
        disabled_picid => $suspended->picid,
    }
);
print "\n";
