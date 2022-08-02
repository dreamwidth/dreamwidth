#!/usr/bin/perl
#
# DW::Auth::Challenge
#
# Library for dealing with challenge/response type authentication patterns.
# Basic idea is that we can generate challenges which can be used to ensure
# an action is being performed by the user who was given the challenge,
# in the same session, and only once.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Auth::Challenge;

use strict;
use v5.10;
use Log::Log4perl;
use Digest::MD5;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::Utils qw(rand_chars);

################################################################################
#
# public methods
#

# Validate a challenge string previously supplied by generate
# return 1 "good" 0 "bad", plus sets keys in $opts:
# 'valid'=1/0 whether the string itself was valid
# 'expired'=1/0 whether the challenge expired, provided it's valid
# 'count'=N number of times we've seen this challenge, including this one,
#           provided it's valid and not expired
# $opts also supports in parameters:
#   'dont_check_count' => if true, won't return a count field
# the return value is 1 if 'valid' and not 'expired' and 'count'==1
sub check {
    my ( $class, $chal, $opts ) = @_;
    my ( $valid, $expired, $count ) = ( 1, 0, 0 );

    my ( $c_ver, $stime, $s_age, $goodfor, $rand, $chalsig ) = split /:/, $chal;
    my $secret   = LJ::get_secret($stime);
    my $chalbare = "$c_ver:$stime:$s_age:$goodfor:$rand";

    # Validate token
    $valid = 0
        unless $secret && $c_ver eq 'c0';    # wrong version
    $valid = 0
        unless Digest::MD5::md5_hex( $chalbare . $secret ) eq $chalsig;

    $expired = 1
        unless ( not $valid )
        or time() - ( $stime + $s_age ) < $goodfor;

    # Check for token dups
    if ( $valid && !$expired && !$opts->{dont_check_count} ) {
        if (@LJ::MEMCACHE_SERVERS) {
            $count = LJ::MemCache::incr( "chaltoken:$chal", 1 );
            unless ($count) {
                LJ::MemCache::add( "chaltoken:$chal", 1, $goodfor );
                $count = 1;
            }
        }
        else {
            my $dbh = LJ::get_db_writer();
            my $rv  = $dbh->do( q{SELECT GET_LOCK(?,5)}, undef, Digest::MD5::md5_hex($chal) );
            if ($rv) {
                $count = $dbh->selectrow_array( q{SELECT count FROM challenges WHERE challenge=?},
                    undef, $chal );
                if ($count) {
                    $dbh->do( q{UPDATE challenges SET count=count+1 WHERE challenge=?},
                        undef, $chal );
                    $count++;
                }
                else {
                    $dbh->do( q{INSERT INTO challenges SET ctime=?, challenge=?, count=1},
                        undef, $stime + $s_age, $chal );
                    $count = 1;
                }
            }
            $dbh->do( q{SELECT RELEASE_LOCK(?)}, undef, $chal );
        }

        # if we couldn't get the count (means we couldn't store either)
        # , consider it invalid
        $valid = 0 unless $count;
    }

    if ($opts) {
        $opts->{expired} = $expired;
        $opts->{valid}   = $valid;
        $opts->{count}   = $count;
    }

    return ( $valid && !$expired && ( $count == 1 || $opts->{dont_check_count} ) );
}

# Create a challenge token, used by a couple of systems that need to be able to
# guarante something is being performed by the same user/session/only once.
sub generate {
    my ( $class, $goodfor, $attr ) = @_;

    $goodfor ||= 60;
    $attr    ||= LJ::rand_chars(20);

    my ( $stime, $secret ) = LJ::get_secret();

    # challenge version, secret time, secret age, time in secs token is good for, random chars.
    my $s_age    = time() - $stime;
    my $chalbare = "c0:$stime:$s_age:$goodfor:$attr";
    my $chalsig  = Digest::MD5::md5_hex( $chalbare . $secret );
    my $chal     = "$chalbare:$chalsig";

    return $chal;
}

# Return challenge info.
# This could grow later - for now just return the rand chars used.
sub get_attributes {
    my ( $class, $chal ) = @_;
    return ( split /:/, $chal )[4];
}

################################################################################
#
# internal methods
#

1;
