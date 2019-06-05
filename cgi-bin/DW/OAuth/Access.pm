#!/usr/bin/perl
#
# DW::OAuth
#
# OAuth Access
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::OAuth::Access;
use strict;
use warnings;

use DW::OAuth;

sub from_token {
    my ( $class, $token ) = @_;
    return undef unless $token;
    return $LJ::REQUEST_CACHE{oauth_access}{$token} if $LJ::REQUEST_CACHE{oauth_access}{$token};
    return undef unless DW::OAuth->validate_token($token);

    {
        my $ar = LJ::MemCache::get( [ $token, "oauth_access_token:" . $token ] );
        return $class->from_consumer( $ar->[0], $ar->[1] ) if $ar && scalar(@$ar) == 2;
    }

    return $class->_load_raw( token => $token );
}

sub from_consumer {
    my ( $class, $uid, $cid ) = @_;
    $uid = LJ::want_userid($uid);
    $cid = DW::OAuth::Consumer->want_id($cid);

    return undef unless $uid && $cid;
    return $LJ::REQUEST_CACHE{oauth_access}{"$uid:$cid"}
        if $LJ::REQUEST_CACHE{oauth_access}{"$uid:$cid"};

    {
        my $ar  = LJ::MemCache::get( [ $uid, join( ":", "oauth_access", $uid, $cid ) ] );
        my $row = $ar ? LJ::MemCache::array_to_hash( "oauth_access", $ar ) : undef;
        return $class->new_from_row($row) if $row;
    }

    return $class->_load_raw( userid => $uid, consumer_id => $cid );
}

sub want {
    my ( $class, $thing ) = @_;

    return undef unless $thing;
    return $thing if ref $thing eq $class;
    return $class->from_token($thing);
}

sub tokens_for_user {
    my ( $class, $u ) = @_;
    my $userid = LJ::want_userid($u);

    return [] unless $userid;

    my @ret;

    my @ids;
    my $memkey = [ $userid, "user_oauth_access:" . $userid ];
    my $data   = LJ::MemCache::get($memkey);

    if ($data) {
        @ids = @$data;
    }
    else {
        my $dbr = LJ::get_db_reader() or die "Failed to get database";
        my $sth = $dbr->prepare("SELECT consumer_id FROM oauth_access_token WHERE userid = ?")
            or die $dbr->errstr;
        $sth->execute( $u->userid ) or die $dbr->errstr;

        while ( my ($id) = $sth->fetchrow_array ) {
            push @ids, $id;
        }

        LJ::MemCache::set( $memkey, \@ids );
    }

    foreach my $id (@ids) {
        push @ret, $class->from_consumer( $userid, $id );
    }

    return \@ret;
}

# This is not cached.
sub tokens_for_consumer {
    my ( $class, $c ) = @_;

    return [] unless $c;
    my $consumer_id = $c->id;

    my @ret;

    my @ids;

    my $dbr = LJ::get_db_reader() or die "Failed to get database";
    my $sth = $dbr->prepare("SELECT userid FROM oauth_access_token WHERE consumer_id = ?")
        or die $dbr->errstr;
    $sth->execute($consumer_id) or die $dbr->errstr;

    while ( my ($id) = $sth->fetchrow_array ) {
        push @ids, $id;
    }

    foreach my $id (@ids) {
        push @ret, $class->from_consumer( $id, $consumer_id );
    }

    return \@ret;
}

sub _clear_user_tokens {
    LJ::MemCache::delete( [ $_[1], "user_oauth_access:" . $_[1] ] );
}

sub _delete_cache {
    my ($c) = @_;

    LJ::MemCache::delete( [ $c->token, "oauth_access_token:" . $c->token ] );
    LJ::MemCache::delete(
        [ $c->userid, join( ":", "oauth_access", $c->userid, $c->consumer_id ) ] );

    delete $LJ::REQUEST_CACHE{oauth_access}{ $c->token };
    delete $LJ::REQUEST_CACHE{oauth_access}{ $c->userid . ":" . $c->consumer_id };
}

