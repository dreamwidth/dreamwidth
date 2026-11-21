# t/export-posted-comments.t
#
# Test downloads of comments authored by the signed-in user.
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
use DW::Request::Standard;
use HTTP::Request::Common;
use LJ::Protocol;
use LJ::Test qw( temp_user );
use Plack::Test;

my $owner   = temp_user();
my $author  = temp_user();
my $entry   = $owner->t_post_fake_entry( subject => 'entry-only-subject' );
my $parent  = $entry->t_enter_comment( u => $owner, body => 'other-author-body' );
my $comment = $parent->t_reply(
    u       => $author,
    subject => 'own-subject',
    body    => qq{own "quoted", <reply> & text\nnext line},
);
my $screened = $entry->t_enter_comment( u => $author, body => 'own-screened-body' );
LJ::Talk::screen_comment( $owner, $entry->jitemid, $screened->jtalkid );
my $deleted = $entry->t_enter_comment( u => $author, body => 'deleted-body' );
$deleted->delete;
my $restricted = $owner->t_post_fake_entry( security => 'friends' );
ok( $owner->add_edge( $author, trust => { nonotify => 1 } ), 'grant access for posting' );
ok( $restricted->visible_to($author), 'restricted entry is visible before revocation' );
$restricted->t_enter_comment( u => $author, state => 'S', body => 'revoked-body' );
ok( $owner->remove_edge( $author, trust => { nonotify => 1 } ), 'revoke access after posting' );
ok( !$restricted->visible_to($author), 'restricted entry is no longer visible' );

DW::Request->reset;
DW::Request::Standard->new( GET 'http://www.dw.test/' );
my $error;
my $session =
    LJ::Protocol::do_request( 'sessiongenerate',
    { username => $author->user, expiration => 'short' },
    \$error, { noauth => 1 } );
DW::Request->reset;
my $cookie  = 'ljsession=' . ( $session->{ljsession} or die "sessiongenerate: $error" );
my $app     = do "$ENV{LJHOME}/app.psgi" or die $@;
my $test    = Plack::Test->create($app);
my $page    = $test->request( GET 'http://www.dw.test/export', Cookie => $cookie );
my ($token) = $page->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
ok( $token, 'export page provides form authorization' ) or diag( $page->status_line );

my ( $month, $year ) = ( gmtime( $comment->unixtime ) )[ 4, 5 ];
my $download = sub {
    my ( $format, %extra ) = @_;
    return $test->request(
        POST 'http://www.dw.test/export_posted_comments',
        Cookie  => $cookie,
        Content => {
            lj_form_auth => $token,
            format       => $format,
            year         => $year + 1900,
            month        => $month + 1,
            %extra
        },
    );
};

my $xml      = $download->('xml');
my $xml_body = $xml->header('Content-Disposition') ? $xml->content : '';
ok( $xml->is_success, 'XML download succeeds' ) or diag( $xml->status_line );
like( $xml->header('Content-Disposition'), qr/attachment;.*\.xml/, 'XML is an attachment' );
like( $xml_body, qr{<subject>own-subject</subject>}, 'exports my subject' );
like(
    $xml_body,
    qr{own &quot;quoted&quot;, &lt;reply&gt; &amp; text\nnext line},
    'exports my body with XML escaping'
);
like( $xml_body, qr{<journal>\Q${\ $owner->user }\E</journal>}, 'includes the journal' );
like(
    $xml_body,
    qr{<permalink>[^<]+\?thread=\Q${\ $comment->dtalkid }\E\b},
    'includes the direct comment link'
);
like(
    $xml_body,
    qr{<datetime>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|\+00:00)</datetime>},
    'includes the timestamp in UTC'
);
like( $xml_body, qr/own-screened-body/, 'includes my screened comment when I can see it' );
unlike(
    $xml_body,
    qr/entry-only-subject|other-author-body|revoked-body|deleted-body/,
    'excludes other authors, entry content, revoked access and deleted comments'
);
my @comments = $xml_body =~ /<comment>/g;
is( scalar @comments, 2, 'only the two eligible comments are exported' );

my $csv      = $download->('csv');
my $csv_body = $csv->header('Content-Disposition') ? $csv->content : '';
like( $csv->header('Content-Disposition'), qr/attachment;.*\.csv/, 'CSV is an attachment' );
like( $csv_body, qr/^journal,permalink,datetime,subject,body,icon_keyword\n/, 'CSV has a header' );
like(
    $csv_body,
    qr/"own ""quoted"", <reply> & text\nnext line"/,
    'CSV quotes commas, quotes and line breaks'
);
my $empty = $download->( 'xml', year => 2000 );
like(
    $empty->content,
    qr{\A<\?xml[^\n]+\n<comments>\n</comments>\n\z},
    'empty export outside the selected month'
);
ok( !$download->( 'xml', month => 13 )->header('Content-Disposition'), 'rejects invalid dates' );
ok( !$download->( 'xml', lj_form_auth => '' )->header('Content-Disposition'),
    'rejects missing form authorization' );

done_testing;
