#!/usr/bin/perl
# Verify Protocol request notes are native and request-local.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Standard;
use LJ::Protocol;
use LJ::Test qw(temp_comm temp_user);

sub request_context {
    my ($label) = @_;
    DW::Request->reset;
    return DW::Request::Standard->new( HTTP::Request->new( GET => "/protocol-note-$label" ) );
}

my $user = temp_user();
$user->update_self( { status => 'A' } );
my $comm = temp_comm();
LJ::set_rel( $comm, $user, 'P' );
ok( $user->can_post_to($comm), 'disposable user can use alternate community' );

my $login = sub {
    my ($clientversion) = @_;
    my $err = '';
    return LJ::Protocol::login(
        { username => $user->user, ver => 1, clientversion => $clientversion },
        \$err, { noauth => 1, u => $user },
    );
};

my $a = request_context('a');
ok( $login->('ClientA/1.0'), 'actual login succeeds in request A' );
is( $a->note('clientver'), 'ClientA/1.0', 'valid client version is stored on request A' );
my $b = request_context('b');
is( $b->note('clientver'), undef, 'request B starts without request A client version' );
ok( $login->('ClientB/2.0'), 'actual login succeeds in request B' );
is( $b->note('clientver'), 'ClientB/2.0', 'request B stores its own client version' );
is( $a->note('clientver'), 'ClientA/1.0', 'request B cannot overwrite request A client version' );
$login->('invalid client version');
is( $b->note('clientver'), 'ClientB/2.0', 'invalid client version leaves existing note unchanged' );

my $alt = sub {
    my ($flags) = @_;
    my $err = '';
    return LJ::Protocol::check_altusage( { usejournal => $comm->user }, \$err, $flags );
};
my $alt_a = request_context('alt-a');
ok( $alt->( { u => $user } ), 'actual alternate-journal check succeeds in request A' );
is( $alt_a->note('journalid'), $comm->id, 'alternate journal ID is stored on request A' );
my $alt_b = request_context('alt-b');
is( $alt_b->note('journalid'), undef, 'request B starts without request A alternate journal ID' );
$alt_b->note( journalid => 999_999 );
ok( $alt->( { u => $user } ), 'alternate-journal check succeeds with existing note' );
is( $alt_b->note('journalid'), 999_999, 'truthy existing journal note is preserved' );

DW::Request->reset;
my $no_request_error = eval {
    $login->('NoRequest/1.0');
    $alt->( { u => $user } );
    1;
};
ok( $no_request_error, 'login and alternate-journal note paths are no-ops without a request' );
is( DW::Request->get, undef, 'no-request path does not create a request object' );

done_testing;
