#!/usr/bin/perl
#
# DW::OAuth
#
# OAuth Consumer
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::OAuth::Consumer;
use strict;
use warnings;

use DW::OAuth;

sub from_token {
    my ( $class, $token ) = @_;
    return undef unless $token;
    return $LJ::REQUEST_CACHE{oauth_consumer}{$token} if $LJ::REQUEST_CACHE{oauth_consumer}{$token};
    return undef unless DW::OAuth->validate_token($token);

    {
        my $consumer_id = LJ::MemCache::get( [ $token, "oauth_consumer_token:" . $token ] );
        return $class->from_id($consumer_id) if $consumer_id;
    }

    return $class->_load_raw( 'token', $token );
}

sub from_id {
    my ( $class, $id ) = @_;
    return undef unless $id;
    return $LJ::REQUEST_CACHE{oauth_consumer}{$id} if $LJ::REQUEST_CACHE{oauth_consumer}{$id};

    {
        my $ar  = LJ::MemCache::get( [ $id, "oauth_consumer:" . $id ] );
        my $row = $ar ? LJ::MemCache::array_to_hash( "oauth_consumer", $ar ) : undef;
        return $class->new_from_row($row) if $row;
    }

    return $class->_load_raw( 'consumer_id', $id );
}

sub want {
    my ( $class, $thing ) = @_;

    return undef unless $thing;
    return $thing if ref $thing eq $class;
    return $class->from_id($thing) if int($thing) eq $thing;
    return $class->from_token($thing);
}

sub want_id {
    my ( $class, $thing ) = @_;

    return undef unless $thing;
    return $thing->consumer_id if ref $thing eq $class;
    return $thing if $thing =~ /^\d+$/;
    return undef;
}

sub tokens_for_user {
    my ( $class, $u ) = @_;
    my $userid = LJ::want_userid($u);

    return [] unless $userid;

    my @ret;

    my @ids;
    my $memkey = [ $userid, "user_oauth_consumer:" . $userid ];
    my $data   = LJ::MemCache::get($memkey);

    if ($data) {
        @ids = @$data;
    }
    else {
        my $dbr = LJ::get_db_reader() or die "Failed to get database";
        my $sth = $dbr->prepare("SELECT consumer_id FROM oauth_consumer WHERE userid = ?")
            or die $dbr->errstr;
        $sth->execute($userid) or die $dbr->errstr;

        while ( my ($id) = $sth->fetchrow_array ) {
            push @ids, $id;
        }
        LJ::MemCache::set( $memkey, \@ids );
    }

    foreach my $id (@ids) {
        push @ret, $class->from_id($id);
    }

    return \@ret;
}

sub _clear_user_tokens {
    LJ::MemCache::delete( [ $_[1], "user_oauth_consumer:" . $_[1] ] );
}

sub _delete_cache {
    my $c = $_[0];

    DW::OAuth::Consumer->_clear_user_tokens( $c->{userid} );
    LJ::MemCache::delete( [ $c->id,    "oauth_consumer:" . $c->id ] );
    LJ::MemCache::delete( [ $c->token, "oauth_consumer_token:" . $c->token ] );
    delete $LJ::REQUEST_CACHE{oauth_consumer}{ $c->token };
}

sub _load_raw {
    my ( $class, $key, $val ) = @_;

    my $dbh = LJ::get_db_writer() or die "Failed to get database";
    my $sth = $dbh->prepare("SELECT * FROM oauth_consumer WHERE $key = ?") or die $dbh->errstr;
    $sth->execute($val) or die $dbh->errstr;
    my $row = $sth->fetchrow_hashref;
    return $row ? $class->new_from_row($row) : undef;
}

sub new {
    my ( $class, %opts ) = @_;

    $opts{userid} = $opts{u}->userid if $opts{u};

    # Required.
    die "Missing required parameter" unless $opts{userid} && $opts{name} && $opts{website};

    my ( $token, $secret ) = $class->make_token_pair( \%opts );

    $opts{token}  = $token;
    $opts{secret} = $secret;

    my $dbh = LJ::get_db_writer()           or die 'Failed to get database';
    my $id  = LJ::alloc_global_counter('U') or die 'Failed to alloc counter';
    $dbh->do(
"INSERT INTO oauth_consumer (consumer_id, userid, name, website, token, secret, createtime) VALUES (?,?,?,?,?,?,?)",
        undef,
        $id,
        $opts{userid},
        $opts{name},
        $opts{website},
        $opts{token},
        $opts{secret},
        time()
    ) or die $dbh->errstr;

    $class->_clear_user_tokens( $opts{userid} );

    return $class->from_id($id);
}

sub make_token_pair {
    my ( $self, $data ) = @_;

    $data = $self if ref $self;

    return DW::OAuth->make_token_pair('consumer');
}

sub new_from_row {
    my ( $class, $row ) = @_;

    my $c = bless $row, $class;

# These can change, we need to store the original value so in case it changes, we can invalidate the right memcache key later.
    for my $item (qw(token userid)) {
        $c->{_orig}{$item} = $c->{$item};
    }

    my $expire = time() + 1800;

    my $ar = LJ::MemCache::hash_to_array( "oauth_consumer", $c );
    LJ::MemCache::set( [ $c->id, "oauth_consumer:" . $c->id ], $ar, $expire );
    LJ::MemCache::set( [ $c->token, "oauth_consumer_token:" . $c->token ], $c->id );

    $LJ::REQUEST_CACHE{oauth_consumer}{ $c->token } = $c;
    $LJ::REQUEST_CACHE{oauth_consumer}{ $c->id }    = $c;

    return $c;
}

