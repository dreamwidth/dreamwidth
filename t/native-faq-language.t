#!/usr/bin/perl
# Regression coverage for native request-language FAQ controller calls.
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
use DW::Controller::Support::Faq;

sub request {
    my ($query) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/support/faqbrowse',
            QUERY_STRING      => $query || '',
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

    package NativeFaqLanguage::ExampleUser;
    sub user         { 'example' }
    sub journal_base { '/example/' }
}

{

    package NativeFaqLanguage::Reader;
    sub selectrow_array { 'General' }
}

{

    package NativeFaqLanguage::Writer;
}

{

    package NativeFaqLanguage::Faq;
    sub new { my ( $class, %args ) = @_; bless \%args, $class }
    sub faqid           { $_[0]{faqid} }
    sub unixmodtime     { $_[0]{unixmodtime} }
    sub summary_raw     { $_[0]{summary} }
    sub answer_raw      { $_[0]{answer} }
    sub has_summary     { 0 }
    sub question_html   { $_[0]{question} }
    sub faqcat          { 'general' }
    sub sortorder       { 1 }
    sub lastmoduserid   { 1 }
    sub lastmodtime     { 'now' }
    sub render_in_place { 1 }
}

sub native_context {
    my ( $lang, $calls ) = @_;
    LJ::Lang::set_request_context(
        lang   => $lang,
        getter => sub {
            my ( $got_lang, $code, $unused, $vars ) = @_;
            push @$calls, [ $got_lang, $code, { %{ $vars || {} } } ];
            return "native:$got_lang:$code";
        },
    );
}

sub local_handler_dependencies {
    my ($rendered) = @_;
    no warnings 'redefine';
    local *DW::Controller::Support::Faq::controller = sub { return ( 1, {} ) };
    local *LJ::load_user = sub { return bless {}, 'NativeFaqLanguage::ExampleUser' };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @$rendered, [ $template, $vars ];
        return "rendered:$template";
    };
    return;
}

subtest 'faq search uses current native request language and global getter key' => sub {
    my $r = request('');
    my @calls;
    native_context( 'fr', \@calls );
    my @rendered;

    no warnings 'redefine';
    local @LJ::LANGS                                = qw(en fr);
    local $LJ::DEFAULT_LANG                         = 'en';
    local *DW::Controller::Support::Faq::controller = sub { return ( 1, {} ) };
    local *LJ::load_user = sub { return bless {}, 'NativeFaqLanguage::ExampleUser' };
    local *LJ::Lang::get_lang =
        sub { return { lncode => $_[0] } if $_[0] =~ /\A(?:en|fr)\z/; return };
    local *LJ::Lang::get_text            = sub { return "native-name:$_[0]:$_[1]" };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @rendered, [ $template, $vars ];
        return "rendered:$template";
    };

    is(
        DW::Controller::Support::Faq::faqsearch_handler(),
        'rendered:support/faqsearch.tt',
        'actual search handler renders'
    );
    is( $rendered[0][1]{sel}, 'fr', 'native effective language selects the request language' );
    is_deeply(
        $rendered[0][1]{langs},
        [
            'en', 'native-name:en:langname.en (native:fr:langname.en)',
            'fr', 'native-name:fr:langname.fr (native:fr:langname.fr)'
        ],
        'current-language labels use the request getter while native names keep their language'
    );
    is_deeply(
        [ map { $_->[1] } @calls ],
        [qw(langname.en langname.fr)],
        'language-name keys remain absolute rather than acquiring a template scope'
    );
};

