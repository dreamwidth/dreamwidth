#!/usr/bin/perl
# Disposable maintainer editor browser fixture.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON::MaybeXS qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);
my $manager = temp_user();
my $poster  = temp_user();
my $comm    = temp_comm();
$_->update_self( { status => 'A' } ) for $manager, $poster;
$manager->set_password( my $pw = 'maintainer-' . LJ::rand_chars(12) );
LJ::set_rel( $comm, $manager, 'A' );
my $entry = $poster->t_post_fake_comm_entry( $comm, body => 'foreign body' );
$| = 1;
print encode_json(
    { user => $manager->user, password => $pw, comm => $comm->user, id => $entry->ditemid } )
    . "\n";
<STDIN>;
