#!/usr/bin/perl
# Disposable credentials for the settings browser acceptance test.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";
use JSON qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_comm temp_user);

my $password = 'settings-browser-fixture';
my $user     = temp_user();
my $comm     = temp_comm();
$user->set_password($password);
$comm->set_password($password);
LJ::set_rel( $comm, $user, 'A' );
my $active = $user->subscribe( event => 'JournalNewEntry', journalid => 0, method => 'Inbox' );
my $inactive =
    $user->subscribe( event => 'AddedToCircle', journal => $user, method => 'Inbox', arg1 => 42 );
$inactive->_deactivate;
print encode_json(
    {
        user           => $user->user,
        community      => $comm->user,
        password       => $password,
        community_type => $comm->journaltype,
        maintainer     => LJ::check_rel( $comm, $user, 'A' ) ? 1 : 0,
        active_id      => $active->id,
        inactive_id    => $inactive->id
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
            xpost_disable_comments =>
                LJ::load_userid( $user->id, 1 )->prop('opt_xpost_disable_comments'),
            xpost_footer => LJ::load_userid( $user->id, 1 )->prop('crosspost_footer_text'),
        }
    ) . "\n";
    <>;    # Browser closes stdin after it has consumed verification.
}