subtest 'faq browse keeps default-language fallback and native error scope' => sub {
    my $r = request('faqid=91&lang=not-a-language');
    my @calls;
    native_context( 'fr', \@calls );
    my @rendered;
    my @load_lang;

    no warnings 'redefine';
    local $LJ::DEFAULT_LANG                         = 'en';
    local *DW::Controller::Support::Faq::controller = sub { return ( 1, {} ) };
    local *LJ::load_user      = sub { return bless {}, 'NativeFaqLanguage::ExampleUser' };
    local *LJ::get_db_reader  = sub { return undef };
    local *LJ::Lang::get_lang = sub { return { lncode => 'fr' } if $_[0] eq 'fr'; return };
    local *LJ::Lang::get_dom  = sub { return { dmid => 1 } };
    local *LJ::Faq::load      = sub { push @load_lang, $_[3]; return };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @rendered, [ $template, $vars ];
        return "rendered:$template";
    };

    is(
        DW::Controller::Support::Faq::faqbrowse_handler(),
        'rendered:support/faqbrowse.tt',
        'actual browse handler renders its no-FAQ response'
    );
    is( $load_lang[0], 'en',
        'unknown requested language falls back to application default for FAQ data' );
    ok( !$rendered[0][1]{altlang},
        'unknown requested language is not treated as an alternate FAQ translation' );
    is(
        $calls[0][1],
        '/support/faqbrowse.tt.error.title_nofaq',
        'browse error keeps its existing fully scoped native translation key'
    );
};

subtest 'FAQ content does not manufacture a Plack Last-Modified header' => sub {
    my $r = request('faqid=92');
    my @calls;
    native_context( 'en', \@calls );
    my @rendered;
    my $faq = NativeFaqLanguage::Faq->new(
        faqid       => 92,
        unixmodtime => time - 60,
        summary     => '',
        answer      => 'answer',
        question    => 'Question'
    );

    no warnings 'redefine';
    local $LJ::DEFAULT_LANG                         = 'en';
    local *DW::Controller::Support::Faq::controller = sub { return ( 1, {} ) };
    local *LJ::load_user              = sub { return bless {}, 'NativeFaqLanguage::ExampleUser' };
    local *LJ::get_db_reader          = sub { return bless {}, 'NativeFaqLanguage::Reader' };
    local *LJ::get_db_writer          = sub { return bless {}, 'NativeFaqLanguage::Writer' };
    local *LJ::get_username           = sub { return 'editor' };
    local *LJ::Lang::get_lang         = sub { return { lncode => 'en' } if $_[0] eq 'en'; return };
    local *LJ::Lang::get_dom          = sub { return { dmid => 1 } };
    local *LJ::Faq::load              = sub { return $faq };
    local *LJ::CleanHTML::clean_event = sub { return };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @rendered, [ $template, $vars ];
        return "rendered:$template";
    };

    is(
        DW::Controller::Support::Faq::faqbrowse_handler(),
        'rendered:support/faqbrowse.tt',
        'actual FAQ content handler renders'
    );
    is( $r->header_out('Last-Modified'), undef,
'legacy BML modification bookkeeping did not provide a Plack response header and is not replaced implicitly'
    );
};

subtest 'sequential FAQ requests do not leak native language context' => sub {
    my @rendered;
    no warnings 'redefine';
    local @LJ::LANGS                                = qw(en fr);
    local $LJ::DEFAULT_LANG                         = 'en';
    local *DW::Controller::Support::Faq::controller = sub { return ( 1, {} ) };
    local *LJ::load_user = sub { return bless {}, 'NativeFaqLanguage::ExampleUser' };
    local *LJ::Lang::get_lang =
        sub { return { lncode => $_[0] } if $_[0] =~ /\A(?:en|fr)\z/; return };
    local *LJ::Lang::get_text            = sub { return "fallback:$_[0]:$_[1]" };
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        push @rendered, [ $template, $vars ];
        return "rendered:$template";
    };

    request('');
    my @calls;
    native_context( 'fr', \@calls );
    DW::Controller::Support::Faq::faqsearch_handler();
    is( $rendered[-1][1]{sel}, 'fr', 'first actual request uses its native request language' );

    request('');
    DW::Controller::Support::Faq::faqsearch_handler();
    is( $rendered[-1][1]{sel},
        'en', 'second actual request falls back to default instead of leaking prior context' );

    DW::Request->reset;
    is( LJ::Lang::ml('langname.en'),
        'fallback:en:langname.en',
        'nonweb fallback keeps the global FAQ language key and application default' );
};

done_testing;
