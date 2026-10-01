# t/plack-entry-not-found.t
#
# Entry URLs must not reveal whether a hidden entry exists.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner    = temp_user();
my $stranger = temp_user();
my $public   = $owner->t_post_fake_entry( body => 'PUBLIC_MARKER' );
my $private  = $owner->t_post_fake_entry( body => 'PRIVATE_MARKER', security => 'private' );
$private->slug('hidden-slug');
$public->slug('public-slug');
my $date = substr( $private->eventtime_mysql, 0, 10 );
$date =~ s!-!/!g;

my $base    = 'http://localhost/users/' . $owner->user;
my $missing = ( $private->jitemid + 100 ) * 256 + 1;
my $wrong   = ( $public->jitemid << 8 ) + ( ( $public->anum + 1 ) % 256 );

# Comments on the public entry that $stranger can't see, keyed by why, as dtalkids.
my $commenter = temp_user();
my $suspended = temp_user();
my $shown     = $public->t_enter_comment( u => $commenter );
my $screened  = $public->t_enter_comment( u => $commenter, state => 'S' );
my $deleted   = $public->t_enter_comment( u => $commenter );
$deleted->delete;
my $by_suspended = $public->t_enter_comment( u => $suspended );
$suspended->update_self( { statusvis => 'S' } );    # set_statusvis would also write userlog
my $elsewhere      = $private->t_enter_comment( u => $owner );
my $anum           = $public->anum;
my %hidden_comment = (
    screened           => $screened->dtalkid,
    deleted            => $deleted->dtalkid,
    suspended          => $by_suspended->dtalkid,
    'on another entry' => $elsewhere->jtalkid * 256 + $anum,
    'wrong anum'       => $shown->jtalkid * 256 + ( $anum + 1 ) % 256,
);
my $missing_comment = ( $elsewhere->jtalkid + 100 ) * 256 + $anum;

my @hidden = (
    '/' . $private->ditemid . '.html',
    "/$missing.html",
    "/$wrong.html",
    "/$date/hidden-slug.html",
    "/$date/no-such-slug.html",
    '/1999/01/01/hidden-slug.html',
    '/1999/01/01/public-slug.html',
    '/' . $private->ditemid . '.html?mode=reply',
    "/$missing.html?mode=reply",
    map {
        ( '/' . $public->ditemid . ".html?replyto=$_", '/' . $public->ditemid . ".html?edit=$_" )
    } $missing_comment,
    sort values %hidden_comment,
);

# Per-request form tokens and the requested URL (in returnto links) legitimately
# differ, and Perl's hash order shuffles attributes, JSON keys and query args, so
# compare each line's tokens.
sub normalized {
    my ($body) = @_;
    $body =~ s!https?://localhost/[^"'\s]*!RETURNTO!g;
    $body =~ s/(name="lj_form_auth" value=")[^"]*/$1/g;
    return join "\n", map { join ' ', sort split /[\s,{}]+/ } split /\n/, $body;
}

