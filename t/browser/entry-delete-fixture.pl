#!/usr/bin/perl
# Disposable fixture for native owned-entry delete-confirmation coverage.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json decode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;
use LJ::Test qw(temp_user);

my $user = temp_user();
$user->update_self( { status => 'A' } );
$user->set_password( my $password = 'entry-delete-' . LJ::rand_chars(12) );
my $target = $user->t_post_fake_entry(
    subject  => 'Browser delete target',
    body     => 'Browser delete target body',
    security => 'private'
);
my $other = $user->t_post_fake_entry(
    subject  => 'Browser delete unrelated',
    body     => 'Browser delete unrelated body',
    security => 'private'
);

sub state {
    LJ::Entry::reset_singletons();
    my $target_fresh = LJ::Entry->new( $user, ditemid => $target->ditemid );
    my $other_fresh  = LJ::Entry->new( $user, ditemid => $other->ditemid );
    return {
        target_valid => $target_fresh->valid ? JSON::true : JSON::false,
        other_valid  => $other_fresh->valid  ? JSON::true : JSON::false,
    };
}

$| = 1;
print encode_json(
    { user => $user->user, password => $password, id => $target->ditemid, state => state() } )
    . "\n";
while (<STDIN>) {
    my $command = decode_json($_);
    print encode_json( state() ) . "\n" if $command->{state};
}
