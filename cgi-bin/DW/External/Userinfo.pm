#!/usr/bin/perl
#
# DW::External::Userinfo - Methods for discovery of journal type
#                          for DW::External::User accounts.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::External::Userinfo;
use strict;

use Carp qw/ croak /;
use Storable qw/ nfreeze /;

use DW::External::Site;
use DW::Stats;

# timeout interval - to avoid hammering the remote site,
# wait 30 minutes before trying again for this user
sub wait { return 1800; }

sub agent {
    return LJ::get_useragent(
        role     => 'userinfo',
        agent    => "$LJ::SITENAME Userinfo; $LJ::ADMIN_EMAIL",
        max_size => 10240
    );
}

# CACHE METHODS

sub load {
    my ( $class, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';
    my $user = $u->user;
    my $site = $u->site->{siteid};

    # check memcache
    my $memkey = "ext_userinfo:$site:$user";
    my $data   = LJ::MemCache::get($memkey);
    return $data if defined $data;

    # check the database
    my $dbr = LJ::get_db_reader() or return undef;
    $data = $dbr->selectrow_array( "SELECT type FROM externaluserinfo WHERE user=?" . " AND site=?",
        undef, $user, $site );
    die $dbr->errstr if $dbr->err;

    if ( defined $data ) {
        LJ::MemCache::set( $memkey, $data );
    }
    else {    # rate limiting
        LJ::MemCache::set( $memkey, '', $class->wait );
    }

    # possible return values:
    # - the journaltype PYC (best case scenario)
    # - undef (not cached anywhere, go look for it)
    # - null string (timeout in memcache, need to wait)
    return $data;
}

sub timeout {

    # there are two layers of timeout protection.
    # we set a timeout in memcache for ext_userinfo
    # when we try to load the data for the user,
    # but we also set one in the database for persistence
    # (and for sites that might not be using memcache).
    # this function checks to see if the database timeout
    # is in effect, returning true if we need to wait more,
    # or false if it's OK to try to try loading again.
    # the assumption is that we already know if the memcache
    # check in the load method failed before calling here.

    my ( $class, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';
    my $user = $u->user;
    my $site = $u->site->{siteid};

    my $dbr = LJ::get_db_reader() or return undef;
    my $timeout =
        $dbr->selectrow_array( "SELECT last FROM externaluserinfo WHERE user=?" . " AND site=?",
        undef, $user, $site );
    die $dbr->errstr if $dbr->err;
    return 0 unless $timeout;

    # at this point, we've determined that there
    # is a timeout in the database, but we still
    # need to check and see if it's expired.

    my $time_remaining = $timeout + $class->wait - time;
    if ( $time_remaining > 0 ) {

        # timeout hasn't expired yet! we should notify memcache.
        my $memkey = "ext_userinfo:$site:$user";
        LJ::MemCache::set( $memkey, '', $time_remaining + 60 );
        return 1;
    }
    else {
        return 0;    # timeout expired
    }
}

sub save {
    my ( $class, $u, %opts ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';
    return undef unless %opts;
    my $user = $u->user;
    my $site = $u->site->{siteid};

    my $stat_tags = [ "username:$user", "site:" . DW::External::Site->get_site_by_id($site) ];

    my $memkey = "ext_userinfo:$site:$user";
    my $dbh    = LJ::get_db_writer() or return undef;

    if ( $opts{timeout} ) {
        $dbh->do( "REPLACE INTO externaluserinfo (user, site, last)" . " VALUES (?,?,?)",
            undef, $user, $site, $opts{timeout} );
        die $dbh->errstr if $dbh->err;
        LJ::MemCache::set( $memkey, '', $class->wait );
        DW::Stats::increment( 'dw.worker.extacct.failure', 1, $stat_tags );

    }
    elsif ( $opts{type} && $opts{type} =~ /^[PYC]$/ ) {

        # save as journaltype and clear any timeout
        $dbh->do( "REPLACE INTO externaluserinfo (user, site, type, last)" . " VALUES (?,?,?,?)",
            undef, $user, $site, $opts{type}, undef );
        die $dbh->errstr if $dbh->err;
        LJ::MemCache::set( $memkey, $opts{type} );
        DW::Stats::increment( 'dw.worker.extacct.success', 1, $stat_tags );

    }
    else {
        my $opterr = join ', ', map { "$_ => $opts{$_}" } keys %opts;
        croak "Bad values passed to DW::External::Userinfo->save: $opterr";
    }

    return 1;
}

# PARSE METHODS

sub parse_domain {
    my ( $class, $url ) = @_;
    return '' unless $url;
    my ($host) = $url =~ m@^https?://([^/]+)@;
    my @parts = split /\./, $host;
    return join '.', $parts[-2], $parts[-1];
}

sub is_offsite_redirect {
    my ( $class, $res, $url ) = @_;
    return 0 unless $res->previous;
    my $resurl = $res->previous->header('Location');
    if ( my $resdom = $class->parse_domain($resurl) ) {
        my $urldom = $class->parse_domain($url);
        return 1 if $resdom ne $urldom;
    }
}

sub atomtype {
    my ( $class, $atomurl ) = @_;
    return undef unless $atomurl;
    my $ua  = $class->agent;
    my $res = $ua->get($atomurl);
    return undef unless $res && $res->is_success;

    # check for redirects to a different domain
    # (this will catch offsite syndicated accounts)
    return 'feed' if $class->is_offsite_redirect( $res, $atomurl );

    # this is simple enough not to bother with an XML parser
    my $text = $res->content || '';

    # first look for lj.rossia.org - different from other LJ sites
    my ($ljr) =
        $text =~ m@<link rel='alternate' type='text/html' href='http://lj.rossia.org/([^/]+)@i;
    return $ljr if $ljr;    # community or users

    my ($str) = $text =~ m@<(?:lj|dw):journal ([^/]*)/>@i;
    return undef unless $str;

    my @attrs = split / /, $str;
    foreach (@attrs) {

        # look for type="journaltype"
        my ( $key, $val ) = split /=/;
        return substr( $val, 1, -1 ) if $key eq 'type';
    }                       # community / personal / news
}

sub title {
    my ( $class, $url ) = @_;
    return undef unless $url;
    my $ua  = $class->agent;
    my $res = $ua->get($url);
    return 'error' if $res   && $res->code == 404;    # non-exist
    return undef unless $res && $res->is_success;     # non-response

    my $text = $res->content || '';
    my ($title) = $text =~ m@<title>([^<]*)</title>@i;
    return lc $title;                                 # e.g. username - community profile
}

# REMOTE METHODS
# to be called from gearman worker (background processing)

sub check_remote {
    my ( $class, $u, $urlbase ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';
    my $site = $u->site;
    my $type;

    # translate to one-character journaltype codes
    my %type = (
        asylum     => 'C',    # InsaneJournal
        community  => 'C',
        feed       => 'Y',
        news       => 'C',
        personal   => 'P',
        syndicated => 'Y',
        user       => 'P',
        users      => 'P',
    );

    # invalid users don't always 404, so we also detect from title
    my %invalid = ( 'error' => 1, 'unknown journal' => 1 );

    my ( $profile, $feed );
    if ($urlbase) {
        $profile = $urlbase . 'profile';
        $feed    = $urlbase . 'data/atom';
    }
    else {    # beware recursion
        $profile = $site->profile_url($u);
        $feed    = $site->feed_url($u);
    }

    # Remote attempt 1/2: Check atom feed.
    unless ($type) {
        my $a = $class->atomtype($feed);
        $type = $type{$a} if $a && $type{$a};
    }

    # Remote attempt 2/2: Check the profile page title,
    # in case the site has nonstandard or nonexistent feeds.
    unless ($type) {
        if ( my $t = $class->title($profile) ) {
            return $class->save( $u, timeout => time + 3 * 86400 )    # 3 days
                if $invalid{$t};
            my $keys = join '|', sort keys %type;
            my ($w) = ( $t =~ /\b($keys)\b/ );
            $type = $type{$w} if $w && $type{$w};
        }
    }

    # If everything has failed, set a timeout.
    my %opts = $type ? ( type => $type ) : ( timeout => time );
    return $class->save( $u, %opts );
}

# JOURNALTYPE METHODS
# to be called from DW::External::Site

# determines the account type for this user on an lj-based site.
sub lj_journaltype {
    my ( $class, $u, $urlbase ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';
    croak 'need a valid username' unless $u->user;

    # try to load the journaltype from cache
    my $type = $class->load($u);
    return $type if $type;

    # if it's not cached, check remote if allowed
    if (
        LJ::is_enabled( 'extacct_info', $u->site ) &&    # allowed in config;
        !defined $type &&                                # load returned undef; go look for it
        !$class->timeout($u)
        )
    {                                                    # unless a timeout is in effect

        # ask gearman worker to do a lookup (calls check_remote)
        if ( my $gc = LJ::gearman_client() ) {
            my ( $user, $site ) = ( $u->user, $u->site->{domain} );
            my $args = { user => $user, site => $site, url => $urlbase };
            $gc->dispatch_background( 'resolve-extacct', nfreeze($args),
                { uniq => "$user\@$site" } );
        }
    }

    # default is to assume personal account
    return 'P';
}

1;
