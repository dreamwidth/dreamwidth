#!/usr/bin/perl
#
# DW::Draft
#
# Draft/scheduled posts.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Draft;
use strict;
use warnings;

use Storable;
use DateTime::Format::Strptime;

use base 'DW::UserDbObj';

sub _tablename { "draft" }

sub _obj_props {
    # be sure to add to _editable_obj_props below if a new property is 
    # editable.
    return qw( subject summary createtime modtime status recurring_period nextscheduletime );
}

# Editable properties for the object. 
sub _editable_obj_props {
    return qw( subject summary modtime status recurring_period nextscheduletime );
}

sub _default_order_by {
    return " ORDER BY nextscheduletime, createtime ";
}

sub _usercounter_id { "2" }

sub _memcache_key_prefix            { "draft" }
sub _memcache_version { "1" }

sub memcache_enabled { 1 }
sub memcache_query_enabled { 1 }

# populates the basic keys for a Draft post; everything else is
# loaded from absorb_row
sub _skeleton {
    my ( $class, $u, $id ) = @_;
    return bless {
        id => $id,
        _obj_id => $id,
        userid => $u->id,
        _userid => $u->id,
    };
}

# does a full create.  should probably not be called directly; instead
# use create_draft or create_scheduled
sub create {
    my ( $class, $u, $req, $opts ) = @_;

    $opts ||= {};

    $opts->{createtime} = LJ::mysql_time( time );
    $opts->{modtime} = LJ::mysql_time( time );
    $opts->{subject} = $req->{subject};
    $opts->{summary} = $class->_create_summary( $req->{event} );

    my $draft = $class->_create( $u, $opts );

    $draft->set_req( $req );
    $draft->_save_req();

    $draft->_clear_associated_caches();

    return $draft;
}

# creates a draft
sub create_draft {
    my ( $class, $u, $req, $opts ) = @_;

    $opts ||= {};
    $opts->{status} = 'D';
 
    return $class->create( $u, $req, $opts );
}

# creates a scheduled post
sub create_scheduled_draft {
    my ( $class, $u, $req, $opts ) = @_;

    $opts ||= {};
    $opts->{status} = 'S';

    return $class->create( $u, $req, $opts );
}

# updates an existing instance.  overrides UserDbObj->update().
sub update {
    my ( $self ) = @_;

    # need to update modtime and then do a save_req in addition to 
    # modifying the base table.
    $self->{modtime} = LJ::mysql_time( time );
    $self->SUPER::update();
    $self->_save_req();
}

# saves the request to the draftblob table.
sub _save_req {
    my ( $self ) = @_;

    # only update if we've set the request already
    my $req = $self->{req};
    if ( $req ) {
        my $u = $self->user;

        # delete the old req
        $u->do( "DELETE FROM draftblob WHERE userid = ? AND id = ?", undef, $u->{userid}, $self->{id} );
        LJ::throw($u->errstr) if $u->err;
        
        my $frozen_req = Storable::nfreeze( $req );

        # and save the new one
        $u->do( "INSERT INTO draftblob (userid, id, req_stor) VALUES (?, ?, ?)", undef, $u->{userid}, $self->{id}, $frozen_req );
        LJ::throw($u->errstr) if $u->err;
    }
}

# loads the req from the draftblob table
sub _load_req {
    my ( $self ) = @_;
    
    if ( defined $self->{req} ) {
        return;
    }
    my $u = $self->user;

    my $sth = $u->prepare( "SELECT req_stor FROM draftblob WHERE userid = ? AND id = ?" );
    $sth->execute( $u->{userid}, $self->{id});
    LJ::throw( $u->errstr ) if $u->err;
    
    my $blob = $sth->fetchrow_hashref->{req_stor};
    $self->{req} = Storable::thaw( $blob );
}

# deletes this object
sub delete {
    my ($self) = @_;
    my $u = $self->user;

    $u->do("DELETE FROM draftblob " . $self->_where_by_id, 
           undef, $self->_key );

    $u->do("DELETE FROM " . $self->_tablename . " " . $self->_where_by_id, 
           undef, $self->_key );

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return 1;
}

# copies from an existing object
sub copy_from_object {
    my ( $self, $source ) = @_;
    
    $self->_copy_from_object( $source );
    if ( exists $source->{req} ) {
        $self->set_req( $source->{req} );
    } 
}

