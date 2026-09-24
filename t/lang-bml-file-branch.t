#!/usr/bin/perl
# Native pages must not depend on translation keys scoped to a BML page: no
# *.bml.text file exists, so such a key can only resolve from a production
# database row and renders a missing-string banner on a fresh install. This
# renders the pages whose keys were relocated to native homes
# (views/manage/index.tt, views/manage/circle/index.tt, views/delcomment.tt,
# and the poll.error.accttype lookup in DW::Controller::Entry) and asserts
# real text with no banner, and that no '.bml.' key literal remains anywhere
# outside deadphrases.dat.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use File::Find;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Lang;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'requires a development server' unless $LJ::IS_DEV_SERVER;

subtest 'the from_files branch has no backing files left to read' => sub {
    my @text_files;
    find(
        {
            wanted => sub {
                push @text_files, $File::Find::name if -f $_ && /\.bml\.text$/;
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/htdocs",
        "$ENV{LJHOME}/ext",
    );
    is_deeply( \@text_files, [], 'no remaining *.bml.text files under htdocs/ or ext/' );
};

subtest 'the poll error key resolves to real text' => sub {
    my $text = LJ::Lang::ml('poll.error.accttype');
    ok( !LJ::Lang::is_missing_string($text), 'poll.error.accttype is not a missing-string banner' );
    is(
        $text,
        "Your account type doesn't allow you to create polls.",
        'poll.error.accttype resolves to its relocated English text'
    );
};

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

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    subtest '/manage/ renders real text for all four relocated keys' => sub {
        my $res = $cb->( GET '/manage/' );
        is( $res->code, 200, '/manage/ renders' );
        like( $res->content, qr/Edit Profile/,     'relocated profile title renders' );
        like( $res->content, qr/Account Settings/, 'relocated settings title renders' );
        like( $res->content, qr/Manage Tags/,      'relocated tags title renders' );
        like( $res->content, qr/Manage Circle/,    'relocated circle edit title renders' );
    };

    subtest '/manage/circle/ renders real text for its relocated key' => sub {
        my $res = $cb->( GET '/manage/circle/' );
        is( $res->code, 200, '/manage/circle/ renders' );
        like( $res->content, qr/Manage Circle/, 'relocated circle edit title (title3) renders' );
    };

    subtest 'a delcomment page renders real text for its relocated key' => sub {
        my $poster = temp_user();
        $poster->update_self( { status => 'A' } );
        my $entry   = $u->t_post_fake_entry;
        my $comment = $entry->t_enter_comment( u => $poster );

        my $res = $cb->( GET '/delcomment?journal=' . $u->user . '&id=' . $comment->dtalkid );
        is( $res->code, 200, '/delcomment renders' );
        like(
            $res->content,
            qr/Account Settings/,
            'relocated settings-link text renders in the changeoptions notice'
        );
    };
};

subtest 'no .bml. key literal remains in cgi-bin/views/ext outside deadphrases' => sub {
    my @offenders;
    find(
        {
            wanted => sub {
                return unless -f $_ && /\.(?:pm|tt)$/;
                return if $File::Find::name =~ m{/t/lang-bml-file-branch\.t$};
                return if $File::Find::name =~ m{/deadphrases(?:-local)?\.dat$};
                open my $fh, '<', $_ or return;
                while ( my $line = <$fh> ) {
                    next if $line =~ /^\s*#/;
                    push @offenders, "$File::Find::name:$.: $line"
                        if $line =~ /\.bml\.[a-zA-Z_]/;
                }
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/cgi-bin",
        "$ENV{LJHOME}/views",
        "$ENV{LJHOME}/ext",
    );
    is_deeply( \@offenders, [], 'no .bml. key literal remains outside deadphrases' )
        or diag(@offenders);
};

done_testing;