# Test DBs do not install S2 styles; the stub marks where rendering would start.
my $renders = 0;
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::make_journal = sub { $renders++; return 'JOURNAL_RENDERED' };

    test_psgi $app, sub {
        my $cb = shift;

        for my $as ( 'nobody_exists', $stranger->user ) {
            my $reference;
            for my $path (@hidden) {
                my $url = $base . $path . ( $path =~ /\?/ ? '&' : '?' ) . "as=$as";
                my $res = $cb->( GET $url );
                is( $res->code, 404, "$as: $path is 404" );
                unlike(
                    $res->content,
                    qr/PRIVATE_MARKER|PUBLIC_MARKER|JOURNAL_RENDERED/,
                    "$as: $path shows no entry"
                );
                my $body = normalized( $res->content );
                $reference //= $body;
                is( $body, $reference, "$as: $path matches the other hidden URLs" );
            }
        }
        is( $renders, 0, 'hidden entries never reach the journal renderer' );

        # The adult interstitial would otherwise answer for any URL it can resolve.
        local $LJ::DISABLED{adult_content} = 0;
        $owner->set_prop( adult_content => 'explicit' );
        for my $path (@hidden) {
            my $res =
                $cb->( GET $base . $path . ( $path =~ /\?/ ? '&' : '?' ) . 'as=nobody_exists' );
            is( $res->code, 404, "adult journal: $path is 404, not the interstitial" );
        }
        $owner->set_prop( adult_content => 'none' );

        for (
            [ $owner,    '/' . $private->ditemid . '.html' ],
            [ $owner,    "/$date/hidden-slug.html" ],
            [ $owner,    '/' . $public->ditemid . '.html?replyto=' . $screened->dtalkid ],
            [ $stranger, '/' . $public->ditemid . '.html?replyto=' . $shown->dtalkid ],
            )
        {
            my ( $viewer, $path ) = @$_;
            my $res =
                $cb->( GET $base . $path . ( $path =~ /\?/ ? '&' : '?' ) . 'as=' . $viewer->user );
            is( $res->code, 200, "$viewer->{user}: $path renders" );
            like( $res->content, qr/JOURNAL_RENDERED/,
                "$viewer->{user}: $path reaches the renderer" );
        }

        # Other pages that take a comment or entry id from the URL.
        my $as      = 'as=' . $stranger->user;
        my $journal = $owner->user;
        my %by_id   = (
            "/go?redir_type=threadroot&journal=$journal&talkid=" => $missing_comment,
            "/talkscreen?mode=unscreen&journal=$journal&talkid=" => $missing_comment,
            "/delcomment?journal=$journal&id="                   => $missing_comment,
            "/manage/tracking/comments?journal=$journal&talkid=" => $missing_comment,
            "/manage/tracking/entry?journal=$journal&itemid="    => $missing,
        );
        local $LJ::DISABLED{esn} = 0;
        for my $page ( sort keys %by_id ) {
            my $is_entry = $page =~ /itemid=$/;
            my $get      = sub { $cb->( GET "http://localhost$page$_[0]&$as" ) };
            my $expected = $get->( $by_id{$page} );
            my $ref      = normalized( $expected->content );
            my @ids      = $is_entry ? ( $private->ditemid, $wrong ) : sort values %hidden_comment;
            for my $id (@ids) {
                my $res = $get->($id);
                is( $res->code, $expected->code, "$page$id: same status as missing" );
                is( normalized( $res->content ), $ref, "$page$id: same body as missing" );
            }
            my $visible = $get->( $is_entry ? $public->ditemid : $shown->dtalkid );
            isnt( normalized( $visible->content ), $ref, "$page: a visible id differs" );
        }
    };

    # The thread view falls back to the whole page for a missing thread id.
    for my $viewer ( undef, $stranger ) {
        my $load = sub {
            [
                LJ::Talk::load_comments(
                    $owner, $viewer, 'L', $public->jitemid, { thread => $_[0] >> 8 }
                )
            ];
        };
        my $ref = $load->($missing_comment);
        for my $why ( grep { $_ ne 'wrong anum' } sort keys %hidden_comment ) {
            is_deeply( $load->( $hidden_comment{$why} ), $ref, "thread: $why is like missing" );
        }
    }

    # Replying to or editing a comment through talkpost_do.
    for my $viewer ( undef, $stranger ) {
        my $reply_errors = sub {
            my @errors;
            LJ::Talk::Post::prepare_and_validate_comment(
                { replyto => $_[0] >> 8, subject => 'subject', body => 'body' },
                $viewer, $public, 0, \@errors );
            return \@errors;
        };
        my $ref = $reply_errors->($missing_comment);
        for my $why ( grep { $_ ne 'wrong anum' } sort keys %hidden_comment ) {
            is_deeply( $reply_errors->( $hidden_comment{$why} ),
                $ref, "reply: $why is like missing" );
        }
    }
    LJ::set_remote($stranger);
    my $edit_error = sub {
        ( LJ::Talk::Post::edit_comment( { entry => $public, editid => $_[0] } ) )[1];
    };
    for my $why ( sort keys %hidden_comment ) {
        is(
            $edit_error->( $hidden_comment{$why} ),
            $edit_error->($missing_comment),
            "edit: $why is like missing"
        );
    }
};

done_testing();
