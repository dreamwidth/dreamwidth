#!/usr/bin/perl
#
# t/auth-client-compat.t
#
# Verify the shipped jbackup client backs up a 2FA-enabled account using an API key.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use DW::API::Key;
use DW::Auth::TOTP;
use Plack::Test::Server;
use IPC::Open3;
use Symbol qw(gensym);
use GDBM_File;
plan skip_all => 'Unmodified jbackup requires Term::ReadKey'
    unless eval { require Term::ReadKey; 1 };

local $LJ::ADMIN_EMAIL = 'test@example.invalid';
my $u = temp_user();
$u->update_self( { status => 'A' } );
$u->set_password('client-password');
DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
my $key = DW::API::Key->new_for_user($u);

# Run the shipped backup CLI against a real local HTTP server and MFA account.
my $entry = $u->t_post_fake_entry(
    subject  => 'API backup regression',
    body     => 'Private backup body',
    security => 'private'
);
$entry->t_enter_comment( u => $u, body => 'Private backup comment' );
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless $app;
my $server = Plack::Test::Server->new($app);
my $backup = "$ENV{HOME}/" . $u->user . '.jbak';
BAIL_OUT('Refusing to overwrite an existing backup') if -e $backup;

# Seed a prior sync date: the legacy server's zero-date default is rejected by
# strict MySQL, independently of authentication. Exercise an incremental backup.
{
    my %seed;
    tie %seed, 'GDBM_File', $backup, &GDBM_NEWDB, 0600 or die $!;
    $seed{'event:lastsync'} = '2000-01-01 00:00:00';
    $seed{'event:lastgrab'} = '2000-01-01 00:00:00';
    untie %seed;
}
my $stderr = gensym;
my $pid    = open3(
    undef,                                 my $stdout,
    $stderr,                               $^X,
    "$ENV{LJHOME}/src/jbackup/jbackup.pl", '--sync',
    '--quiet',                             '--protocol=http',
    '--server=127.0.0.1',                  '--port=' . $server->port,
    '--user=' . $u->user,                  '--password=' . $key->hash
);
my ( $output, $errors );
{
    local $SIG{ALRM} = sub { kill 'KILL', $pid; die 'Backup client timeout' };
    alarm 60;
    $output = do { local $/; <$stdout> };
    $errors = do { local $/; <$stderr> };
    waitpid( $pid, 0 );
    alarm 0;
}
is( $?, 0, 'jbackup completes API-key entry and comment backup' ) or diag($errors);
ok( -f $backup, 'jbackup produces a backup file' );
SKIP: {
    skip 'Backup file was not produced', 2 unless -f $backup;
    my %saved;
    tie %saved, 'GDBM_File', $backup, &GDBM_READER, 0600 or die $!;
    ok(
        grep( /Private backup body/, values %saved ),
        'Backup contains authenticated private entry'
    ) or diag( $output, $errors );
    ok( grep( /Private backup comment/, values %saved ), 'Backup includes authenticated comments' );
    untie %saved;
    unlink $backup;
}
done_testing();
