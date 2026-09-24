#!/usr/bin/perl
# Support request FAQ reference-list language regression coverage.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use DW::Controller::Support::Request;

{

    package SupportRequestFaqReference::User;

    sub new {
        bless { user => 'requester', name => 'Requester', status => 'A', stylesys => 1 }, shift;
    }
    sub user          { $_[0]{user} }
    sub journal_base  { '/requester/' }
    sub email_raw     { 'requester@example.test' }
    sub preload_props { 1 }
    sub is_suspended  { 0 }
    sub has_priv      { 0 }
    sub is_personal   { 1 }
}

{

    package SupportRequestFaqReference::Remote;
    sub user         { 'helper' }
    sub journal_base { '/helper/' }
    sub has_priv     { 0 }
}

{

    package SupportRequestFaqReference::STH;
    sub new { my ( $class, $rows ) = @_; bless { rows => [@$rows] }, $class }
    sub execute          { 1 }
    sub fetchrow_hashref { shift @{ $_[0]{rows} } }
}

{

    package SupportRequestFaqReference::DB;

    sub prepare {
        my ( $self, $sql ) = @_;
        return SupportRequestFaqReference::STH->new( [] ) if $sql =~ /supportlog/;
        return SupportRequestFaqReference::STH->new(
            $SupportRequestFaqReference::ALT
            ? [
                { faqcat => 'basics',  faqcatname => 'Fondamentaux', catorder => 10 },
                { faqcat => 'general', faqcatname => 'Général',    catorder => 20 },
                ]
            : [
                { faqcat => 'basics',  faqcatname => 'Basics',  catorder => 10 },
                { faqcat => 'general', faqcatname => 'General', catorder => 20 },
            ]
        );
    }
}

{

    package SupportRequestFaqReference::Faq;
    sub new { my ( $class, %args ) = @_; bless \%args, $class }
    sub faqid           { $_[0]{faqid} }
    sub faqcat          { $_[0]{faqcat} }
    sub sortorder       { $_[0]{sortorder} }
    sub question_raw    { $_[0]{question} }
    sub render_in_place { 1 }
}

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/support/see_request',
            QUERY_STRING      => 'id=71',
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

sub run_reference_list {
    my ($lang) = @_;
    request();
    $SupportRequestFaqReference::ALT = $lang ne 'en';
    my @rendered;
    my @load_lang;
    my $user   = SupportRequestFaqReference::User->new;
    my $remote = bless {}, 'SupportRequestFaqReference::Remote';
    my $db     = bless {}, 'SupportRequestFaqReference::DB';

    LJ::Lang::set_request_context( lang => $lang, getter => sub { return $_[1] } );

    no warnings 'redefine';
    local $LJ::DEFAULT_LANG = 'en';
    local *DW::Controller::Support::Request::controller =
        sub { return ( 1, { remote => $remote } ) };
    local *LJ::get_db_reader         = sub { return $db };
    local *LJ::Support::load_request = sub {
        return {
            spid         => 71,
            reqtype      => 'user',
            requserid    => 17,
            reqemail     => 'requester@example.test',
            state        => 'open',
            subject      => 'FAQ list',
            timecreate   => time,
            timelasthelp => 0,
            timetouched  => 0,
            _cat         => { catname => 'Support', catkey => 'support', public_read => 1 },
        };
    };
    local *LJ::Support::load_props = sub { return {} };
    local *LJ::Support::load_cats  = sub { return {} };
    local *LJ::Support::init_remote      = sub { 1 };
    local *LJ::load_userid               = sub { return $user };
    local *LJ::robot_meta_tags           = sub { return '' };
    local *LJ::Support::can_read         = sub { 1 };
    local *LJ::Support::can_close        = sub { 0 };
    local *LJ::Support::can_reopen       = sub { 0 };
    local *LJ::Support::can_help         = sub { 1 };
    local *LJ::Support::can_see_stocks   = sub { 0 };
    local *LJ::Support::is_poster        = sub { 0 };
    local *LJ::Support::can_read_cat     = sub { 0 };
    local *LJ::Support::can_see_helper   = sub { 0 };
    local *LJ::Support::get_answer_types = sub { return ( answer => 1 ) };
    local *LJ::Support::can_append       = sub { 0 };
    local *LJ::Capabilities::name_caps   = sub { return 'Free' };
    local *LJ::isu                       = sub { 0 };
    local *LJ::time_to_http              = sub { return 'now' };
    local *LJ::diff_ago_text             = sub { return 'now' };
    local *LJ::Lang::get_effective_lang  = sub { return $lang };
    local *LJ::Lang::get_lang =
        sub { return { lnid => 3, lncode => $_[0] } if $_[0] =~ /\A(?:en|fr)\z/; return };
    local *LJ::Lang::get_dom = sub { return { dmid => 9 } };
    local *LJ::Faq::load_all = sub {
        my ( undef, %args ) = @_;
        push @load_lang, $args{lang};
        my $translated = $args{lang} eq 'fr';
        return (
            SupportRequestFaqReference::Faq->new(
                faqid     => 202,
                faqcat    => 'general',
                sortorder => 2,
                question  => $translated ? "\n Général deux\n" : "\n General two\n",
            ),
            SupportRequestFaqReference::Faq->new(
                faqid     => 101,
                faqcat    => 'basics',
                sortorder => 2,
                question  => $translated ? 'Base beta' : 'Basics beta',
            ),
            SupportRequestFaqReference::Faq->new(
                faqid     => 100,
                faqcat    => 'basics',
                sortorder => 1,
                question  => $translated ? 'Base alpha' : 'Basics alpha',
            ),
        );
    };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @rendered, [ $template, $vars ];
        return "rendered:$template";
    };

    is(
        DW::Controller::Support::Request::see_request_handler(),
        'rendered:support/see_request.tt',
        "actual support request handler renders FAQ references for $lang"
    );
    return ( $rendered[0][1]{faqlist}, \@load_lang );
}

subtest 'default-language references retain category and FAQ ordering' => sub {
    my ( $faqlist, $loads ) = run_reference_list('en');
    is_deeply(
        $faqlist,
        [
            0,   '(don\'t reference FAQ)', 0,   '[ Basics ]',
            100, '... Basics alpha',       101, '... Basics beta',
            0,   '[ General ]',            202, '...   General two',
        ],
        'default FAQ categories and questions use their legacy order and rendered text'
    );
    is_deeply( $loads, ['en'], 'default reference list loads default-language FAQ content' );
};

subtest 'nondefault-language references retain translated category and FAQ ordering' => sub {
    my ( $faqlist, $loads ) = run_reference_list('fr');
    is_deeply(
        $faqlist,
        [
            0,   '(don\'t reference FAQ)', 0,   '[ Fondamentaux ]',
            100, '... Base alpha',         101, '... Base beta',
            0,   '[ Général ]',          202, '...   Général deux',
        ],
        'nondefault FAQ categories and questions remain translated and ordered'
    );
    is_deeply( $loads, ['fr'], 'nondefault reference list loads current-language FAQ content' );
};

done_testing;
