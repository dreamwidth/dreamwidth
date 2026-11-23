#!/usr/bin/perl
#
# t/plack-entry-preview.t
#
# The native entry preview renders polls and embeds without saving anything.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use LJ::Session;
plan skip_all => 'Preview integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u = temp_user();
$u->update_self( { status => 'A' } );
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

my @spam_checks;
local $LJ::HOOKS{spam_check}   = [ sub { push @spam_checks, [@_]; return; } ];
local $LJ::T_HAS_ALL_CAPS      = 1;
local $LJ::EMBED_MODULE_DOMAIN = 'embed.localhost';
$u->set_prop( stylesys                    => 1 );
$u->set_prop( use_journalstyle_entry_page => 'N' );

sub count_rows {
    my ( $table, $column ) = @_;
    my ($count) =
        $u->selectrow_array( "SELECT COUNT(*) FROM $table WHERE $column=?", undef, $u->id );
    return $count;
}

my %before = (
    entries => count_rows( log2         => 'journalid' ),
    polls   => count_rows( poll2        => 'journalid' ),
    embeds  => count_rows( embedcontent => 'userid' ),
);

test_psgi $app, sub {
    my $send = shift;
    my $event =
          '<poll name="Preview poll" isanon="no" whovote="all" whoview="all">'
        . '<poll-question type="radio">Preview question'
        . '<poll-item>Only option</poll-item></poll-question></poll>'
        . '<iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe>';
    my $res = $send->(
        POST 'http://localhost/entry/preview',
        [
            usejournal     => $u->user,
            security       => 'public',
            subject        => 'Native pipeline subject',
            event          => $event,
            editor         => 'html_raw0',
            entrytime_date => '2020-01-02',
            entrytime_time => '03:04',
            trust_datetime => 1
        ],
        Cookie => $cookie
    );
    is( $res->code, 200, 'poll and embed preview renders' );
    like( $res->content, qr/<input type=["']radio["']/, 'preview renders the poll control' );
    like( $res->content, qr/lj_embedcontent-wrapper/,   'preview expands the trusted embed' );
    unlike(
        $res->content,
        qr/<poll-placeholder>|<(?:lj-)?poll\b/i,
        'preview leaves no raw poll markup or placeholder'
    );
};

is( count_rows( log2  => 'journalid' ), $before{entries}, 'preview creates no entry' );
is( count_rows( poll2 => 'journalid' ), $before{polls},   'preview persists no poll' );
is( count_rows( embedcontent => 'userid' ),
    $before{embeds}, 'preview persists no embed outside preview storage' );

done_testing;
