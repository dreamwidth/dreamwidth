#!/usr/bin/perl
#
# DW::Auth
#
# Alternate authentication styles
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Auth;
use strict;

use Digest::SHA1;
use MIME::Base64;

=head1 NAME

DW::Auth - Alternate authentication styles.

=head1 SYNOPSIS

=cut 

# this returns ( $u, $auth_method, @misc )

=head1 API

=head2 C<< $class->authenticate( %opts ) >>

Authentication methods ( specifiable by opts, in order of preference ):

All of the following can accept either 1 or a hashref of specific options.

=over
=item B< wsse >
WSSE

Acceptable options:

=over

=item B< allow_duplicate_nonce >

=back

=item B< digest >
HTTP Digest

=item B< remote >
Use the value of LJ::get_remote

=back

Additional options:

=over

=item B< _keep_remote >
Do not call LJ::set_remote with the authenticated user.

=back

=cut

sub authenticate {
    my ( $class, %opts ) = @_;

    my $r = DW::Request->get;
    my @fail_subs;

    my $ok = sub {
        my $u = shift;
        die 'Called $ok without valid $u' unless $u;
        LJ::set_remote($u) unless $opts{_keep_remote};
        return ( $u, @_ );
    };

    my $fail = sub {
        LJ::set_remote(undef) unless $opts{_keep_remote};
        $_->() foreach @fail_subs;
        return ( undef, @_ );
    };

    return ( undef, undef ) unless $r;

    if ( $opts{wsse} ) {
        my $nonce_dup;
        my $wsse = $r->header_in("X-WSSE");
        my ( $u, $fail_sub ) = _auth_wsse( $wsse, \$nonce_dup );
        push @fail_subs, $fail_sub if $fail_sub;
        my $_opts = {};
        $_opts = $opts{wsse} if ref $opts{wsse} eq 'HASH';
        return $fail->( 'wsse', 'wsse_nonce_duplicated' )
            if $nonce_dup && !$_opts->{allow_duplicate_nonce};
        return $ok->( $u, 'wsse' ) if $u;
    }
    if ( $opts{digest} ) {
        my ( $u, $fail_sub ) = _auth_basic();
        push @fail_subs, $fail_sub if $fail_sub;
        return $ok->( $u, 'digest' ) if $u;
    }
    if ( $opts{remote} ) {
        my $remote = LJ::get_remote();
        return $ok->( $remote, 'remote' ) if $remote;
    }

    return $fail->(undef);
}

sub _auth_wsse {
    my ( $wsse, $nonce_dup ) = @_;

    my $fail = sub {
        my $reason = shift;

        my $sv = sub {
            my $r = DW::Request->get;
            $r->header_out_add( "WWW-Authenticate",
                "WSSE realm=\"$LJ::SITENAMESHORT\", profile=\"UsernameToken\"" );
        };
        return ( undef, $sv );
    };

    $wsse =~ s/UsernameToken // or return $fail->('no username token');

    # parse credentials into a hash.
    my %creds;
    foreach ( split /, /, $wsse ) {
        my ( $k, $v ) = split '=', $_, 2;
        $v =~ s/^[\'\"]//;
        $v =~ s/[\'\"]$//;
        $v =~ s/=$// if $k =~ /passworddigest/i;    # strip base64 newline char
        $creds{ lc($k) } = $v;
    }

    # invalid create time?  invalid wsse.
    my $ctime = LJ::ParseFeed::w3cdtf_to_time( $creds{created} )
        or return $fail->("no created date");

    # prevent replay attacks.
    $ctime = LJ::mysqldate_to_time( $ctime, 'gmt' );
    return $fail->("replay time skew") if abs( time() - $ctime ) > 42300;

    my $u = LJ::load_user( LJ::canonical_username( $creds{username} ) )
        or return $fail->("invalid username [$creds{username}]");

    if ( @LJ::MEMCACHE_SERVERS && ref $nonce_dup ) {
        $$nonce_dup = 1
            unless LJ::MemCache::add( "wsse_auth:$creds{username}:$creds{nonce}", 1, 180 );
    }

    # validate hash
    my $hash = Digest::SHA1::sha1_base64( $creds{nonce} . $creds{created} . $u->password );

    # Nokia's WSSE implementation is incorrect as of 1.5, and they
    # base64 encode their nonce *value*.  If the initial comparison
    # fails, we need to try this as well before saying it's invalid.
    if ( $hash ne $creds{passworddigest} ) {
        $hash =
            Digest::SHA1::sha1_base64(
            MIME::Base64::decode_base64( $creds{nonce} ) . $creds{created} . $u->password );

        if ( $hash ne $creds{passworddigest} ) {
            LJ::handle_bad_login($u);
            return $fail->("hash wrong");
        }
    }

    return $fail->("ip_ratelimiting")
        if LJ::login_ip_banned($u);

    # If we're here, we're valid.
    return ( $u, undef );
}

sub _auth_basic {
    my $r = DW::Request->get;

    my $decline = sub {
        my $stale = shift;

        my $sv = sub {
            my $r = DW::Request->get;

            $r->header_out_add( "WWW-Authenticate", "Basic  realm=\"$LJ::SITENAMESHORT\"" );
        };
        return ( undef, $sv );
    };

    unless ( $r->header_in("Authorization") ) {
       return $decline->();
    }

    my $header = $r->header_in("Authorization");

    my ($authname, $val) = split( ' ', $header );

    # sanity checks
    unless ( $authname eq 'Basic')
    {
        return $decline->();
    }
    $val =~ s/=$//;    # strip base64 newline char
    my $decoded = MIME::Base64::decode_base64($val);

    my ($username, $password) = split(":", $decoded, 2);

    # the username
    my $user = LJ::canonical_username( $username );
    my $u    = LJ::load_user($user);

    return $decline->() unless $u;

    # don't allow empty passwords

    return $decline->() unless $u->password;

    return $decline->()
        unless $u->check_password( $password );

    return ( $u, undef );
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=item Afuna <coder.dw@afunamatata.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
