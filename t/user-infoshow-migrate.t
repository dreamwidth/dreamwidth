#!/usr/bin/perl

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';


plan tests => 228;

use LJ::Test qw(temp_user memcache_stress);

$LJ::DISABLED{infoshow_migrate} = 0;

sub new_temp_user {
    my $u = temp_user();
    ok(LJ::isu($u), 'temp user created');

    # force it to Y, since we're testing migration here
    $u->update_self( { allow_infoshow => 'Y' } );
    $u->clear_prop("opt_showlocation");
    $u->clear_prop("opt_showbday");

    is($u->{'allow_infoshow'}, 'Y', 'allow_infoshow set to Y');
    ok(! defined $u->{'opt_showbday'}, 'opt_showbday not set');
    ok(! defined $u->{'opt_showlocation'}, 'opt_showlocation not set');

    return $u;
}

sub run_tests {
    foreach my $getter (
            sub { $_[0]->prop('opt_showbday') },
            sub { $_[0]->prop('opt_showlocation') },
            sub { $_[0]->opt_showbday },
            sub { $_[0]->opt_showlocation } )
    {
        foreach my $mode (qw(default off)) {
            my $u = new_temp_user();
            if ($mode eq 'off') {
                my $uid = $u->{userid};
                $u->update_self( { allow_infoshow => 'N' } );
                is($u->{allow_infoshow}, 'N', 'allow_infoshow set to N');

                my $temp_var = $getter->($u);
                is($temp_var, 'N', "prop value after migration: 'N'");
                is($u->{'allow_infoshow'}, ' ', 'lazy migrate: allow_infoshow set to SPACE');
                is($u->{'opt_showbday'}, 'N', 'lazy_migrate: opt_showbday set to N');
                is($u->{'opt_showlocation'}, 'N', 'lazy_migrate: opt_showlocation set to N');
            } else {
                my $temp_var = $getter->($u);
                ok(defined $temp_var, "prop value after migration: defined");
                is($u->{'allow_infoshow'}, ' ', 'lazy migrate: allow_infoshow set to SPACE');
                is($u->{'opt_showbday'}, undef, 'lazy_migrate: opt_showbday unset');
                is($u->opt_showbday, 'D', "lazy_migrate: opt_showbday returned as D");
                is($u->{'opt_showlocation'}, undef, 'lazy_migrate: opt_showlocation unset');
                is($u->opt_showlocation, 'Y', "lazy_migrate: opt_showlocation set as Y");
            }
        }
    }

}

memcache_stress {
    run_tests;
}
