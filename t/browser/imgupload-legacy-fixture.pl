#!/usr/bin/perl
# Disposable fixture for legacy image insertion browser coverage.
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

sub state {
    my ($count) =
        $user->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $user->id );
    return { entries => $count };
}

$| = 1;
print encode_json( { user => $user->user, password => $password, state => state() } ) . "\n";
while (<STDIN>) {
    my $command = decode_json($_);
    print encode_json( state() ) . "\n" if $command->{state};
}
