#!/usr/bin/perl
# Regression coverage for native request-language controller callers.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;
use LJ::JSON qw(from_json);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use DW::Controller::MassPrivacy;
use DW::Controller::RPC::CutExpander;
use DW::Controller::Customize::Advanced;
use DW::Setting::Display::AccountLevel;
use DW::Widget::AccountStatistics;
use LJ::NotificationMethod::Email;
use LJ::NotificationMethod::Inbox;

sub request {
    my ($query) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
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

    package NativeLanguageCallers::MassPrivacyUser;
    sub new { bless {}, shift }
    sub can_use_mass_privacy { return $_[0]->{allowed} }
}

subtest 'MassPrivacy renders native translated security labels only for permitted users' => sub {
    my $r = request();
    my @lookups;
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code ) = @_;
            push @lookups, $code;
            return "native:$code";
        },
    );

    my $vars;
    my $user = NativeLanguageCallers::MassPrivacyUser->new;
    $user->{allowed} = 1;
    local $LJ::DISABLED{mass_privacy};
    local *LJ::get_remote                   = sub { return $user; };
    local *LJ::remote_bounce_url            = sub { return undef; };
    local *DW::Captcha::should_captcha_view = sub { return 0; };
    local *DW::Template::render_template    = sub {
        my ( $class, $template, $render_vars ) = @_;
        is( $template, 'editprivacy.tt', 'permitted request reaches the editprivacy template' );
        $vars = $render_vars;
        return 'RENDERED';
    };

    is( DW::Controller::MassPrivacy::editprivacy_handler(),
        'RENDERED', 'permitted handler renders' );
    is_deeply(
        $vars->{security_list},
        [
            'public',  'native:label.security.public2',
            'friends', 'native:label.security.accesslist',
            'private', 'native:label.security.private2',
        ],
        'security labels come from the native request getter'
    );
    is_deeply(
        [ @lookups[ 0 .. 5 ] ],
        [
            'label.security.public2',    'label.security.accesslist',
            'label.security.private2',   'label.security.public2',
            'label.security.accesslist', 'label.security.private2',
        ],
        'security label lookup precedes the legacy month labels'
    );

    $user->{allowed} = 0;
    @lookups = ();
    local *DW::Controller::MassPrivacy::error_ml = sub { return LJ::Lang::ml( $_[0] ); };
    is(
        DW::Controller::MassPrivacy::editprivacy_handler(),
        'native:/editprivacy.tt.unable',
        'denied user receives the native translated error'
    );
    is_deeply( \@lookups, ['/editprivacy.tt.unable'], 'denial does not render security controls' );
    DW::Request->reset;
};

subtest 'CutExpander returns translated native errors for denied and missing entries' => sub {
    for my $case (
        [ '', 'request without cut parameters is denied' ],
        [ 'journal=this_journal_does_not_exist&ditemid=1&cutid=1', 'missing entry is denied' ],
        )
    {
        my ( $query, $description ) = @$case;
        my $r = request($query);
        LJ::Lang::set_request_context(
            lang   => 'en',
            getter => sub {
                my ( $lang, $code ) = @_;
                return "native:$code";
            },
        );

        DW::Controller::RPC::CutExpander::cutexpander_handler();
        my $response = $r->res;
        is( $response->[0], 200, "$description retains the legacy HTTP status" );
        my $json = from_json( join '', @{ $response->[2] } );
        is( $json->{error}, 'native:error.nopermission', "$description uses native translation" );
        DW::Request->reset;
    }
};

subtest 'Advanced layer browser formats object values with its full template key' => sub {
    my $r = request();
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            push @calls, [ $code, $vars ];
            return "native:$code:$vars->{type}";
        },
    );

    my $vars;
    my $user = NativeLanguageCallers::MassPrivacyUser->new;
    $user->{allowed} = 1;
    local *LJ::get_remote                   = sub { return $user; };
    local *LJ::remote_bounce_url            = sub { return undef; };
    local *DW::Captcha::should_captcha_view = sub { return 0; };
    local *LJ::S2::get_public_layers        = sub { return {}; };
    local *LJ::S2::load_layer_info          = sub { return; };
    local *DW::Template::render_template    = sub {
        my ( $class, $template, $render_vars ) = @_;
        is( $template, 'customize/advanced/layerbrowse.tt', 'layer browser reaches its template' );
        $vars = $render_vars;
        return 'RENDERED';
    };

    is( DW::Controller::Customize::Advanced::layerbrowse_handler(),
        'RENDERED', 'layer browser handler builds its formatter' );
    is(
        $vars->{format_value}->( { _type => 'Widget <unsafe>' } ),
        'native:/customize/advanced/layerbrowse.tt.propformat.object:Widget &lt;unsafe&gt;',
        'object formatter substitutes escaped object type through native getter'
    );
    is_deeply(
        \@calls,
        [
            [
                '/customize/advanced/layerbrowse.tt.propformat.object',
                { type => 'Widget &lt;unsafe&gt;' },
            ],
        ],
        'object formatting resolves the full TT key before template rendering'
    );
    DW::Request->reset;
};

{

    package NativeLanguageCallers::AccountUser;

    sub new { bless { @_ > 1 ? @_ : () }, shift }
    sub tags   { return $_[0]->{tags}   || {}; }
    sub id     { return $_[0]->{id}     || 1; }
    sub userid { return $_[0]->{userid} || 1; }
}

