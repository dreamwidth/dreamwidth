# t/plack-shop-transferpoints.t
#
# Exercise the points transfer forms and the balance changes they authorize.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTML::TokeParser;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

sub form_inputs {
    my ($body) = @_;
    while ( $body =~ m{<form\b[^>]*>(.*?)</form>}gis ) {
        my $form   = $1;
        my $parser = HTML::TokeParser->new( \$form );
        my %inputs;
        while ( my $tag = $parser->get_tag('input') ) {
            my $attrs = $tag->[1];
            $inputs{ $attrs->{name} } = $attrs if defined $attrs->{name};
            $inputs{submit} = $attrs if ( $attrs->{type} // '' ) eq 'submit';
        }
        return \%inputs if $inputs{foruser};
    }
    return {};
}

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $test = Plack::Test->create($app);
$test->request( GET 'http://localhost/robots.txt' );

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
local $LJ::T_SUPPRESS_EMAIL           = 1;
local $LJ::DISABLED{payments}         = 0;
local $LJ::DOMAIN_SHOP                = '';
local $LJ::SHOP{points}               = [];

my $sender    = temp_user();
my $recipient = temp_user();
$_->update_self( { status => 'A', statusvis => 'V' } ) for ( $sender, $recipient );
$sender->give_shop_points( amount => 30, reason => 'Transfer form test' );
my $url           = 'http://localhost/shop/transferpoints?as=' . $sender->user;
my $recipient_url = 'http://localhost/shop/transferpoints?as=' . $recipient->user;

my $empty = $test->request( GET $recipient_url );
is( $empty->code, 200, 'an account with no points can view the page' );
ok( !form_inputs( $empty->content )->{points}, 'no transfer form without a balance' );

my $initial = $test->request( GET $url );
is( $initial->code, 200, 'the transfer form is available to the sender' )
    or diag( 'Redirect: ', $initial->header('Location') // '' );
like( $initial->content, qr{foundation\.js}, 'the page loads Foundation resources' );
my $inputs = form_inputs( $initial->content );
is( $inputs->{foruser}->{type}, 'text',     'recipient is editable' );
is( $inputs->{points}->{type},  'number',   'points use a numeric control' );
is( $inputs->{anon}->{type},    'checkbox', 'sender can choose an anonymous transfer' );
ok( !$inputs->{anon}->{checked}, 'anonymity is opt-in' );
my $token = $inputs->{lj_form_auth}->{value};
ok( $token, 'the initial form has a form-auth token' );

my $prefilled = form_inputs( $test->request( GET "$url&for=" . $recipient->user )->content );
is( $prefilled->{foruser}->{type}, 'hidden', 'a recipient chosen via the shop stays fixed' );
is( $prefilled->{foruser}->{value}, $recipient->user, 'the prefilled recipient is submitted' );

my $invalid_recipient = $test->request( POST $url,
    [ lj_form_auth => $token, foruser => '<not-an-account>', points => 1, anon => 1 ] );
is( $invalid_recipient->code, 200, 'invalid recipient redisplays the form' );
ok(
    $invalid_recipient->content =~ /<small class="error"[^>]*>/,
    'recipient validation renders a Foundation field error'
);
unlike( $invalid_recipient->content, qr/<not-an-account>/, 'invalid input is HTML escaped' );
my $retry = form_inputs( $invalid_recipient->content );
is( $retry->{foruser}->{value}, '<not-an-account>', 'the recipient can be corrected' );
ok( $retry->{anon}->{checked}, 'correcting the form does not opt out of anonymity' );
ok( !$retry->{confirm},        'invalid recipient cannot reach confirmation' );

my $too_many = $test->request( POST $url,
    [ lj_form_auth => $token, foruser => $recipient->user, points => 31, confirm => 1 ] );
is( $too_many->code, 200, 'insufficient points redisplays the form' );
ok(
    $too_many->content =~ /<small class="error"[^>]*>/,
    'the amount problem renders a Foundation field error'
);
ok( !form_inputs( $too_many->content )->{confirm}, 'the invalid amount cannot be confirmed' );
is( LJ::load_userid( $sender->id, 1 )->shop_points,
    30, 'invalid submissions do not debit the sender' );
is( LJ::load_userid( $recipient->id, 1 )->shop_points,
    0, 'invalid submissions do not credit the recipient' );

for my $anonymous ( 0, 1 ) {
    subtest $anonymous ? 'anonymous transfer' : 'named transfer' => sub {
        my $reason  = 'A "note" & a gift';
        my $preview = $test->request(
            POST $url,
            [
                lj_form_auth => $token,
                foruser      => $recipient->user,
                points       => 10,
                anon         => $anonymous,
                reason       => $reason,
            ]
        );
        is( $preview->code, 200, 'the transfer can be reviewed' );
        my $confirmation = form_inputs( $preview->content );
        like( $confirmation->{submit}->{class} // '',
            qr/\bbutton\b/, 'confirmation uses a Foundation submit button' );
        is( $preview->content =~ /They will not know the points came from you/ ? 1 : 0,
            $anonymous, 'the review describes anonymity only when selected' );
        is( $confirmation->{foruser}->{value}, $recipient->user, 'recipient carries forward' );
        is( $confirmation->{points}->{value}, 10, 'amount carries forward' );
        is( $confirmation->{anon}->{value},   $anonymous, 'anonymity choice carries forward' );
        is( $confirmation->{reason}->{value}, $reason,    'escaped note round-trips unchanged' );
        is( $confirmation->{confirm}->{value}, 1, 'the form explicitly confirms the transfer' );
        is(
            LJ::load_userid( $sender->id, 1 )->shop_points,
            30 - 10 * $anonymous,
            'reviewing does not debit the sender'
        );
        is(
            LJ::load_userid( $recipient->id, 1 )->shop_points,
            10 * $anonymous,
            'reviewing does not credit the recipient'
        );

        my @values =
            map { $_ => $confirmation->{$_}->{value} } qw(foruser points anon reason confirm);
        my $rejected = $test->request( POST $url, [ @values, lj_form_auth => 'invalid' ] );
        ok( $rejected->is_error, 'confirmation requires valid form authentication' );
        is(
            LJ::load_userid( $sender->id, 1 )->shop_points,
            30 - 10 * $anonymous,
            'invalid auth cannot debit the sender'
        );
        is(
            LJ::load_userid( $recipient->id, 1 )->shop_points,
            10 * $anonymous,
            'invalid auth cannot credit the recipient'
        );

        my $complete = $test->request( POST $url,
            [ @values, lj_form_auth => $confirmation->{lj_form_auth}->{value} ] );
        is( $complete->code, 200, 'valid confirmation completes the transfer' );
        ok(
            $complete->content =~ /class="alert-box success\b/,
            'completion is displayed as a Foundation success alert'
        );
        ok( $complete->content =~ /successfully transferred 10 points/,
            'the result reports a completed transfer' );
        is( $complete->content =~ /An anonymous notification/ ? 1 : 0,
            $anonymous, 'the completion notice matches the anonymity choice' );
        ok( !form_inputs( $complete->content )->{confirm},
            'completion is not a confirmation form' );
        is(
            LJ::load_userid( $sender->id, 1 )->shop_points,
            20 - 10 * $anonymous,
            'the sender loses exactly 10 points'
        );
        is(
            LJ::load_userid( $recipient->id, 1 )->shop_points,
            10 + 10 * $anonymous,
            'the recipient gains exactly 10 points'
        );
    };
}

done_testing();
