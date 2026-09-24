#!/usr/bin/perl
# Disposable native image insertion fixture.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json decode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;
use LJ::Test qw(temp_user);
my $u = temp_user();
$u->update_self( { status => "A" } );
$u->set_password( my $p = "image-" . LJ::rand_chars(12) );
my $e = $u->t_post_fake_entry(
    subject  => "Image edit",
    body     => "Image edit body",
    security => "private"
);

sub state {
    LJ::Entry::reset_singletons();
    my $x = LJ::Entry->new( $u, ditemid => $e->ditemid );
    my ($n) = $u->selectrow_array( "SELECT COUNT(*) FROM log2 WHERE journalid=?", undef, $u->id );
    return { entries => $n, subject => $x->subject_raw, body => $x->event_raw };
}
$| = 1;
print encode_json( { user => $u->user, password => $p, id => $e->ditemid, %{ state() } } ) . "\n";
while (<STDIN>) { my $c = decode_json($_); print encode_json( state() ) . "\n" if $c->{state}; }
