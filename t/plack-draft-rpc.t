#!/usr/bin/perl
#
# t/plack-draft-rpc.t
#
# The entry draft is a body plus properties, and one of the properties names the
# format the body is written in. The two must never be stored out of step: a
# save of other fields alone can't relabel a body it didn't save.
#
# Authors:
#     Mark Smith <mark@qq.is>
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
use Storable;
use JSON;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

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
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'draftRpc';

sub stored_editor {
    my $frozen = LJ::load_user( $u->user )->prop('draft_properties');
    return $frozen ? Storable::thaw($frozen)->{editor} : undef;
}

# A draft saved in the retired format, as it is before the form converts it.
$u->set_prop( entry_draft      => "old draft text" );
$u->set_prop( draft_properties => Storable::nfreeze( { editor => 'rte0', subject => 'Old' } ) );

test_psgi $app, sub {
    my $send = shift;
    my $save = sub {
        my $req = POST '/__rpc_draft', [@_];
        $req->header( Cookie => $cookie );
        $send->($req);
        LJ::start_request();
    };

    $save->( draftv => 2, saveSubject => 'New subject', saveEditor => 'rte1' );
    is( stored_editor(), 'rte0', 'saving fields without a body leaves the body\'s format alone' );

    $save->(
        saveDraft   => 'converted draft text',
        saveSubject => 'New subject',
        saveEditor  => 'rte1'
    );
    is( stored_editor(), 'rte1', 'saving a body with its format stores the new format' );
    is( LJ::load_user( $u->user )->draft_text, 'converted draft text', '...and the body' );

    $save->( draftv => 2, saveSubject => 'Later subject', saveEditor => 'markdown0' );
    is( stored_editor(), 'rte1', 'a later fields-only save still leaves it alone' );

    # A page opened before that change sends the format on its own, and the body
    # in a separate request; it gets the behavior it was written for.
    $save->( saveSubject => 'Legacy subject', saveEditor => 'markdown0' );
    is( stored_editor(), 'markdown0', 'an older page\'s fields-only save still sets the format' );
    $save->( saveDraft => 'legacy body' );
    is( stored_editor(), 'markdown0', '...and its body-only save leaves it' );

    # Casual HTML -> explicit HTML is done by the server, with the cleaner's rules.
    my $convert = sub {
        my ( $login, @form ) = @_;
        my $req = POST '/__rpc_entry_convert', [@form];
        $req->header( Cookie => $cookie ) if $login;
        my $res = $send->($req);
        return eval { decode_json( $res->content ) } || {};
    };

    my $body =
"one\ntwo http://example.com/x\n<table><tr><td>cell\nhttp://example.com/y</td></tr></table>";
    my $got = $convert->( 1, text => $body, from => 'html_casual1' );
    like(
        $got->{text},
        qr{^one<br />two <a href="http://example\.com/x">},
        'casual text gets explicit breaks and links'
    );
    like(
        $got->{text},
        qr{<td>cell<br /><a href="http://example\.com/y">},
        '...including inside a table cell, where a client-side pass would not look'
    );
    unlike( $convert->( 1, text => "a\nb", from => 'html_raw0' )->{text} // '',
        qr/./, 'only casual formats are converted' );
    ok( $convert->( 1, text => "a\nb", from => 'html_raw0' )->{alert}, '...others are refused' );
    my $res = sub {
        my ( $login, @form ) = @_;
        my $req = POST '/__rpc_entry_convert', [@form];
        $req->header( Cookie => $cookie ) if $login;
        return $send->($req);
    };
    is( $res->( 1, text => 'x' x ( LJ::CMAX_EVENT + 1 ), from => 'html_casual1' )->code,
        413, 'text longer than an entry can be is refused' );
    my $big = $res->( 1, text => 'x' x ( 3 * LJ::BMAX_EVENT + 2000 ), from => 'html_casual1' );
    is( $big->code, 413, 'a request body larger than any entry could produce is refused' );
    unlike( $big->content, qr/"text"/, '...without converting any of it' );
    is( $res->( 1, text => 'x' x LJ::CMAX_EVENT, from => 'html_casual1' )->code,
        200, 'text at the entry limit is accepted' );

    # Three-byte characters: 110,000 of them are 330,000 bytes but well within the
    # character limit, and 150,001 of them are over the byte limit.
    my $euro = "\xe2\x82\xac";
    is( $res->( 1, text => $euro x 110_000, from => 'html_casual1' )->code,
        200, 'multibyte text within both entry limits is accepted' );
    is( $res->( 1, text => $euro x 150_001, from => 'html_casual1' )->code,
        413, 'multibyte text over the byte limit is refused' );
    ok( !defined $convert->( 0, text => "a\nb", from => 'html_casual1' )->{text},
        'a visitor who is not logged in gets nothing' );
};

done_testing();