sub _load_raw {
    my ( $class, %args ) = @_;

    my @keys = sort keys %args;
    my $data = join " AND ", map { "$_ = ?" } @keys;

    my $dbr = LJ::get_db_reader() or die "Failed to get database";
    my $sth = $dbr->prepare(
        "SELECT consumer_id, userid, token, secret, createtime FROM oauth_access_token WHERE $data")
        or die $dbr->errstr;
    $sth->execute( map { $args{$_} } @keys ) or die $dbr->errstr;
    my $row = $sth->fetchrow_hashref;
    return $row ? $class->new_from_row($row) : undef;
}

sub new {
    my ( $class, $request, %opts ) = @_;

    my $r = DW::OAuth::Request->want($request);
    die "Invalid request token" unless $r && $r->usable;
    my $c = $r->consumer;

    $opts{consumer_id} = $c->id;
    $opts{userid}      = $r->userid;

    # Required.
    die "Missing required parameter" unless $opts{userid} && $opts{consumer_id};

    my $c_tkn = $class->from_consumer( $opts{userid}, $opts{consumer_id} );
    return $c_tkn if $c_tkn;

    my ( $token, $secret ) = DW::OAuth->make_token_pair('access');

    $opts{token}  = $token;
    $opts{secret} = $secret;

    my $dbh = LJ::get_db_writer();
    $dbh->do(
"INSERT INTO oauth_access_token (consumer_id, userid, token, secret, createtime, lastaccess) VALUES (?,?,?,?,?,?)",
        undef,
        $opts{consumer_id},
        $opts{userid},
        $opts{token},
        $opts{secret},
        time(),
        time()
    ) or die $dbh->errstr;

    $class->_clear_user_tokens( $opts{userid} );

    return $class->from_token( $opts{token} );
}

sub new_from_row {
    my ( $class, $row ) = @_;

    my $c = bless $row, $class;

    my $expire = time() + 1800;

    if ( $c->token ) {
        LJ::MemCache::set( [ $c->token, "oauth_access_token:" . $c->token ],
            [ $c->userid, $c->consumer_id ], $expire );
        $LJ::REQUEST_CACHE{oauth_access}{ $c->token } = $c;
    }

    my $ar = LJ::MemCache::hash_to_array( "oauth_access", $c );
    LJ::MemCache::set( [ $c->userid, join( ":", "oauth_access", $c->userid, $c->consumer_id ) ],
        $ar, $expire );
    $LJ::REQUEST_CACHE{oauth_access}{ $c->userid . ":" . $c->consumer_id } = $c;

    return $c;
}

sub consumer_id {
    return $_[0]->{consumer_id};
}

sub consumer {
    return DW::OAuth::Consumer->from_id( $_[0]->consumer_id );
}

sub userid {
    return $_[0]->{userid};
}

sub user {
    return $_[0]->userid ? LJ::load_userid( $_[0]->userid ) : undef;
}

sub token {
    return $_[0]->{token};
}

sub secret {
    return $_[0]->{secret};
}

sub createtime {
    return $_[0]->{createtime};
}

sub lastaccess {
    my $self = $_[0];
    unless ( exists $self->{lastaccess} ) {
        DW::OAuth::Access->load_all_lastaccess( [$self] );
    }
    return $self->{lastaccess};
}

sub load_all_lastaccess {
    my ( $class, $tokens ) = @_;

    my %userids;

    foreach my $token (@$tokens) {
        $userids{ $token->userid }->{ $token->consumer_id } = $token;
    }

    my $dbr = LJ::get_db_reader() or die 'Failed to get database';

    foreach my $userid ( keys %userids ) {
        my $u_tokens = $userids{$userid};

        my @ids    = map { $_->consumer_id } grep { !exists $_->{lastaccess} } values %$u_tokens;
        my $qmarks = join( ",", map { '?' } @ids );

        my $sth = $dbr->prepare(
"SELECT consumer_id,lastaccess FROM oauth_access_token WHERE consumer_id IN ($qmarks) AND userid = ?"
        ) or die $dbr->errstr;
        $sth->execute( @ids, $userid ) or die $dbr->errstr;
        while ( my $row = $sth->fetchrow_hashref ) {
            $u_tokens->{ $row->{consumer_id} }->{lastaccess} = $row->{lastaccess};
        }
    }
}

