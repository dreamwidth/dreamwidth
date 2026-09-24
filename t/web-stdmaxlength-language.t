#!/usr/bin/perl
# Native request-language coverage for LJ::std_max_length.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use HTTP::Request::Common qw(GET);
use Plack::Test;
use LJ::Lang;
use LJ::Test qw(temp_user);
use LJ::Web;
use LJ::Widget::JournalTitles;

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        }
    );
}
sub lang { request(); LJ::Lang::set_request_context( lang => $_[0] ) }
subtest 'raw request language preserves existing maxlength mapping and isolation' => sub {
    lang('en');
    is( LJ::std_max_length(), 80, 'en remains 80' );
    lang('ru');
    is( LJ::std_max_length(), 100, 'listed ru remains 100' );
    lang('fr');
    is( LJ::std_max_length(), 80, 'unlisted language remains 80' );
    lang('debug');
    is( LJ::std_max_length(), 80, 'debug remains raw non-listed 80' );
    local $LJ::DEFAULT_LANG = 'ru';
    DW::Request->reset;
    is( LJ::std_max_length(), 80, 'no request remains 80 even when application default is listed' );
};
subtest 'actual JournalTitles save uses request maxlength boundary with fresh persistence' => sub {
    my $u = temp_user();
    $u->update_self( { status => 'A' } );
    my $value = 'x' x 105;
    no warnings 'redefine';
    local *LJ::Widget::JournalTitles::get_effective_remote = sub { $u };
    lang('en');
    LJ::Widget::JournalTitles->handle_post(
        { which_title => 'journaltitle', title_value => $value } );
    my $fresh = LJ::load_user( $u->user, 'force' );
    is( length( $fresh->prop('journaltitle') ), 80, 'English save stores 80 characters' );
    lang('ru');
    LJ::Widget::JournalTitles->handle_post(
        { which_title => 'journaltitle', title_value => $value } );
    $fresh = LJ::load_user( $u->user, 'force' );
    is( length( $fresh->prop('journaltitle') ), 100, 'listed-language save stores 100 characters' );
};

# LJ::entry_form (deleted by F2, formerly the caller exercised here) is gone;
# the native /entry/new page carries the same LJ::std_max_length-driven
# maxlength on its "current_music"/"current_location" fields (the module-
# currents panel, views/entry/module-currents.tt:51,62 -- limits.current_length
# is LJ::std_max_length, cgi-bin/DW/Controller/Entry.pm:741; the subject
# field's own maxlength, views/entry/form.tt:184, is the fixed
# LJ::CMAX_SUBJECT constant, not language-dependent, so it isn't part of this
# characterization). RequestWrapper.pm sets the per-request language from
# $LJ::DEFAULT_LANG for every real request, so drive it the same way
# 'no request uses configured native default fallback' above does, per
# request, rather than calling LJ::Lang::set_request_context directly (a
# real test_psgi request re-establishes that context itself on entry).
subtest 'actual entry form renders the native maxlength on current fields' => sub {
    my $u = temp_user();
    $u->update_self( { status => 'A' } );
    my $session = LJ::Session->create( $u, nolog => 1 );
    my $cookie =
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;

    my $app = do "$ENV{LJHOME}/app.psgi";
    die $@ unless ref $app eq 'CODE';

    for my $case ( [ 'en', 80 ], [ 'ru', 100 ] ) {
        my ( $case_lang, $expect ) = @$case;
        local $LJ::DEFAULT_LANG = $case_lang;
        test_psgi $app, sub {
            my $cb  = shift;
            my $req = GET 'http://localhost/entry/new';
            $req->header( Cookie => $cookie );
            my $res = $cb->($req);
            is( $res->code, 200, "/entry/new renders under '$case_lang'" );
            like(
                $res->content,
qr/name="current_location"[^>]*maxlength="$expect"|maxlength="$expect"[^>]*name="current_location"/,
                "entry form current_location reflects '$case_lang' maxlength ($expect)"
            );
            like(
                $res->content,
qr/name="current_music"[^>]*maxlength="$expect"|maxlength="$expect"[^>]*name="current_music"/,
                "entry form current_music reflects '$case_lang' maxlength ($expect)"
            );
        };
    }
};
done_testing;
