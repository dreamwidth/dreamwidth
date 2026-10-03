#!/usr/bin/perl
# Disposable credentials for the settings browser acceptance test.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";
use JSON qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $password = 'settings-browser-fixture';
my $user     = temp_user();
$user->set_password($password);
my $active = $user->subscribe( event => 'JournalNewEntry', journalid => 0, method => 'Inbox' );
my $inactive =
    $user->subscribe( event => 'AddedToCircle', journal => $user, method => 'Inbox', arg1 => 42 );
$inactive->_deactivate;
print encode_json(
    {
        user        => $user->user,
        password    => $password,
        active_id   => $active->id,
        inactive_id => $inactive->id
    }
) . "\n";
$| = 1;
my $command = <>;    # Keep LJ::Test fixtures alive until the browser closes stdin.

if ( $command && $command =~ /verify/ ) {
    my @subs = LJ::load_userid( $user->id, 1 )->subscriptions;
    my %ids  = map { $_->id => 1 } @subs;
    print encode_json(
        {
            active   => $ids{ $active->id }   ? 1 : 0,
            inactive => $ids{ $inactive->id } ? 1 : 0,
            usermsg => LJ::load_userid( $user->id, 1 )->prop('opt_usermsg'),
        }
    ) . "\n";
    <>;              # Browser closes stdin after it has consumed verification.
}
