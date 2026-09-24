#!/usr/bin/perl
# Admin FAQ native template bookkeeping regression.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use DW::Controller::Admin::FAQ;

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/admin/faq/readcat',
            QUERY_STRING      => 'faqcat=general',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        },
    );
}
{

    package AdminFaqModtime::Db;
    sub prepare { bless {}, 'AdminFaqModtime::Sth' }

    package AdminFaqModtime::Sth;
    sub execute        { 1 }
    sub fetchrow_array { 'General' }

    package AdminFaqModtime::User;
    sub user         { 'example' }
    sub journal_base { '/example/' }

    package AdminFaqModtime::Faq;
    sub new { bless { unixmodtime => time + 600 }, shift }
    sub sortorder     { 1 }
    sub unixmodtime   { $_[0]{unixmodtime} }
    sub has_summary   { 1 }
    sub question_html { 'Question' }
    sub summary_html  { 'Summary' }
    sub answer_html   { 'Answer' }
}

subtest
    'actual admin readcat handler preserves native rendering without BML modification bookkeeping'
    => sub {
    my $r = request();
    LJ::Lang::set_request_context(
        lang   => 'fr',
        getter => sub { return "native:$_[1]" },
    );
    my $rendered = '';
    my $faq      = AdminFaqModtime::Faq->new;
    no warnings 'redefine';
    local *DW::Controller::Admin::FAQ::controller  = sub { return ( 1, { r => $r } ) };
    local *DW::Controller::Admin::FAQ::_page_setup = sub {
        return {
            display_faq => sub { $_[0] }
        };
    };
    local *LJ::get_db_writer = sub { bless {}, 'AdminFaqModtime::Db' };
    local *LJ::Lang::get_dom       = sub { return { dmid   => 1 } };
    local *LJ::Lang::get_root_lang = sub { return { lncode => 'en' } };
    local *LJ::Faq::load_all       = sub { return ($faq) };
    local *LJ::Faq::render_in_place   = sub { return 1 };
    local *LJ::load_user              = sub { bless {}, 'AdminFaqModtime::User' };
    local *LJ::CleanHTML::clean_event = sub { return };
    local *DW::Template::render_string = sub {
        my ( $class, $body ) = @_;
        $rendered = $body;
        return $body;
    };

    is( DW::Controller::Admin::FAQ::read_handler(),
        $rendered, 'public admin category handler renders the actual native template' );
    like(
        $rendered,
        qr/<h2>General<\/h2>.*Question.*Answer/s,
        'actual template renders real FAQ content, not a blank or failed render'
    );

    is( $r->header_out('Last-Modified'),
        undef,
        'handler does not invent a Plack Last-Modified header from BML-era mtime bookkeeping' );
    };

done_testing;
