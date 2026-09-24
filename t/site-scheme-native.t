#!/usr/bin/perl
# Locks two properties E3's engine deletion must preserve: every selectable
# DW::SiteScheme supports_tt and none has the bml engine, and rendering a
# native page through DW::Template never touches BML. Deliberately does not
# assume the internal tt_runner scheme or its bml engine still exist by name
# -- only what a real visitor can select is asserted, so this keeps passing
# whether or not E3 also removes that internal-only scheme.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use DW::SiteScheme;
use DW::Template;
use LJ::Widget::Search;

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        }
    );
}

subtest 'every selectable site scheme supports_tt, and none has the bml engine' => sub {
    request();
    my @available = DW::SiteScheme->available;
    ok( scalar(@available) > 0, 'at least one scheme is selectable' );
    for my $row (@available) {
        my $scheme = DW::SiteScheme->get( $row->{scheme} );
        ok( $scheme->supports_tt, "$row->{scheme} supports_tt" );
        isnt( $scheme->engine, 'bml', "$row->{scheme} does not have the bml engine" );
    }
};

subtest 'rendering a native page through DW::Template never touches BML' => sub {
    request();
    no warnings 'redefine';
    local *BML::ml         = sub { die 'native TT rendering must not call BML::ml' };
    local *DW::BML::render = sub { die 'native TT rendering must not call DW::BML::render' };

    my $ok = eval { DW::Template->render_string('native rendering marker text'); 1 };
    ok( $ok, 'render_string completes without calling BML::ml or DW::BML::render' )
        or diag("died: $@");
    ok( DW::Request->get->response_bytes_written, 'render_string actually produced a body' );
};

done_testing;