subtest 'native account and notification methods use request-local translation getters' => sub {
    my $r = request();
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            $vars ||= {};
            push @calls, [ $code, $vars ];
            return "native:$code" unless keys %$vars;
            return join ':', 'native', $code,
                map { defined $vars->{$_} ? $vars->{$_} : '' } qw(type date status exptime);
        },
    );

    is(
        LJ::NotificationMethod::Email->title,
        'native:notification_method.email.title',
        'email title uses the request getter'
    );
    is(
        LJ::NotificationMethod::Inbox->title,
        'native:notification_method.inbox.title',
        'inbox title uses the request getter'
    );

    my $user = NativeLanguageCallers::AccountUser->new;
    my $stats_vars;
    local *LJ::get_remote                       = sub { return $user; };
    local *LJ::Memories::count                  = sub { return 0; };
    local *DW::Pay::get_account_type_name       = sub { return 'Premium'; };
    local *DW::Pay::get_account_expiration_time = sub { return 1_704_067_200; };
    local *DW::Template::template_string        = sub {
        my ( $class, $template, $vars ) = @_;
        is( $template, 'widget/accountstatistics.tt', 'account statistics reaches its template' );
        $stats_vars = $vars;
        return 'RENDERED';
    };
    is( DW::Widget::AccountStatistics->render_body,
        'RENDERED', 'expiring account statistics renders' );
    like(
        $stats_vars->{accttype_string},
        qr/^native:widget\.accountstatistics\.expires_on:Premium:/,
        'expiring account text uses request getter substitutions'
    );

    local *DW::Pay::get_paid_status =
        sub { return { typeid => 7, expiresin => 1, expiretime => '2030-01-02 03:04:05' }; };
    local *DW::Pay::type_name = sub { return 'Premium'; };
    local *LJ::mysql_time     = sub { return '2030-01-02 03:04:05'; };
    like(
        DW::Setting::Display::AccountLevel->option($user),
        qr/^native:setting\.display\.accounttype\.status:.*Premium.*:2030-01-02 03:04:05$/,
        'expiring account-level option uses request getter substitutions'
    );

    is_deeply(
        [ map { $_->[0] } @calls ],
        [
            'notification_method.email.title',     'notification_method.inbox.title',
            'widget.accountstatistics.expires_on', 'setting.display.accounttype.status',
        ],
        'all migrated methods use the native request getter'
    );
    DW::Request->reset;
};

subtest 'account translation callers preserve permanent, free, and nonweb behavior' => sub {
    my $user = NativeLanguageCallers::AccountUser->new;
    my $stats_vars;
    local *LJ::get_remote                       = sub { return $user; };
    local *LJ::Memories::count                  = sub { return 0; };
    local *DW::Template::template_string        = sub { $stats_vars = $_[2]; return 'RENDERED'; };
    local *DW::Pay::get_account_type_name       = sub { return 'Premium'; };
    local *DW::Pay::get_account_expiration_time = sub { return 0; };
    is( DW::Widget::AccountStatistics->render_body,
        'RENDERED', 'permanent account statistics renders' );
    is( $stats_vars->{accttype_string},
        'Premium', 'permanent account has no expiration translation' );

    local *DW::Pay::get_account_type_name = sub { return undef; };
    is( DW::Widget::AccountStatistics->render_body, 'RENDERED', 'free account statistics renders' );
    ok( !defined $stats_vars->{accttype_string}, 'free account has no account-level text' );

    local *DW::Pay::get_paid_status =
        sub { return { typeid => 7, permanent => 1, expiresin => 0 }; };
    local *DW::Pay::type_name = sub { return 'Premium'; };
    is(
        DW::Setting::Display::AccountLevel->option($user),
        '<strong>Premium</strong>',
        'permanent account-level option has no expiration translation'
    );
    local *DW::Pay::get_paid_status = sub { return undef; };
    local *DW::Pay::default_typeid  = sub { return 0; };
    local *DW::Pay::type_name       = sub { return 'Free'; };
    is( DW::Setting::Display::AccountLevel->option($user),
        '<strong>Free</strong>', 'free account-level option has no expiration translation' );

    local *LJ::Lang::get_text = sub {
        my ( $lang, $code, $unused, $vars ) = @_;
        $vars ||= {};
        return "background:$lang:$code:$vars->{type}"
            if $code eq 'widget.accountstatistics.expires_on';
        return "background:$lang:$code";
    };
    is(
        LJ::NotificationMethod::Email->title,
        'background:en:notification_method.email.title',
        'nonweb email title uses native default lookup'
    );
    is(
        LJ::NotificationMethod::Inbox->title,
        'background:en:notification_method.inbox.title',
        'nonweb inbox title uses native default lookup'
    );
    local *DW::Pay::get_account_type_name       = sub { return 'Premium'; };
    local *DW::Pay::get_account_expiration_time = sub { return 1_704_067_200; };
    is( DW::Widget::AccountStatistics->render_body,
        'RENDERED', 'nonweb expiring account statistics renders' );
    is(
        $stats_vars->{accttype_string},
        'background:en:widget.accountstatistics.expires_on:Premium',
        'nonweb account statistics uses the native default lookup'
    );
    local *DW::Pay::get_paid_status =
        sub { return { typeid => 7, expiresin => 1, expiretime => '2030-01-02 03:04:05' }; };
    local *DW::Pay::type_name = sub { return 'Premium'; };
    local *LJ::mysql_time     = sub { return '2030-01-02 03:04:05'; };
    is(
        DW::Setting::Display::AccountLevel->option($user),
        'background:en:setting.display.accounttype.status',
        'nonweb account-level option uses native default lookup'
    );
};

done_testing;
