# t/openid-identity.t
#
# Test LJ::OpenID::is_identity, which decides whether the logged-in user can
# vouch for the OpenID identity URL a relying party asks about.
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

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use LJ::OpenID;

my $u     = temp_user();
my $other = temp_user();

# build an identity URL for $who's journal, optionally with an explicit port
sub ident {
    my ( $who, $port ) = @_;
    my ( $scheme, $host, $path ) = $who->journal_base =~ m!^(https?)://([^/]+)(.*)$!
        or die "unexpected journal_base: " . $who->journal_base;
    $host .= ":$port" if defined $port;
    return "$scheme://$host$path/";
}

foreach my $protocol (qw( http https )) {
    local $LJ::PROTOCOL = $protocol;
    my $default = $protocol eq 'https' ? 443 : 80;
    my $wrong   = $protocol eq 'https' ? 80  : 443;

    ok( LJ::OpenID::is_identity( $u, ident($u) ), "$protocol: own journal URL is accepted" );
    ok( LJ::OpenID::is_identity( $u, ident( $u, $default ) ),
        "$protocol: own journal URL with default port $default is accepted" );
    ok(
        !LJ::OpenID::is_identity( $u, ident( $u, $wrong ) ),
        "$protocol: own journal URL with port $wrong is refused"
    );
    ok(
        !LJ::OpenID::is_identity( $u, ident( $u, 8443 ) ),
        "$protocol: own journal URL with port 8443 is refused"
    );
    ok(
        !LJ::OpenID::is_identity( $u, ident( $other, $default ) ),
        "$protocol: another user's journal URL with default port is refused"
    );
}

{
    local $LJ::PROTOCOL = 'https';
    my $ident = ident( $u, 443 );
    $ident =~ s!/$!!;
    ok( LJ::OpenID::is_identity( $u, $ident ),
        "default port is accepted without a trailing slash" );
}
