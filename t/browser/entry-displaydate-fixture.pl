#!/usr/bin/perl
# Disposable browser fixture for entry display-date controls.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
my $u        = temp_user();
my $password = 'entry-date-browser-' . LJ::rand_chars(12);
$u->set_password($password);
$u->update_self( { status => 'A' } );

# Display Date is opt-in in the entry form; seed the same per-user panel setting
# the real entry-options UI persists so the browser proof exercises visible controls.
$u->entryform_panels_visibility( { displaydate => 1 } );
my %res;
LJ::do_request(
    {
        mode     => 'postevent',
        ver      => $LJ::PROTOCOL_VER,
        user     => $u->user,
        subject  => 'Date fixture',
        event    => 'Date body',
        year     => 2020,
        mon      => 1,
        day      => 2,
        hour     => 3,
        min      => 4,
        security => 'private'
    },
    \%res,
    { noauth => 1, nomod => 1 }
);
die "post failed: $res{errmsg}" unless $res{success} eq 'OK';
$| = 1;
print encode_json(
    { user => $u->user, password => $password, ditemid => ( ( $res{itemid} << 8 ) + $res{anum} ) } )
    . "\n";
<STDIN>;
