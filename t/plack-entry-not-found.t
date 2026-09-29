# t/plack-entry-not-found.t
#
# Entry URLs must not reveal whether a hidden entry exists.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner    = temp_user();
my $stranger = temp_user();
my $public   = $owner->t_post_fake_entry( body => 'PUBLIC_MARKER' );
my $private  = $owner->t_post_fake_entry( body => 'PRIVATE_MARKER', security => 'private' );
$private->slug('hidden-slug');
my $date = substr( $private->eventtime_mysql, 0, 10 );
$date =~ s!-!/!g;

my $base    = 'http://localhost/users/' . $owner->user;
my $missing = ( $private->jitemid + 100 ) * 256 + 1;
my $wrong   = ( $public->jitemid << 8 ) + ( ( $public->anum + 1 ) % 256 );
my @hidden  = (
    '/' . $private->ditemid . '.html', "/$missing.html",
    "/$wrong.html",                    "/$date/hidden-slug.html",
    "/$date/no-such-slug.html",        '/' . $private->ditemid . '.html?mode=reply',
    "/$missing.html?mode=reply",
);

# Per-request form tokens and the requested URL (in returnto links) legitimately
# differ, and Perl's hash order shuffles attributes, JSON keys and query args, so
# compare each line's tokens.
sub normalized {
    my ($body) = @_;
    $body =~ s!/users/\Q${\ $owner->user }\E/[^"'\s]*!RETURNTO!g;
    $body =~ s/(name="lj_form_auth" value=")[^"]*/$1/g;
    return join "\n", map { join ' ', sort split /[\s,{}]+/ } split /\n/, $body;
}

# Test DBs do not install S2 styles; the stub marks where rendering would start.
my $renders = 0;
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::make_journal = sub { $renders++; return 'JOURNAL_RENDERED' };

    test_psgi $app, sub {
        my $cb = shift;

        for my $as ( 'nobody_exists', $stranger->user ) {
            my $reference;
            for my $path (@hidden) {
                my $url = $base . $path . ( $path =~ /\?/ ? '&' : '?' ) . "as=$as";
                my $res = $cb->( GET $url );
                is( $res->code, 404, "$as: $path is 404" );
                unlike(
                    $res->content,
                    qr/PRIVATE_MARKER|PUBLIC_MARKER|JOURNAL_RENDERED/,
                    "$as: $path shows no entry"
                );
                my $body = normalized( $res->content );
                $reference //= $body;
                is( $body, $reference, "$as: $path matches the other hidden URLs" );
            }
        }
        is( $renders, 0, 'hidden entries never reach the journal renderer' );

        # The adult interstitial would otherwise answer for any URL it can resolve.
        local $LJ::DISABLED{adult_content} = 0;
        $owner->set_prop( adult_content => 'explicit' );
        for my $path (@hidden) {
            my $res =
                $cb->( GET $base . $path . ( $path =~ /\?/ ? '&' : '?' ) . 'as=nobody_exists' );
            is( $res->code, 404, "adult journal: $path is 404, not the interstitial" );
        }
        $owner->set_prop( adult_content => 'none' );

        for my $path ( '/' . $private->ditemid . '.html', "/$date/hidden-slug.html" ) {
            my $res = $cb->( GET $base . $path . '?as=' . $owner->user );
            is( $res->code, 200, "owner: $path renders" );
            like( $res->content, qr/JOURNAL_RENDERED/, "owner: $path reaches the renderer" );
        }
    };
};

done_testing();
