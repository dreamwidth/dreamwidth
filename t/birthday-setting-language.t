#!/usr/bin/perl
# Native language regression coverage for the Birthday setting.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use LJ::Setting::Birthday;

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
        },
    );
}

sub error_for {
    my ( $args, $field ) = @_;
    my $ok = eval { LJ::Setting::Birthday->error_check( undef, $args ); 1 };
    ok( !$ok, "invalid birthday has a $field error" );
    my $error = $@;
    isa_ok( $error, 'LJ::Error::SettingSave', 'Birthday returns a setting error object' );
    return $error->field('map')->{$field};
}

subtest 'validation errors use physical profile template keys despite unrelated request scope' =>
    sub {
    request()->note( ml_scope => '/unrelated.tt' );
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'custom-a',
        getter => sub {
            my ( $lang, $code ) = @_;
            push @calls, [ $lang, $code ];
            return "$lang:$code";
        },
    );

    is(
        error_for( { year => 99 }, 'year' ),
        'custom-a:/manage/profile.tt.error.year.notenoughdigits',
        'short year uses the physical profile template key'
    );
    is(
        error_for( { year => 1800 }, 'year' ),
        'custom-a:/manage/profile.tt.error.year.outofrange',
        'out-of-range year uses the physical profile template key'
    );
    is(
        error_for( { month => 13 }, 'month' ),
        'custom-a:/manage/profile.tt.error.month.outofrange',
        'out-of-range month uses the physical profile template key'
    );
    is(
        error_for( { month => 2, day => 31 }, 'day' ),
        'custom-a:/manage/profile.tt.error.day.notinmonth',
        'invalid day in month uses the physical profile template key'
    );
    is_deeply(
        [ map { $_->[1] } @calls ],
        [
            '/manage/profile.tt.error.year.notenoughdigits',
            '/manage/profile.tt.error.year.outofrange',
            '/manage/profile.tt.error.month.outofrange',
            '/manage/profile.tt.error.day.notinmonth',
        ],
        'every validation error bypasses the unrelated request scope'
    );
    };

subtest 'sequential request contexts and default language remain isolated' => sub {
    request()->note( ml_scope => '/wrong.tt' );
    LJ::Lang::set_request_context( lang => 'first', getter => sub { return "first:$_[1]"; } );
    is(
        error_for( { day => 32 }, 'day' ),
        'first:/manage/profile.tt.error.day.outofrange',
        'first request getter handles day validation'
    );

    request()->note( ml_scope => '/also-wrong.tt' );
    LJ::Lang::set_request_context( lang => 'second', getter => sub { return "second:$_[1]"; } );
    is(
        error_for( { month => 13 }, 'month' ),
        'second:/manage/profile.tt.error.month.outofrange',
        'second request cannot inherit the first request getter'
    );

    request();
    LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
    is(
        error_for( { day => 32 }, 'day' ),
        'Invalid date.  Enter a day from 1-31.',
        'default getter returns the existing profile error text'
    );
    DW::Request->reset;
};

done_testing;
