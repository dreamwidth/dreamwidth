#!/usr/bin/perl

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Lang;
use LJ::HTMLControls;

plan tests => 9;


use LJ::Setting::Gender;
use LJ::Setting::Name;

my $genkey = LJ::Setting::Gender->pkgkey;
my $namekey = LJ::Setting::Name->pkgkey;
is($genkey, "LJ__Setting__Gender_",     "key check");

my $u = LJ::load_user("system");

is(LJ::Setting->error_map($u, {}, ()), undef, "no errors for no settings");
is(LJ::Setting::Gender->error_map($u, {"${genkey}gender" => "U"}), undef, "no errors for gender with 'U'");
is(LJ::Setting::Gender->error_map($u, {"${genkey}gender" => "M"}), undef, "no errors for gender with 'M'");
isnt(LJ::Setting::Gender->error_map($u, {"${genkey}gender" => "X"}), undef, "errors for gender with 'X'");

{
    my @settings = qw(LJ::Setting::Name LJ::Setting::Gender);
    my $errmap;
    local $LJ::T_FAKE_SETTINGS_RULES = 1;
    my %post = (
                "${namekey}txt"  => "this is `bad",
                "${genkey}gender" => "M",
                );
    $errmap = LJ::Setting->error_map($u, \%post, @settings);
    ok($errmap, "got errors");

    my $html;
    $html = LJ::Setting::Name->as_html($u, $errmap, \%post);
    like($html, qr/this is .bad/, "got posted value back");
    like($html, qr/T-FAKE-ERROR/, "got inline error");

}

# and this time okay:
{
    my @settings = qw(LJ::Setting::Name LJ::Setting::Gender);
    my $errmap;
    my %post = (
                "${namekey}txt"  => "the system user",
                "${genkey}gender" => "M",
                );
    $errmap = LJ::Setting->error_map($u, \%post, @settings);
    ok(!$errmap, "no errors");
}

#    use Data::Dumper;
#    print Dumper($errmap);



