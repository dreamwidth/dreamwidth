# t/captcha.t
#
# Test DW::Captcha
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $recaptcha_enabled   = DW::Captcha::reCAPTCHA->site_enabled;
my $textcaptcha_enabled = DW::Captcha::textCAPTCHA->site_enabled;

if ( ! DW::Captcha->site_enabled ) {
    plan skip_all => "CAPTCHA functionality disabled.";
} elsif ( ! $recaptcha_enabled && ! $textcaptcha_enabled ) {
    plan skip_all => "No valid CAPTCHA configuration.";
} else {
    plan tests => 13;
}


# override for the sake of the test
%LJ::CAPTCHA_FOR = (
    testpage => 1,
    nocaptchapage => 0,
);

note( "disabled captcha for a specific page" );
{
    my $captcha = DW::Captcha->new( "nocaptchapage" );
    ok( ! $captcha->enabled, "Captcha is not enabled for nocaptchapage" );
}

note( "check captcha is enabled" );
{
    my $captcha = DW::Captcha->new( "testpage" );
    ok( $captcha->enabled, "Captcha is enabled for testpage" );
}

note( "check various implementations are loaded okay" );
{
    my $default = $LJ::CAPTCHA_TYPES{$LJ::DEFAULT_CAPTCHA_TYPE};
    my $captcha = DW::Captcha->new( 'testpage' );
    is( $captcha->name, $default, "Use default captcha implementation" );


    SKIP: {
        skip "reCAPTCHA disabled.", 2 unless $recaptcha_enabled;

        $captcha = DW::Captcha->new( 'testpage', want => 'I' );
        is( $captcha->name, "recaptcha", "Using reCAPTCHA" );

        # can also be done using DW::Captcha::reCAPTCHA->site_enabled
        # but technically we shouldn't be worrying about module names
        ok( $captcha->site_enabled, "reCAPTCHA is enabled and configured on this site" );
    }

    SKIP: {
        skip "textCAPTCHA disabled.", 2 unless $textcaptcha_enabled;

        $captcha = DW::Captcha->new( 'testpage', want => 'T' );
        is( $captcha->name, "textcaptcha", "Using textCAPTCHA" );
        ok( $captcha->site_enabled, "textCAPTCHA is enabled and configured on this site" );
    }

    $captcha = DW::Captcha->new( 'testpage', want => 'abc' );
    is( $captcha->name, $default, "not a valid captcha implementation, so used default" );
    ok( $captcha->site_enabled, "not a valid captcha implementation, so used default to make sure we still get captcha" );
}

note( "user tries to use a disabled captcha type" );
# it's possible only one type currently works, so activate a good one
{
    local %LJ::DISABLED = ( captcha  => sub {
        my $module = $_[0] // '';
        return ! $recaptcha_enabled if $module eq "recaptcha";
        return $recaptcha_enabled if $module eq "textcaptcha";
    } );
    local $LJ::DEFAULT_CAPTCHA_TYPE = $recaptcha_enabled ? "I" : "T";
    my $BAD_CAPTCHA_TYPE = $recaptcha_enabled ? "T" : "I";
    my $default_name = $LJ::CAPTCHA_TYPES{$LJ::DEFAULT_CAPTCHA_TYPE};

    my $captcha = DW::Captcha->new( "testpage", want => $LJ::DEFAULT_CAPTCHA_TYPE );
    is( $captcha->name, $default_name, "want $default_name, everything is fine" );
    ok( $captcha->site_enabled, "$default_name was enabled" );

    $captcha = DW::Captcha->new( "testpage", want => $BAD_CAPTCHA_TYPE );
    is( $captcha->name, $default_name, "wanted other type, but it's not enabled so use default instead" );
    ok( $captcha->site_enabled, "our fallback is enabled" );
}
