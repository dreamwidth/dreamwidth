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

my $hcaptcha_enabled = DW::Captcha::hCaptcha->site_enabled;

if ( !DW::Captcha->site_enabled ) {
    plan skip_all => "CAPTCHA functionality disabled.";
}
elsif ( !$hcaptcha_enabled ) {
    plan skip_all => "No valid CAPTCHA configuration.";
}
else {
    plan tests => 8;
}

# override for the sake of the test
%LJ::CAPTCHA_FOR = (
    testpage      => 1,
    nocaptchapage => 0,
);

note("disabled captcha for a specific page");
{
    my $captcha = DW::Captcha->new("nocaptchapage");
    ok( !$captcha->enabled, "Captcha is not enabled for nocaptchapage" );
}

note("check captcha is enabled");
{
    my $captcha = DW::Captcha->new("testpage");
    ok( $captcha->enabled, "Captcha is enabled for testpage" );
}

note("check various implementations are loaded okay");
{
    my $default = $LJ::CAPTCHA_TYPES{$LJ::DEFAULT_CAPTCHA_TYPE};
    my $captcha = DW::Captcha->new('testpage');
    is( $captcha->name, $default, "Use default captcha implementation" );

    $captcha = DW::Captcha->new( 'testpage', want => 'H' );
    is( $captcha->name, "hcaptcha", "Using hCaptcha" );

    # can also be done using DW::Captcha::hCaptcha->site_enabled
    # but technically we shouldn't be worrying about module names
    ok( $captcha->site_enabled, "hCaptcha is enabled and configured on this site" );

    $captcha = DW::Captcha->new( 'testpage', want => 'abc' );
    is( $captcha->name, $default, "not a valid captcha implementation, so used default" );
    ok( $captcha->site_enabled,
        "not a valid captcha implementation, so used default to make sure we still get captcha" );
}

note("captcha implementation disabled via the DISABLED config");
{
    local %LJ::DISABLED = (
        captcha => sub {
            my $module = $_[0] // '';
            return 1 if $module eq "hcaptcha";    # disable hCaptcha specifically
            return 0;
        }
    );

    my $captcha = DW::Captcha->new("testpage");
    ok( !$captcha->site_enabled, "hCaptcha is disabled via the DISABLED config" );
}
