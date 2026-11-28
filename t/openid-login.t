# t/openid-login.t
#
# Tests OpenID login discovery with a canned identity provider.
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

use HTTP::Request::Common;
use HTTP::Response;
use LWP::UserAgent::Paranoid;
use Plack::Test;
use Test::More;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $endpoint = 'https://provider.example/openid';
my $journal  = 'https://sample-user.livejournal.com/';
my $legacy   = 'https://users.livejournal.com/_sample_user/';
my $other    = 'http://sample-user.insanejournal.com/';

{
    no warnings 'redefine';
    my $get_useragent = \&LJ::get_useragent;
    local *LJ::get_useragent = sub {
        my %opts = @_;
        return $get_useragent->(@_) unless $opts{role} eq 'OpenID';
        my $ua = LWP::UserAgent::Paranoid->new;
        $ua->add_handler(
            request_send => sub {
                my ($request) = @_;
                my $url = $request->uri->as_string;
                return HTTP::Response->new(
                    200, 'OK',
                    [ 'Content-Type' => 'text/html' ],
                    qq{<html><head><link rel="openid.server" href="$endpoint"></head></html>}
                    )
                    if $request->method eq 'GET' && grep { $url eq $_ }
                    ( $journal, $legacy, $other );
                return HTTP::Response->new( 404, 'Not Found' );
            }
        );
        return $ua;
    };

    test_psgi $app, sub {
        my ($request) = @_;
        for my $case (
            [ 'http://sample-user.livejournal.com', $journal ],
            [ 'sample_user.livejournal.com',        $journal ],
            [ $journal,                             $journal ],
            [ $legacy,                              $legacy ],
            [ $other,                               $other ],
            )
        {
            my ( $input, $identity ) = @$case;
            my $response =
                $request->( POST 'http://localhost/openid/login', [ openid_url => $input ] );
            my $redirect = URI->new( $response->header('Location') // '' );
            my %params   = $redirect->can('query_form') ? $redirect->query_form : ();
            is( $params{'openid.identity'},
                $identity, "Login for $input requests the expected identity" );
        }
    };
}

done_testing;
