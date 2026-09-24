#!/usr/bin/perl
# Disposable fixture for modern entry draft and preview characterization.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $user     = temp_user();
my $password = 'entry-draft-browser-' . LJ::rand_chars(12);
$user->set_password($password);
$user->update_self( { status => 'A' } );
$| = 1;
print encode_json( { user => $user->user, password => $password } ) . "\n";
while (<STDIN>) {
    next unless /^entry_count\s*$/;
    my ($count) =
        $user->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $user->id );
    print encode_json( { entry_count => 0 + $count } ) . "\n";
}
