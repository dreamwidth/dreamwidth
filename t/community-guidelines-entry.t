# t/community-guidelines-entry.t
#
# Posting guidelines accept entry ids and URLs belonging to the community.
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
use LJ::Test qw(temp_user temp_comm);
use DW::Setting::CommunityGuidelinesEntry;

my $admin = temp_user();
my $comm  = temp_comm();
my $other = temp_comm();
LJ::set_rel( $comm,  $admin, 'A' );
LJ::set_rel( $other, $admin, 'A' );

my $entry = $admin->t_post_fake_comm_entry( $comm, body => 'short guidelines' );
my $long  = $admin->t_post_fake_comm_entry( $comm, body => 'long guidelines' );
my $foreign = $admin->t_post_fake_comm_entry($other);
$entry->slug('posting-guidelines');
$long->slug( 'a' x 100 );
$foreign->slug('other-guidelines');
my $id = $entry->ditemid;

subtest 'accepted entry references' => sub {
    for my $input ( $id, $comm->journal_base . "/$id.html", $entry->url, $long->url, ) {
        my $expected = $input eq $long->url ? $long->ditemid : $id;
        is( $comm->posting_guidelines_entry($input), $expected, "accept $input" );
        is( $comm->posting_guidelines_entry,         $expected, 'store the entry id' );
        my $saved = $comm->get_posting_guidelines_entry;
        is( $saved && $saved->ditemid, $expected, 'resolve stored entry' );
    }
};

subtest 'invalid references preserve the saved entry' => sub {
    $comm->posting_guidelines_entry($id);
    my $wrong_date = $entry->url;
    $wrong_date =~ s!/\d{4}/\d{2}/\d{2}/!/1900/01/01/!;
    my $missing = $entry->url;
    $missing =~ s!posting-guidelines\.html$!missing-guidelines.html!;
    for my $input ( $wrong_date, $missing, $foreign->url, 'not an entry' ) {
        ok( !$comm->posting_guidelines_entry($input), "reject $input" );
        is( $comm->posting_guidelines_entry, $id, 'keep previous entry' );
    }
};

subtest 'settings save and redisplay' => sub {
    my $class = 'DW::Setting::CommunityGuidelinesEntry';
    my $key   = $class->pkgkey . 'communityguidelinesentry';
    $comm->posting_guidelines_location('E');
    my $saved = eval { $class->save( $comm, { $key => $long->url } ); 1 };
    ok( $saved, 'save a long slug URL through the setting' );
    is( $comm->posting_guidelines_entry, $long->ditemid, 'setting stores its entry id' );
    my $html = $class->option($comm);
    like( $html, qr/\Q@{[$long->url]}\E/, 'redisplay the saved slug URL' );
    my ($limit) = $html =~ /maxlength=['"]?(\d+)/;
    cmp_ok( $limit, '>=', length( $long->url ), 'input fits the full slug URL' );
};

subtest 'clearing' => sub {
    ok( $comm->posting_guidelines_entry(''),  'clear with an empty value' );
    ok( !$comm->posting_guidelines_entry,     'stored value is empty' );
    ok( !$comm->get_posting_guidelines_entry, 'no guidelines entry remains' );
};

done_testing;
