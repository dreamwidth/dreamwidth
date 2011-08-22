# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Test qw(temp_user);
use LJ::BetaFeatures;

my $u = LJ::Test::temp_user();

{
    ok(ref LJ::BetaFeatures->get_handler('foo') eq 'LJ::BetaFeatures::default', "instantiated default handler");
}

{
    ok(! $u->in_class('betafeatures'), "cap not set");
    ok(! defined $u->prop('betafeatures_list'), "prop not set");

    LJ::BetaFeatures->add_to_beta($u => 'foo');
    ok($u->in_class('betafeatures'), "cap set after add");
    ok($u->prop('betafeatures_list') eq 'foo', 'prop set after add');

    LJ::BetaFeatures->add_to_beta($u => 'foo');
    ok($u->prop('betafeatures_list') eq 'foo', 'no dup');

    ok(LJ::BetaFeatures->user_in_beta($u => 'foo'), "user_in_beta true");

    $u->prop('betafeatures_list' => 'foo,foo,foo');
    ok(LJ::BetaFeatures->user_in_beta($u => 'foo'), "user_in_beta true with dups");

    ok($u->prop('betafeatures_list') eq 'foo', "no more dups");

    $LJ::BETA_FEATURES{foo}->{end_time} = 0;
    ok(! LJ::BetaFeatures->user_in_beta($u => 'foo'), "expired");
    ok(! $u->in_class('betafeatures'), "cap unset");
    ok(! defined $u->prop('betafeatures_list'), "prop no longer defined");

    # FIXME: more!
    # -- BetaFeatures::t_handler dies unless $LJ::T_FOO ?
}
