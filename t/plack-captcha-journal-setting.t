# t/plack-captcha-journal-setting.t
#
# Journal CAPTCHA explanations survive comment preview and failed-answer redisplay.
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user with_fake_memcache);
use DW::Captcha;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# Match production form-auth binding across in-process dev impersonation requests.
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'captchaJournalTest';

my $owner    = temp_user();
my $stranger = temp_user();
$_->update_self( { status => 'A' } ) for ( $owner, $stranger );
$owner->update_self( { opt_whocanreply => 'all' } );
my $entry = $owner->t_post_fake_entry( body => 'Journal CAPTCHA regression entry' );

with_fake_memcache {
    no warnings qw(redefine once);
    local %LJ::DISABLED                 = ( %LJ::DISABLED, captcha => 0 );
    local %LJ::CAPTCHA_FOR              = ();
    local $LJ::CAPTCHA_HCAPTCHA_SITEKEY = 'local-test-sitekey';
    local $LJ::CAPTCHA_HCAPTCHA_SECRET  = 'local-test-secret';
    my $configured = 1;
    local *DW::Captcha::hCaptcha::_implementation_enabled = sub { return $configured; };
    local *LJ::Session::trusted_anon_user                 = sub { return undef; };

    # Keep the real CAPTCHA wrapper and validation, but replace the external
    # provider boundary. No request in this test can contact hCaptcha.
    local *DW::Captcha::hCaptcha::_print = sub {
        return '<input name="h-captcha-response" id="local-captcha" />';
    };
    local *DW::Captcha::hCaptcha::_validate = sub {
        return $_[0]->response eq 'local-correct';
    };
    my $beta   = \&LJ::BetaFeatures::user_in_beta;
    my $legacy = 0;
    local *LJ::BetaFeatures::user_in_beta = sub {
        return $legacy if ( $_[2] || '' ) eq 'nos2foundation';
        return $beta->(@_);
    };

    test_psgi $app, sub {
        my $cb = shift;
        for $legacy ( 0, 1 ) {
            subtest $legacy ? 'legacy form' : 'Foundation form' => sub {
                for my $who ( 'nobody_exists', $stranger->user, $owner->user ) {

                    # Bind a genuine signed token to this dev-impersonated viewer,
                    # as in plack-talkpost.t; /login has independent view-CAPTCHA gates.
                    my $viewer = $who eq 'nobody_exists' ? undef : LJ::load_user($who);
                    LJ::set_remote($viewer);
                    delete $LJ::REQ_GLOBAL{form_auth_chal};
                    my $token = LJ::form_auth(1);
                    LJ::set_remote(undef);
                    for my $setting ( 'N', 'A' ) {
                        $owner->set_prop( opt_show_captcha_to => $setting );
                        for my $preview ( 0, 1 ) {

                            # Both paths redisplay after an actual failed answer;
                            # neither can create a comment, even if preview breaks.
                            my $res = $cb->(
                                POST "http://localhost/talkpost_do?as=$who",
                                [
                                    lj_form_auth => $token,
                                    chrp1 =>
                                        LJ::Talk::generate_chrp1( $owner->id, $entry->ditemid ),
                                    journal  => $owner->user,
                                    itemid   => $entry->ditemid,
                                    usertype => $who eq 'nobody_exists'
                                    ? 'anonymous'
                                    : 'cookieuser',
                                    cookieuser              => $who,
                                    body                    => 'Retained CAPTCHA test body',
                                    subjecticon             => 'none',
                                    submitpreview           => $preview,
                                    'h-captcha-response'    => 'local-incorrect',
                                    captcha_journal_setting => 1,
                                ]
                            );
                            is( $res->code, 200,
                                "$who setting=$setting preview=$preview redisplays" );
                            like( $res->content, qr/id="local-captcha"/,
                                'challenge is rendered again' );
                            like(
                                $res->content,
                                qr/Retained CAPTCHA test body/,
                                'draft is retained'
                            );
                            my $required = $setting eq 'A' && $who ne $owner->user;
                            if ($required) {
                                like(
                                    $res->content,
                                    qr/class="captcha-journal-setting"/,
                                    'applicable journal policy is explained on redisplay'
                                );
                            }
                            else {
                                unlike( $res->content, qr/class="captcha-journal-setting"/,
                                    'posted explanation flag cannot override actual journal policy'
                                );
                            }
                        }
                    }

                    my $bad_form = $cb->(
                        POST "http://localhost/talkpost_do?as=$who",
                        [
                            lj_form_auth            => 'invalid',
                            journal                 => $owner->user,
                            itemid                  => $entry->ditemid,
                            usertype                => 'anonymous',
                            body                    => 'Untrusted form',
                            captcha_journal_setting => 1,
                            'h-captcha-response'    => 'local-incorrect',
                        ]
                    );
                    unlike(
                        $bad_form->content,
                        qr/class="captcha-journal-setting"/,
                        'failed form authentication cannot request an explanation'
                    );

                    # Preview with no configured implementation cannot publish a
                    # comment and must not label an invisible CAPTCHA.
                    $configured = 0;
                    my $disabled = $cb->(
                        POST "http://localhost/talkpost_do?as=$who",
                        [
                            lj_form_auth => $token,
                            chrp1        => LJ::Talk::generate_chrp1( $owner->id, $entry->ditemid ),
                            journal      => $owner->user,
                            itemid       => $entry->ditemid,
                            usertype     => 'anonymous',
                            body         => 'Disabled CAPTCHA preview',
                            subjecticon  => 'none',
                            submitpreview           => 1,
                            captcha_journal_setting => 1,
                        ]
                    );
                    unlike(
                        $disabled->content,
                        qr/class="captcha-journal-setting"/,
                        'unconfigured CAPTCHA has no journal explanation'
                    );
                    $configured = 1;
                }
            };
        }
    };
};

done_testing();
