# t/comment-account-age.t
#
# Test minimum account age settings and comment submission.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use Test::MockTime qw(set_fixed_time restore_time);
use HTTP::Request::Common;
use JSON::PP qw(decode_json);
use MIME::Entity;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost::Comment;
use DW::Pay;
use DW::Setting::NewAccountComments;
use LJ::Test qw(temp_user temp_comm with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'commentAgeTest';
local $LJ::T_ALLOW_EMAILPOST          = 1;

my $setting = 'DW::Setting::NewAccountComments';
my $field   = $setting->pkgkey . 'min_age';
my $owner   = temp_user();
my $poster  = temp_user();
my $openid  = temp_user( journaltype => 'I' );
$_->update_self( { status => 'A' } ) for ( $owner, $poster, $openid );
my $entry = $owner->t_post_fake_entry;

my $message = "Sorry, " . $owner->user . " doesn't allow comments from newly-created accounts";

sub save_age {
    my ( $journal, $value ) = @_;
    return LJ::Setting->save_all( $journal, { $field => $value }, [$setting] );
}

sub try_comment {
    my ( $entry, $poster ) = @_;
    my $error;
    my $comment = LJ::Comment->create(
        journal      => $entry->journal,
        ditemid      => $entry->ditemid,
        poster       => $poster,
        body         => 'Test comment ' . LJ::rand_chars(12),
        subject      => 'Test comment',
        parenttalkid => 0,
        props        => {},
        err_ref      => \$error,
    );
    return ( $comment, $error );
}

unless ( LJ::get_prop( user => 'opt_min_comment_age' ) ) {
    subtest 'comments work before the account age setting is installed' => sub {
        ok( !$setting->should_render($owner), 'unavailable setting cannot be configured' );
        my ( $comment, $error ) = try_comment( $entry, $poster );
        ok( $comment, 'new commenters are not blocked' ) or diag explain $error;
    };

    my $db = LJ::get_db_writer();
    $db->do(
        q{INSERT INTO userproplist (name, indexed, cldversion, multihomed, datatype, scope)
          VALUES ('opt_min_comment_age', '0', 4, '0', 'num', 'general')
          ON DUPLICATE KEY UPDATE name = name}
    ) or BAIL_OUT( $db->errstr );
}

subtest 'default and invalid settings' => sub {
    my ( $comment, $error ) = try_comment( $entry, $poster );
    ok( $comment, 'just-created account can comment by default' ) or diag explain $error;

    ok( !LJ::Setting->save_had_errors( save_age( $owner, '86400' ) ), 'save one day' );
    for my $value ( '', '0', '-1', '3600.0', '86401', '604800<script>' ) {
        ok( LJ::Setting->save_had_errors( save_age( $owner, $value ) ), "reject '$value'" );
        is( $owner->prop('opt_min_comment_age'), 86400, 'saved age unchanged' );
    }

    ok( !LJ::Setting->save_had_errors( save_age( $owner, 'none' ) ), 'restore no restriction' );
    ( $comment, $error ) = try_comment( $entry, $poster );
    ok( $comment, 'reset removes the restriction' ) or diag explain $error;
};

subtest 'account age is checked at submission for each threshold' => sub {
    my $created = $poster->timecreate;
    ok( $created, 'loaded the real account creation time' );

    for my $age ( 3600, 86400, 604800 ) {
        ok( !LJ::Setting->save_had_errors( save_age( $owner, $age ) ), "save $age seconds" );
        set_fixed_time( $created + $age - 1 );
        my ( $comment, $error ) = try_comment( $entry, $poster );
        ok( !$comment, "refused one second before $age" );
        is( $error->{msg}, $message, 'same refusal for every setting' );

        for my $elapsed ( $age, $age + 1 ) {
            set_fixed_time( $created + $elapsed );
            ( $comment, $error ) = try_comment( $entry, $poster );
            ok( $comment, "accepted at $elapsed seconds" ) or diag explain $error;
        }
        restore_time();
    }
};

subtest 'owners and maintainers are exempt; OpenID accounts are not' => sub {
    my ( $comment, $error ) = try_comment( $entry, $owner );
    ok( $comment, 'new journal owner can comment on their own entry' ) or diag explain $error;

    my $community = temp_comm();
    LJ::set_rel( $community, $poster, 'A' );
    my $community_entry = $poster->t_post_fake_entry(
        usejournal      => $community->user,
        usejournal_okay => 1,
    );
    save_age( $community, '604800' );
    ( $comment, $error ) = try_comment( $community_entry, $poster );
    ok( $comment, 'new maintainer can comment in their community' ) or diag explain $error;

    ( $comment, $error ) = try_comment( $entry, $openid );
    ok( !$comment, 'new OpenID account cannot comment' );
    is( $error->{msg}, $message, 'OpenID uses the same refusal' );
};

subtest 'web form, Quick Reply, XML-RPC, and email share the restriction' => sub {
    $owner->update_self( { opt_whocanreply => 'all' } );
    my $parent              = $entry->t_enter_comment( u => $owner );
    my $entry_comment_count = sub {
        return $owner->writer->selectrow_array(
            q{SELECT COUNT(*) FROM talk2 WHERE journalid=? AND nodetype='L' AND nodeid=?},
            undef, $owner->id, $entry->jitemid, );
    };
    my $before = $entry_comment_count->();

    with_fake_memcache {
        my $test   = Plack::Test->create($app);
        my $submit = sub {
            my ( $path, $viewer, %extra ) = @_;
            my $as = $viewer ? $viewer->user : 'nobody_exists';
            LJ::set_remote($viewer);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $form_auth = LJ::form_auth(1);
            LJ::set_remote(undef);
            return $test->request(
                POST "http://localhost/$path?as=$as",
                [
                    lj_form_auth => $form_auth,
                    chrp1        => LJ::Talk::generate_chrp1( $owner->id, $entry->ditemid ),
                    journal      => $owner->user,
                    itemid       => $entry->ditemid,
                    parenttalkid => 0,
                    usertype     => $viewer ? 'cookieuser' : 'anonymous',
                    cookieuser   => $viewer ? $viewer->user : '',
                    body         => 'Test web comment',
                    %extra,
                ],
            );
        };

        my $preview = $submit->( 'talkpost_do', $poster, submitpreview => 1 );
        unlike( $preview->decoded_content, qr/newly-created accounts/, 'preview is not a post' );
        my $web = $submit->( 'talkpost_do', $poster );
        like( $web->decoded_content, qr/\Q$message\E/, 'web submission shows the refusal' );
        my $quick = $submit->( '__rpc_addcomment', $poster );
        like( decode_json( $quick->content )->{error}, qr/\Q$message\E/, 'Quick Reply is refused' );

        my $password = 'test-comment-age-password';
        $poster->set_password($password);
        ok( DW::Pay::add_paid_time( $poster, 'paid', 0, 1 ), 'enable protocol comments' );
        my %args = (
            username     => $poster->user,
            password     => $password,
            journal      => $owner->user,
            ditemid      => $entry->ditemid,
            body         => 'Test protocol comment',
            subject      => 'Test protocol comment',
            parenttalkid => 0,
        );
        my $members = join '',
            map { "<member><name>$_</name><value><string>$args{$_}</string></value></member>" }
            sort keys %args;
        my $xml = $test->request(
            POST 'http://localhost/interface/xmlrpc',
            Content_Type => 'text/xml',
            Content      => '<methodCall><methodName>LJ.XMLRPC.addcomment</methodName>'
                . "<params><param><value><struct>$members</struct></value></param></params></methodCall>",
        );
        like( $xml->decoded_content, qr/newly-created accounts/, 'XML-RPC returns a fault' );

        my $email = DW::EmailPost::Comment->new(
            MIME::Entity->build(
                From => $poster->email_raw,
                To   => DW::EmailPost::Comment->replyto_address(
                    $poster, $owner, $entry->ditemid, $parent->dtalkid
                ),
                Subject => 'Test email reply',
                Data    => 'Test email reply body',
            ),
        );
        $email->{error_args} = { nomail => 1, nolog => 1 };
        my ( $success, $error ) = $email->process;
        ok( !$success, 'email reply is refused' );
        like( $error, qr/\Q$message\E/, 'email includes the refusal' );
        is( $entry_comment_count->(), $before, 'no blocked comment was written' );

        $submit->( 'talkpost_do', undef );
        is( $entry_comment_count->(), $before + 1, 'allowed anonymous comment has no age check' );
    };
};

done_testing();