# all drafts (not scheduled) for user
sub all_drafts_for_user {
    my ( $class, $u ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return DW::UserDbObjAccessor->new( $class, $u )->_fv_query_by_user( { status => 'D' } );
}

# all scheduled drafts for user
sub all_scheduled_posts_for_user {
    my ( $class, $u ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return DW::UserDbObjAccessor->new( $class, $u )->_fv_query_by_user( { status => 'S' } );
}

# sets the req for this Draft, plus updates the associated fields (subject, 
# summary)
sub set_req {
    my ( $self, $req ) = @_;

    $self->{subject} = $req->{subject};
    $self->{summary} = $self->_create_summary( $req->{event} );

    $self->{req} = $req;
}

# returns the req for this draft
sub req {
    my ( $self ) = @_;

    if ( ! defined $self->{req} ) {
        $self->_load_req();
    }
    return $self->{req};
}

# field accessors
sub subject { return $_[0]->{subject}; }
sub summary { return $_[0]->{summary}; }
sub createtime { return $_[0]->{createtime}; }
sub modtime { return $_[0]->{modtime}; }
sub status { return $_[0]->{status}; }
sub recurring_period { return $_[0]->{recurring_period}; }

# returns the nextscheduletime as a DateTime object
sub nextscheduletime_dt {
    my ( $self ) = @_;

    # only return if we're scheduled to post
    if ( $self->status eq 'S' ) {
        if ( ! defined $self->{nextschedule_dt} ) {
            my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
            my $nextschedule_dt = $parser->parse_datetime( $self->{nextscheduletime} );
            $self->{nextschedule_dt} = $nextschedule_dt;
        }
        return $self->{nextschedule_dt};
    }

    return undef;
}

# creates the summary. separated out because we need to make sure that 
# the trimmed value is small enough to fit in the db field
sub _create_summary {
    my ( $class, $event ) = @_;

    my $summary = LJ::html_trim( $event, 128 );
    # give it two tries and then give up
    if ( $summary && length( $summary ) > 255 ) {
        $summary =  LJ::html_trim( $event, 64 );
        if ( $summary && length( $summary ) > 255 ) {
            $summary = "";
        }
    }
    return $summary;
}

# returns the edit url for this draft
sub edit_url {
    my ( $self ) = @_;
  
    return LJ::create_url( "/draft/" . $self->user->user . "/" . $self->id . "/edit", host => $LJ::DOMAIN_WEB ),
}

# finds and posts scheduled drafts for a cluster
sub post_by_cluster {
    my ( $class, $cid ) = @_;

    my $dbcr = LJ::get_cluster_def_reader($cid)
        or die "Unable to load reader for cluster: $cid";
    my $sql = "SELECT userid, id FROM " . $class->_tablename . " WHERE nextscheduletime <= now()";
    my $sth = $dbcr->prepare( $sql );
    $sth->execute();
    LJ::throw( $dbcr->errstr ) if $dbcr->err;

    while ( my $row = $sth->fetchrow_hashref ) {
        my $uid = $row->{userid};
        my $id = $row->{id};
        my $u = LJ::want_user( $uid );
        my $scheduled_draft = DW::Draft->by_id( $u, $id );
        my $result = $scheduled_draft->post();
        # FIXME should probably send out a notification for these
        if ( $result->{success} ) {
            warn("success!");
        } else {
            warn("error: " . $result->{errors});
        }
    }
}

# posts a scheduled draft
sub post {
    my ( $self ) = @_;

    my $req = $self->req;
    $req->{ver} = $LJ::PROTOCOL_VER;
    $req->{draftid} = $self->{id};
    $req->{username} = $self->user->user;

    # set the date to now
    my $now = DateTime->now;
    # if user has timezone, use it!
    if ( $self->user && $self->user->prop( "timezone" ) ) {
        my $tz = $self->user->prop( "timezone" );
        $tz = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
        $now = eval { DateTime->from_epoch( epoch => time(), time_zone => $tz ); } if $tz;
    }

    $req->{year}    = $now->year;
    $req->{mon}     = $now->month;
    $req->{day}     = $now->day;
    $req->{hour}    = $now->hour;
    $req->{min}     = $now->min;
    
    my $err = 0;
    my $res = LJ::Protocol::do_request( "postevent", $req, \$err, { noauth => 1 } );

    return { errors => LJ::Protocol::error_message( $err ) } unless $res;
    return { success => 1 };
}

# handles a draft having been posted
sub handle_posted {
    my ( $self ) = @_;

    if ( $self->status eq 'D' ) {
        # if it's a draft, just delete it
        $self->delete();
    } elsif  ( $self->status eq 'S' ) {
        if ( $self->recurring_period eq 'never' ) {
            $self->delete();
        } else {
            # if this was scheduled to be posted in the past, then we need
            # to schedule the next post
            if ( $self->nextscheduletime_dt->epoch() < time ) {
                if ( $self->recurring_period eq 'day' ) {
                    $self->{nextscheduletime} =  LJ::mysql_time( time + ( 60 * 60 * 24 ) );
                    $self->update();
                } elsif ( $self->recurring_period eq 'week' ) {
                    $self->{nextscheduletime} =  LJ::mysql_time( time + ( 60 * 60 * 24 * 7 ) );
                    $self->update();
                } elsif ( $self->recurring_period eq 'month' ) {
                    # FIXME this isn't really monthly
                    $self->{nextscheduletime} =  LJ::mysql_time( time + ( 60 * 60 * 24 * 30 ) );
                    $self->update();
                } else {
                    # no match means treat as never
                    $self->delete();
                }
            } 
        }
    }
}

# clears associated cache for add/delete
sub _clear_associated_caches() {
    my ($self) = @_;

    $self->_clear_keys( { userid => $self->user->id } );
    $self->_clear_keys( { userid => $self->user->id, status => $self->{status} } );
}


1;
