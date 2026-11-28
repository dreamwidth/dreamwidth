# t/console-sourceip.t
#
# Test privileged account-creation IP lookup through the console.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use LJ::Console;
use LJ::Test qw(temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;
my $operator = temp_user();
my $target   = temp_user();
my $other    = temp_user();
my $run      = sub { LJ::Console->run_commands_text(shift) };
my $lookup   = 'sourceip ' . $target->user;
LJ::set_remote(undef);
is( $run->($lookup), 'error: You must be logged in to run this command.', 'requires login' );
LJ::set_remote($operator);
is(
    $run->($lookup),
    'error: You are not authorized to run this command.',
    'requires userlog privilege'
);
$operator->grant_priv( 'canview', 'email' );
is(
    $run->($lookup),
    'error: You are not authorized to run this command.',
    'unrelated canview is insufficient'
);
$operator->grant_priv( 'canview', 'userlog' );

for my $u ( $target, $other ) {
    $u->do( 'DELETE FROM userlog WHERE userid=?', undef, $u->id );
}
my $add = sub {
    my ( $u, $time, $action, $ip ) = @_;
    $u->do( 'INSERT INTO userlog (userid,logtime,action,ip) VALUES (?,?,?,?)',
        undef, $u->id, $time, $action, $ip );
    die $u->errstr if $u->err;
};
$add->( $other,  500, 'account_create',  '2001:db8::3537' );
$add->( $target, 500, 'password_change', '192.0.2.99' );
is(
    $run->($lookup),
    'error: No account creation IP address recorded for ' . $target->user . '.',
    'other users and other actions are excluded'
);
$add->( $target, 2000, 'account_create', '192.0.2.22' );
$add->( $target, 1000, 'account_create', '192.0.2.11' );
my $expected = 'info: Account Created IP address for ' . $target->user . ': 192.0.2.11';
is( $run->($lookup), $expected, 'oldest account creation IP is returned' );
is(
    $run->( 'sourceip ' . $other->user ),
    'info: Account Created IP address for ' . $other->user . ': 2001:db8::3537',
    'IPv6 is preserved'
);
is(
    $run->( $lookup . "\nsourceip " . $other->user ),
    $expected . 'info: Account Created IP address for ' . $other->user . ': 2001:db8::3537',
    'existing console batching runs both lookups'
);
is(
    $run->('sourceip'),
    'error: This command takes exactly one argument. Consult the reference.',
    'missing argument'
);
is(
    $run->( $lookup . ' extra' ),
    'error: This command takes exactly one argument. Consult the reference.',
    'extra argument'
);
is( $run->('sourceip invalid!user'), 'error: Invalid user.', 'invalid account' );
$target->update_self( { statusvis => 'X' } );
is(
    $run->($lookup),
    'error: No user log is available for a purged account.',
    'purged account matches userlog restriction'
);
$target->update_self( { statusvis => 'V' } );
$operator->revoke_priv( 'canview', 'userlog' );
$operator->grant_priv( 'canview', '*' );
is( $run->($lookup), $expected, 'wildcard canview grants access' );
$target->do( "UPDATE userlog SET ip=NULL WHERE userid=? AND action='account_create'",
    undef, $target->id );
is(
    $run->($lookup),
    'error: No account creation IP address recorded for ' . $target->user . '.',
    'missing IP is explicit'
);
LJ::set_remote(undef);
done_testing;
