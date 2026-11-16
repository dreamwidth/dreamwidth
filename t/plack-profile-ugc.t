# t/plack-profile-ugc.t
#
# Render real profiles to distinguish user-supplied destinations from controls.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::TokeParser;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user with_fake_memcache );
use DW::External::ProfileServices;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub set_creation_time {
    my ( $u, $time ) = @_;
    my $dbh = LJ::get_db_writer();
    $dbh->do( 'UPDATE userusage SET timecreate=FROM_UNIXTIME(?) WHERE userid=?',
        undef, $time, $u->id );
    die $dbh->errstr if $dbh->err;
    LJ::MemCache::delete( [ $u->id, 'tc:' . $u->id ] );
    delete $u->{_cache_timecreate};
}

with_fake_memcache {
    my $u = temp_user();
    $u->update_self( { status => 'A', allow_contactshow => 'Y' } );
    set_creation_time( $u, time - 11 * 86400 );
    $u->set_prop( url     => 'https://example.test/website?a=1&b=2' );
    $u->set_prop( urlname => 'UGC website & title' );
    $u->set_bio('<a href="https://example.test/bio" rel="nofollow">UGC bio</a>');

    my ($service) = grep { $_->{name} eq 'github' } @{ DW::External::ProfileServices->list };
    die 'GitHub profile service fixture missing' unless $service && $service->{url_format};
    $u->save_profile_accts( { $service->{service_id} => ['ugc-profile-test'] } );
    my $service_url = sprintf( $service->{url_format}, 'ugc-profile-test' );
    my %expected    = (
        'https://example.test/website?a=1&b=2' => 1,
        'https://example.test/bio'             => 1,
        $service_url                           => 1,
    );

    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET 'http://localhost/users/' . $u->user . '/profile?as=' . $u->user );
        is( $res->code, 200, 'real profile renders' );
        my $html = $res->content;
        like( $html, qr/UGC website &amp; title/, 'website label remains escaped' );
        my $p = HTML::TokeParser->new( \$html );
        my %found;
        my $controls = 0;

        while ( my $token = $p->get_tag('a') ) {
            my $a    = $token->[1];
            my $href = $a->{href} || '';
            my %rel  = map { lc($_) => 1 } split /\s+/, $a->{rel} || '';
            if ( $expected{$href} ) {
                $found{$href}++;
                ok( $rel{ugc},      "$href marked as UGC" );
                ok( $rel{nofollow}, "$href keeps nofollow" );
            }
            else {
                ok( !$rel{ugc}, "$href is not a user-supplied destination" );
                $controls++ if $href =~ m{/manage/profile};
            }
        }
        is_deeply( [ sort keys %found ], [ sort keys %expected ], 'all authored links rendered' );
        ok( $controls, 'profile edit control still present for owner' );

        set_creation_time( $u, time );
        $res = $cb->( GET 'http://localhost/users/' . $u->user . '/profile?as=nobody_exists' );
        is( $res->code, 200, 'new account profile renders for a stranger' );
        unlike(
            $res->content,
            qr{https://example\.test/website},
            'website age restriction still enforced'
        );
    };
};

done_testing();
