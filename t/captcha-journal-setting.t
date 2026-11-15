# t/captcha-journal-setting.t
#
# Test journal CAPTCHA policy and the explanation rendered beside a challenge.
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

use LJ::Talk;
use DW::Template;

{

    package Local::CaptchaAccount;
    our @ISA = ('LJ::User');
    sub new { my ( $class, %args ) = @_; return bless {%args}, $class; }
    sub identity                         { return $_[0]{identity}; }
    sub is_validated                     { return $_[0]{validated}; }
    sub equals                           { return defined $_[1] && $_[0] == $_[1]; }
    sub prop                             { return $_[0]{setting}; }
    sub trusts_or_has_member             { return $_[1] && $_[1]{trusted}; }
    sub count_maxcomments_before_captcha { return 10; }

    package Local::CaptchaEntry;
    sub ditemid      { return 257; }
    sub logtime_unix { return time() - $_[0]{age_days} * 86400; }

    package Local::CaptchaImplementation;
    sub enabled { return $_[0]{enabled}{ $_[1] || '' }; }

    package Local::CaptchaRequest;

    sub note {
        my ( $self, $key, $value ) = @_;
        $self->{$key} = $value if @_ > 2;
        return $self->{$key};
    }
}

my $journal = Local::CaptchaAccount->new;
my @actors  = (
    undef,
    Local::CaptchaAccount->new,
    Local::CaptchaAccount->new( trusted  => 1 ),
    Local::CaptchaAccount->new( identity => 1 ),
    Local::CaptchaAccount->new( identity => 1, validated => 1 ),
    $journal,
);
my @names = (
    'anonymous',          'outsider', 'trusted or member', 'unvalidated identity',
    'validated identity', 'owner'
);

subtest 'journal policy preserves exemptions' => sub {
    my %expected = (
        N => [ '',         '',         '',         '',         '',         'owner' ],
        R => [ 'required', '',         '',         'required', '',         'owner' ],
        F => [ 'required', 'required', '',         'required', 'required', 'owner' ],
        A => [ 'required', 'required', 'required', 'required', 'required', 'owner' ],
    );
    no warnings qw(redefine once);
    for my $trusted ( 0, 1 ) {
        local *LJ::Session::trusted_anon_user = sub { return $trusted; };
        for my $level (qw(N R F A)) {
            $journal->{setting} = $level;
            for my $i ( 0 .. $#actors ) {
                my $want = $expected{$level}[$i];
                $want = 'trusted_anon' if $level eq 'R' && $trusted && ( $i == 0 || $i == 3 );
                is( LJ::Talk::Post::journal_captcha_policy( $actors[$i], $journal ),
                    $want, "$level $names[$i], trust cookie=$trusted" );
            }
        }
    }
};

subtest 'full gate keeps reason ordering and bypass metrics' => sub {
    my %enabled;
    my ( $rate_ok, $sysban, $replycount ) = ( 1, 0, 0 );
    my @bypasses;
    my $trusted = 0;
    my $entry   = bless { age_days => 1 }, 'Local::CaptchaEntry';
    no warnings qw(redefine once);
    local *DW::Captcha::site_enabled = sub { return 1; };
    local *DW::Captcha::new          = sub {
        return bless { enabled => \%enabled }, 'Local::CaptchaImplementation';
    };
    local *DW::Captcha::record_bypass     = sub { push @bypasses, [@_]; };
    local *LJ::Session::trusted_anon_user = sub { return $trusted; };
    local *LJ::Talk::Post::check_rate     = sub { return $rate_ok; };
    local *LJ::sysban_check               = sub { return $sysban; };
    local *LJ::get_remote_ip              = sub { return '198.51.100.10'; };
    local *LJ::Talk::get_replycount       = sub { return $replycount; };

    my $check = sub {
        my ( $actor, $body ) = @_;
        @bypasses = ();
        return LJ::Talk::Post::require_captcha_test( $actor, $journal, $body || '', $entry );
    };
    $journal->{setting} = 'A';
    is( $check->(undef), 'journal_setting', 'journal policy supplies the reason' );
    $enabled{anonpost} = 1;
    $rate_ok = 0;
    is( $check->(undef),    'rate_limited', 'rate limit has priority over journal setting' );
    is( $check->($journal), 'rate_limited', 'rate limit still applies to owner' );
    $rate_ok = 1;
    $sysban  = 1;
    is( $check->(undef), 'ip_sysban', 'IP check has priority over journal setting' );
    $sysban            = 0;
    $replycount        = 10;
    $entry->{age_days} = 31;
    is( $check->($journal), 'maxcomments', 'old-entry check still applies to owner' );
    $replycount = 0;
    is( $check->($journal), '', 'owner remains exempt from journal setting' );
    %enabled            = ( comment_html_anon => 1 );
    $journal->{setting} = 'R';
    $trusted            = 1;
    is( $check->(undef),  '', 'trusted anonymous R bypass remains allowed' );
    is( scalar @bypasses, 1,  'one bypass metric' );
    ok( scalar( grep { $_ eq 'reason:journal_setting' } @{ $bypasses[0] } ),
        'bypass retains journal setting reason' );
    $enabled{comment_html_auth} = 1;
    is( $check->( undef, '<a href="https://example.test/">link</a>' ),
        'comment_html', 'later site HTML rule still overrides the bypass' );
    is( scalar @bypasses, 0, 'no bypass metric when a later rule requires CAPTCHA' );
};

subtest 'shared form fragment explains only visible journal challenges' => sub {
    my $request = bless { ml_lang => 'debug' }, 'Local::CaptchaRequest';
    no warnings qw(redefine once);
    local *DW::Request::get = sub { return $request; };
    for my $html ( '', '<div id="local-captcha">Challenge</div>' ) {
        for my $policy ( 0, 1 ) {
            my $rendered = DW::Template->template_string( 'journal/captcha.tt',
                { captcha => { html => $html, journal_setting => $policy } } );
            if ( length $html ) {
                like( $rendered, qr/id="local-captcha"/, 'real challenge markup retained' );
            }
            if ( length($html) && $policy ) {
                like(
                    $rendered,
                    qr/<p class="captcha-journal-setting">captcha\.journal_setting<\/p>/,
                    'renders localized journal explanation beside challenge'
                );
            }
            else {
                unlike( $rendered, qr/captcha-journal-setting/,
                    'no explanation for site-only or absent challenge' );
            }
            unlike( $rendered, qr/local-captcha/, 'no challenge markup when HTML is empty' )
                unless length $html;
        }
    }
};

done_testing();