sub update_accessed {
    my $self = $_[0];

    my $dbh = LJ::get_db_writer() or die 'Failed to get database';
    $dbh->do( "UPDATE oauth_access_token SET lastaccess = ? WHERE consumer_id = ? AND userid = ?",
        undef, time, $self->consumer_id, $self->userid )
        or die $dbh->errstr;

    delete $self->{lastaccess};
}

sub invalidate_token {
    my $c = $_[0];

    my $old_token = $c->token;

    return unless $old_token;

    my $dbh = LJ::get_db_writer();
    $dbh->do(
"UPDATE oauth_access_token SET token = NULL, secret = NULL WHERE consumer_id = ? AND userid = ?",
        undef, $c->consumer_id, $c->userid
    ) or die $dbh->errstr;

    delete $c->{token};
    delete $c->{secret};

    my $expire = time() + 1800;

    LJ::MemCache::delete( [ $old_token, "oauth_access_token:" . $old_token ] );

    my $ar = LJ::MemCache::hash_to_array( "oauth_access", $c );
    LJ::MemCache::set( [ $c->userid, join( ":", "oauth_access", $c->userid, $c->consumer_id ) ],
        $ar, $expire );

    delete $LJ::REQUEST_CACHE{oauth_access}{$old_token};
}

sub reissue_token {
    my $c = $_[0];

    my ( $token, $secret ) = DW::OAuth->make_token_pair('access');

    my $dbh = LJ::get_db_writer();
    $dbh->do(
"UPDATE oauth_access_token SET createtime = ?, token = ?, secret = ? WHERE consumer_id = ? AND userid = ?",
        undef, time(), $token, $secret, $c->consumer_id, $c->userid
    ) or die $dbh->errstr;

    if ( $c->token ) {
        LJ::MemCache::delete( [ $c->token, "oauth_access_token:" . $c->token ] );
        delete $LJ::REQUEST_CACHE{oauth_access}{ $c->token };
    }

    $c->{token}  = $token;
    $c->{secret} = $secret;

    my $expire = time() + 1800;

    my $ar = LJ::MemCache::hash_to_array( "oauth_access", $c );
    LJ::MemCache::set( [ $c->userid, join( ":", "oauth_access", $c->userid, $c->consumer_id ) ],
        $ar, $expire );

    if ( $c->token ) {
        LJ::MemCache::set( [ $c->token, "oauth_access_token:" . $c->token ],
            [ $c->userid, $c->consumer_id ], $expire );
        $LJ::REQUEST_CACHE{oauth_access}{ $c->token } = $c;
    }
}

sub has_token {
    my $r = $_[0];

    return ( $r->token && $r->secret ) ? 1 : 0;
}

sub token_valid {
    my $r = $_[0];
    my $c = $r->consumer;

    return 0 unless $r->has_token;
    return 1 unless $c;

    return 0 if $c->invalidatedtime && $r->createtime <= $c->invalidatedtime;
    return 1;
}

sub usable {
    my $r = $_[0];
    my $c = $r->consumer;

    return 0 unless $c->token && $c->secret;

    return 0 unless $c;
    return 0 if exists $_[1] && $c->id != $_[1]->id;

    return 0 unless $c->usable;
    return 0 if $c->invalidatedtime && $r->createtime <= $c->invalidatedtime;
    return 1;
}

sub delete {
    my $c = $_[0];

    # trample on this in case there's one of these still around somewhere
    $c->{secret} = undef;

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do( "DELETE FROM oauth_access_token WHERE userid = ? AND consumer_id = ?",
        undef, $c->userid, $c->consumer_id )
        or return 0;

    DW::OAuth::Access->_clear_user_tokens( $c->userid );
    $c->_delete_cache;

    return 1;
}

1;
