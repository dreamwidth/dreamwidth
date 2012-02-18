# -*-perl-*-

use strict;
use Test::More tests => 14;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

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

    ok( DW::Captcha->site_enabled, "Captcha is enabled site-wide" );
    my $captcha = DW::Captcha->new( 'testpage' );
    is( $captcha->name, $default, "Use default captcha implementation" );


    $captcha = DW::Captcha->new( 'testpage', want => 'I' );
    is( $captcha->name, "recaptcha", "Using reCAPTCHA" );

    # can also be done using DW::Captcha::reCAPTCHA->site_enabled
    # but technically we shouldn't be worrying about module names
    ok( $captcha->site_enabled, "reCAPTCHA is enabled and configured on this site" );


    $captcha = DW::Captcha->new( 'testpage', want => 'T' );
    is( $captcha->name, "textcaptcha", "Using textCAPTCHA" );
    ok( $captcha->site_enabled, "textCAPTCHA is enabled and configured on this site" );

    $captcha = DW::Captcha->new( 'testpage', want => 'abc' );
    is( $captcha->name, $default, "not a valid captcha implementation, so used default" );
    ok( $captcha->site_enabled, "not a valid captcha implementation, so used default to make sure we still get captcha" );
}

note( "user tries to use a disabled captcha type" );
{
    local %LJ::DISABLED = ( captcha  => sub {
        my $module = $_[0];
        return 0 if $module eq "recaptcha";
        return 1 if $module eq "textcaptcha";
    } );
    local $LJ::DEFAULT_CAPTCHA_TYPE = "I";

    my $captcha = DW::Captcha->new( "testpage", want => "I" ); # image
    is( $captcha->name, "recaptcha", "want recaptcha, everything is fine" );
    ok( $captcha->site_enabled, "recaptcha was enabled" );

    my $captcha = DW::Captcha->new( "testpage", want => "T" ); # text
    is( $captcha->name, "recaptcha", "wanted textcaptcha, but it's not enabled so use recaptcha instead" );
    ok( $captcha->site_enabled, "recaptcha (our fallback) is enabled" );
}