sub id {
    $_[0]->{consumer_id};
}

sub owner {
    if ( defined $_[1] ) {
        $_[0]->{changed}{userid} = 1;
        return $_[0]->{userid} = $_[1]->userid;
    }
    else {
        return LJ::load_userid( $_[0]->{userid} );
    }
}

sub ownerid {
    if ( defined $_[1] ) {
        $_[0]->{changed}{userid} = 1;
        return $_[0]->{userid} = $_[1];
    }
    else {
        return $_[0]->{userid};
    }
}

sub token {
    return $_[0]->{token};
}

sub secret {
    return $_[0]->{secret};
}

sub reissue_token_pair {
    my ( $token, $secret ) = $_[0]->make_token_pair;

    $_[0]->{token}  = $token;
    $_[0]->{secret} = $secret;

    $_[0]->{changed}{token}  = 1;
    $_[0]->{changed}{secret} = 1;

    $_[0]->invalidatedtime( time() );

    return $_[0]->save;
}

sub name {
    if ( defined $_[1] ) {
        $_[0]->{changed}{name} = 1;
        return $_[0]->{name} = $_[1];
    }
    else {
        return $_[0]->{name};
    }
}

sub website {
    if ( defined $_[1] ) {
        $_[0]->{changed}{website} = 1;
        return $_[0]->{website} = $_[1];
    }
    else {
        return $_[0]->{website};
    }
}

sub createtime {
    return $_[0]->{createtime};
}

sub updatetime {
    if ( exists $_[1] ) {
        $_[0]->{changed}{updatetime} = 1;
        return $_[0]->{updatetime} = $_[1];
    }
    else {
        return $_[0]->{updatetime};
    }
}

sub invalidatedtime {
    if ( exists $_[1] ) {
        $_[0]->{changed}{invalidatedtime} = 1;
        return $_[0]->{invalidatedtime} = $_[1];
    }
    else {
        return $_[0]->{invalidatedtime};
    }
}

sub approved {
    if ( defined $_[1] ) {
        $_[0]->{changed}{approved} = 1;
        return $_[0]->{approved} = $_[1];
    }
    else {
        return $_[0]->{approved};
    }
}

sub active {
    if ( defined $_[1] ) {
        $_[0]->{changed}{active} = 1;
        return $_[0]->{active} = $_[1];
    }
    else {
        return $_[0]->{active};
    }
}

sub why_unusable {
    my $self = $_[0];
    my $u    = $self->owner;

    return 'no_user' unless $u;
    return 'user_inactive' if $u->is_inactive;
    return 'not_person' unless $u->is_person;
    return 'sysbanned' if LJ::sysban_check( 'oauth_consumer', $u->user );
    return 'no_approve' unless $_[0]->approved;
    return 'inactive'   unless $_[0]->active;
    return 'unknown'    unless $self->usable;
    return undef;
}

sub usable {
    my $self = $_[0];
    my $u    = $self->owner;

    return 0 unless $u;
    return 0 if $u->is_inactive || !$u->is_person;
    return 0 if LJ::sysban_check( 'oauth_consumer', $u->user );
    return ( $_[0]->approved && $_[0]->active ) ? 1 : 0;
}

sub save {
    my $c = $_[0];

    my $changed = $c->{changed};
    return unless $changed;

    my @sets;
    my @bindparams;
    while ( my ( $k, $v ) = each %$changed ) {
        next unless $v;
        push @sets,       "$k=?";
        push @bindparams, $c->{$k};
    }

    return 1 unless @sets;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;
    {
        local $" = ",";
        $dbh->do( "UPDATE oauth_consumer SET @sets WHERE consumer_id = ?",
            undef, @bindparams, $c->id );
        return 0 if $dbh->err;
    }

    if ( $changed->{userid} ) {
        DW::OAuth::Consumer->_clear_user_tokens( $c->{userid} );
        DW::OAuth::Consumer->_clear_user_tokens( $c->{_orig}{userid} );
    }

    LJ::MemCache::delete( [ $c->id, "oauth_consumer:" . $c->id ] );
    unless ( $c->{_orig}{token} eq $c->{token} ) {
        LJ::MemCache::delete(
            [ $c->{_orig}{token}, "oauth_consumer_token:" . $c->{_orig}{token} ] );
        LJ::MemCache::delete( [ $c->token, "oauth_consumer_token:" . $c->token ] );   # just in case
        delete $LJ::REQUEST_CACHE{oauth_consumer}{ $c->{_orig}{token} };
        $LJ::REQUEST_CACHE{oauth_consumer}{ $c->token } = $c;
    }

    $c->{_orig}{token} = $c->{token};
    delete $c->{changed};
    return 1;
}

sub delete {
    my $c = $_[0];

    my $tokens = DW::OAuth::Access->tokens_for_consumer($c);

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    foreach my $token (@$tokens) {
        $token->delete or return 0;
    }

    $dbh->do( "DELETE FROM oauth_consumer WHERE consumer_id = ?", undef, $c->id ) or return 0;

    $c->_delete_cache;

    return 1;
}

1;
