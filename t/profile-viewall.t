#!/usr/bin/perl
#
# t/profile-viewall.t
#
# Suspended/deleted profile access, public-only contact visibility, and auditing.
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
use HTTP::Request;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use DW::Controller::Profile;
use DW::Request::Standard;
use DW::External::ProfileServices;

with_fake_memcache {
    my $owner     = temp_user();
    my $ordinary  = temp_user();
    my $limited   = temp_user();
    my $full      = temp_user();
    my $unrelated = temp_user();
    my $admin     = temp_user();

    ok( $limited->grant_priv( canview => 'suspended' ), 'grant restricted viewing privilege' );
    ok( $full->grant_priv( canview => '*' ),            'grant wildcard viewing privilege' );
    ok( $unrelated->grant_priv( canview => 'other' ),   'grant unrelated canview argument' );
    ok( $admin->grant_priv( admin => '*' ),             'grant administration without canview' );
    ok( !$limited->has_priv( canview => '*' ),          'restricted viewer has no wildcard' );

    $owner->add_edge( $limited, trust => { nonotify => 1 } );
    ok( $owner->trusts($limited), 'restricted viewer is independently trusted' );
    $owner->set_bio('PUBLIC_PROFILE_MARKER');
    $owner->set_prop( opt_whatemailshow => 'D' );
    $owner->set_prop( opt_profileemail  => 'profile-viewall@example.invalid' );
    $owner->set_prop( city              => 'PROFILE_CITY_MARKER' );
    $owner->set_prop( opt_showlocation  => 'Y' );
    $owner->set_prop( opt_sharebday     => 'A' );
    $owner->set_prop( opt_showbday      => 'F' );
    $owner->update_self( { bdate => '1980-02-03', allow_contactshow => 'Y' } );

    my ($service) = @{ DW::External::ProfileServices->list };
    BAIL_OUT('test database must contain profile services') unless $service;
    ok( $owner->save_profile_accts( { $service->{service_id} => ['PROFILE_SERVICE_MARKER'] } ),
        'save external contact fixture' );

    my $request;
    my $remote;
    no warnings 'redefine';
    local *DW::Request::get = sub { $request };
    local *LJ::get_remote   = sub { $remote };
    local *DW::Controller::Profile::controller = sub {
        return ( 1, { r => $request, remote => $remote } );
    };
    local *LJ::need_res = sub { };

    # Keep the real controller, user permissions, profile logic, and audit writes.
    # Stop at the rendering boundary so template/layout dependencies do not obscure
    # which data is authorized for the renderer.
    local *DW::Template::render_template = sub {
        return { template => $_[1], vars => $_[2] };
    };
    local *DW::Template::render_template_misc = sub {
        return { template => $_[1], vars => $_[2] };
    };

    my $audit_rows = sub {
        return LJ::get_db_writer()->selectall_arrayref(
            "SELECT adminid, notes FROM statushistory WHERE userid=? AND shtype='viewall'",
            { Slice => {} },
            $owner->id
        );
    };

    my $visit = sub {
        my ( $viewer, $flag ) = @_;
        $remote = $viewer;
        my $url = URI->new( $owner->profile_url );
        $url->query_form(
            user => $owner->user,
            ( defined $flag ? ( viewall => $flag ) : () )
        );
        my $http = HTTP::Request->new( GET => $url );
        $http->header( Host => $url->authority );
        local $DW::Request::cur_req;
        $request = DW::Request::Standard->new($http);
        return DW::Controller::Profile::profile_handler();
    };

    my @viewers = (
        [ anonymous => undef,      0, 0 ],
        [ ordinary  => $ordinary,  0, 0 ],
        [ suspended => $limited,   1, 0 ],
        [ wildcard  => $full,      1, 1 ],
        [ unrelated => $unrelated, 0, 0 ],
        [ admin     => $admin,     0, 0 ],
    );

    for my $status (qw(V S D X)) {
        $owner->update_self( { statusvis => $status } );
        for my $viewer (@viewers) {
            my ( $name, $u, $can_view, $can_override ) = @$viewer;
            for my $flag ( undef, 0, 1 ) {
                my $label = defined $flag ? $flag : 'absent';
                subtest "$status, $name, viewall=$label" => sub {
                    my $before  = scalar @{ $audit_rows->() };
                    my $result  = $visit->( $u, $flag );
                    my $allowed = $status eq 'V'
                        || ( $status ne 'X' && $flag && $can_view );
                    is(
                        $result->{template} eq 'profile/main.tt' ? 1 : 0,
                        $allowed                                 ? 1 : 0,
                        'profile reaches rendering only when authorized'
                    );
                    my $rows    = $audit_rows->();
                    my $audited = $status ne 'X' && $flag && $can_view;
                    is( scalar @$rows - $before, $audited ? 1 : 0, 'exact audit row count' );
                    if ($audited) {
                        my $notes = 'profile: ' . $owner->user . ", statusvis: $status";
                        my @matching =
                            grep { $_->{adminid} == $u->id && $_->{notes} eq $notes } @$rows;
                        ok( @matching, 'audit records viewer, profile owner, and status' );
                    }
                    if ($allowed) {
                        my $profile = $result->{vars}{profile};
                        ok( $profile, 'authorized profile data is available' );
                        return unless $profile;
                        like( $profile->bio, qr/PUBLIC_PROFILE_MARKER/, 'public bio is available' );
                        is(
                            $profile->{viewall}    ? 1 : 0,
                            $flag && $can_override ? 1 : 0,
                            'only wildcard privilege enables private-content override'
                        );
                    }
                };
            }
        }
    }

    for my $status (qw(S D)) {
        $owner->update_self( { statusvis => $status } );
        for my $visibility (qw(Y R F N)) {
            $owner->update_self( { allow_contactshow => $visibility } );
            subtest "$status restricted contact visibility $visibility" => sub {
                my $result = $visit->( $limited, 1 );
                is( $result->{template}, 'profile/main.tt', 'restricted viewer reaches profile' );
                my $profile = $result->{vars}{profile};
                return unless $profile;
                my @emails = map { $_->{email} || () } @{ $profile->contact_rows };
                is_deeply(
                    \@emails,
                    $visibility eq 'Y' ? ['profile-viewall@example.invalid'] : [],
                    'only publicly shared email is available, even to a trusted viewer'
                );
                is(
                    scalar @{ $profile->external_services },
                    $visibility eq 'Y' ? 1 : 0,
                    'only publicly shared external contacts are available'
                );
            };

            subtest "$status wildcard contact visibility $visibility" => sub {
                my $result = $visit->( $full, 1 );
                is( $result->{template}, 'profile/main.tt', 'wildcard viewer reaches profile' );
                my $profile = $result->{vars}{profile};
                return unless $profile;
                is( scalar @{ $profile->external_services },
                    1, 'wildcard retains the existing external-contact security override' );
            };
        }

        $owner->set_prop( opt_sharebday    => 'A' );
        $owner->set_prop( opt_showlocation => 'Y' );
        subtest "$status public personal information" => sub {
            my $result  = $visit->( $limited, 1 );
            my $profile = $result->{vars}{profile};
            ok( $profile, 'restricted viewer reaches profile' );
            return unless $profile;
            ok( @{ $profile->_basic_info_birthday }, 'public birthday remains available' );
            ok( @{ $profile->_basic_info_location }, 'public location remains available' );
        };

        for my $visibility (qw(R F N)) {
            $owner->set_prop( opt_sharebday    => $visibility );
            $owner->set_prop( opt_showlocation => $visibility );
            subtest "$status restricted personal information $visibility" => sub {
                my $result  = $visit->( $limited, 1 );
                my $profile = $result->{vars}{profile};
                ok( $profile, 'restricted viewer reaches profile' );
                return unless $profile;
                is_deeply( $profile->_basic_info_birthday, [], 'nonpublic birthday is hidden' );
                is_deeply( $profile->_basic_info_location, [], 'nonpublic location is hidden' );
            };
        }
    }

    subtest 'visible accounts retain ordinary contact access' => sub {
        $owner->update_self( { statusvis => 'V' } );
        for my $visibility (qw(Y R F N)) {
            $owner->update_self( { allow_contactshow => $visibility } );
            my $result  = $visit->( $limited, 1 );
            my $profile = $result->{vars}{profile};
            ok( $profile, 'visible profile remains available' );
            next unless $profile;
            is(
                scalar @{ $profile->external_services },
                $visibility ne 'N' ? 1 : 0,
                "$visibility keeps ordinary logged-in/trusted access on visible accounts"
            );
        }
    };
};

done_testing;
