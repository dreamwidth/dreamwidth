#!/usr/bin/perl
#
# DW::Mood - Provide mood theme support. Replaces ljmood.pl from LJ.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Mood;

use strict;
use warnings;

use LJ::CleanHTML;

### MOOD (CLASS) METHODS

# load list of moods from DB (adapted from LJ::load_moods)
# arguments: none
# returns: true
sub load_moods {
    return 1 if $LJ::CACHED_MOODS;
    my $dbr = LJ::get_db_reader();
    my $data = $dbr->selectall_arrayref(
        "SELECT moodid, mood, parentmood, weight FROM moods" );
    die $dbr->errstr if $dbr->err;

    $LJ::CACHED_MOOD_MAX ||= 0;

    foreach my $row ( @$data ) {
        my ( $id, $mood, $parent, $weight ) = @$row;
        $LJ::CACHE_MOODS{$id} =
            { name => $mood, parent => $parent, id => $id, weight => $weight };
        $LJ::CACHED_MOOD_MAX = $id if $id > $LJ::CACHED_MOOD_MAX;
    }
    return $LJ::CACHED_MOODS = 1;
}

# get list of moods from cache (adapted from LJ::get_moods)
# arguments: class
# returns: hashref
sub get_moods {
    my ( $self ) = @_;
    $self->load_moods;
    return \%LJ::CACHE_MOODS;
}

# mood name to id (or undef) (adapted from LJ::mood_id)
sub mood_id {
    my ( $self, $mood ) = @_;
    return undef unless $mood;

    $self->load_moods;
    foreach my $m ( values %LJ::CACHE_MOODS ) {
        return $m->{id} if $mood eq $m->{name};
    }
    return undef;
}

# mood id to name (or undef) (adapted from LJ::mood_name)
sub mood_name {
    my ( $self, $moodid ) = @_;
    return undef unless $moodid;

    $self->load_moods;
    my $m = $LJ::CACHE_MOODS{$moodid};
    return $m ? $m->{name} : undef;
}

# associate local moods with moodids on other sites
# arguments: local moodid or mood; external siteid
# returns: id of mood on the remote site, or 0 on failure
sub get_external_moodid {
    my ( $self, %opts ) = @_;

    my $siteid = $opts{siteid};
    my $moodid = $opts{moodid};
    my $mood = $opts{mood};

    return 0 unless $siteid;
    return 0 unless $moodid || $mood;

    my $mood_text = $mood ? $mood : $self->mood_name( $moodid );

    # determine which moodid on the external site
    # corresponds to the given $mood_text
    my $dbr = LJ::get_db_reader();
    my ( $external_moodid ) = $dbr->selectrow_array(
        "SELECT moodid FROM external_site_moods WHERE siteid = ?" .
        " AND LOWER( mood ) = ?", undef, $siteid, lc $mood_text );

    return $external_moodid ? $external_moodid : 0;
}


### THEME (OBJECT/CLASS) METHODS

# basic object construction: requires theme id
# arguments: theme id (required)
# returns: object reference, undef on failure
sub new {
    my ( $class, $id ) = @_;
    return undef unless $id;
    my $self = {};  # id set via object method below
    bless $self, ( ref $class ? ref $class : $class );
    return undef unless $self->id( $id );
    $self->load_moods;  # not necessary but saves effort later
    return $self->load_theme;
}

# basic get/set for theme id
# arguments: set if theme id given, get if no args
# returns: value of theme id, undef on failure
sub id {
    my ( $self, $id ) = @_;
    return undef if $id && $id !~ /^\d+$/;  # invalid id
    return $id unless ref $self;            # class method
    return $self->{id} unless $id;          # get only
    return $self->{id} = $id;               # set and return
}

# load theme data from DB (adapted from LJ::load_mood_theme)
# arguments: theme id (only required if called as class method)
# returns: object reference, undef on failure
sub load_theme {
    my ( $self, $themeid ) = @_;

    # force object path if called as class
    return $self->new( $themeid ) unless ref $self;

    # check themeid and assign it to the object
    return undef unless $themeid = $self->id( $themeid );

    # check global memory cache
    return $self if $LJ::CACHE_MOOD_THEME{$themeid};

    # check memcache
    my $memkey = [$themeid, "moodthemedata:$themeid"];
    $LJ::CACHE_MOOD_THEME{$themeid} = LJ::MemCache::get( $memkey );
    return $self if %{ $LJ::CACHE_MOOD_THEME{$themeid} || {} };

    # fall back to db
    $LJ::CACHE_MOOD_THEME{$themeid} = {};
    my $dbr = LJ::get_db_reader();

    # load picture rows from moodthemedata
    my $data = $dbr->selectall_arrayref(
        "SELECT moodid, picurl, width, height FROM moodthemedata " .
        "WHERE moodthemeid=?", undef, $themeid );
    die $dbr->errstr if $dbr->err;

    # load metadata from moodthemes
    my ( $name, $des, $is_public, $ownerid ) = $dbr->selectrow_array(
        "SELECT name, des, is_public, ownerid FROM moodthemes" .
        " WHERE moodthemeid=?", undef, $themeid );
    die $dbr->errstr if $dbr->err;

    LJ::MemCache::set( $memkey, {}, 3600 ) and return undef
        unless $name;  # no results for this theme

    $LJ::CACHE_MOOD_THEME{$themeid}->{moodthemeid} = $themeid;
    $LJ::CACHE_MOOD_THEME{$themeid}->{is_public} = $is_public;
    $LJ::CACHE_MOOD_THEME{$themeid}->{ownerid}   = $ownerid;
    $LJ::CACHE_MOOD_THEME{$themeid}->{name} = $name;
    $LJ::CACHE_MOOD_THEME{$themeid}->{des}  = $des;

    foreach my $d ( @$data ) {
        my ( $id, $pic, $w, $h ) = @$d;
        $LJ::CACHE_MOOD_THEME{$themeid}->{$id} =
            { pic => $pic, w => $w, h => $h };
    }

    # set in memcache
    LJ::MemCache::set( $memkey, $LJ::CACHE_MOOD_THEME{$themeid}, 3600 )
        if %{ $LJ::CACHE_MOOD_THEME{$themeid} || {} };

    return $self;
}

# object method to load a mood icon (adapted from LJ::get_mood_picture)
# arguments: moodid; hashref to assign with mood icon data
# returns: 1 on success, 0 otherwise.
sub get_picture {
    my ( $self, $moodid, $ref ) = @_;
    return 0 unless $ref && ref $ref;
    my $themeid = $self->id or return 0;

    while ( $moodid ) {
        # inheritance check
        unless ( $LJ::CACHE_MOOD_THEME{$themeid} &&
                 $LJ::CACHE_MOOD_THEME{$themeid}->{$moodid} ) {
            $moodid = defined $LJ::CACHE_MOODS{$moodid} ?
                      $LJ::CACHE_MOODS{$moodid}->{parent} : 0;
            next;
        }
        # load the data
        %{ $ref } = %{ $LJ::CACHE_MOOD_THEME{$themeid}->{$moodid} };
        $ref->{moodid} = $moodid;
        # sanitize the value of pic
        if ($ref->{pic} =~ m!^/!) {
            $ref->{pic} =~ s!^/img!!;
            $ref->{pic} = $LJ::IMGPREFIX . $ref->{pic};
        }
        # must be a good url
        $ref->{pic} = "#invalid" unless
            $ref->{pic} =~ m!^https?://[^\'\"\0\s]+$!;
        $ref->{pic} = LJ::CleanHTML::https_url( $ref->{pic} );
        return 1;
    }
    return 0;  # couldn't find a picture anywhere in the parent chain
}

# object method to update or delete a mood icon
# arguments: moodid; hashref containing new mood icon data; error ref
# returns: 1 on success, undef otherwise.
sub set_picture {
    my ( $self, $moodid, $pic, $err, $dbh ) = @_;
    my $errsub = sub { $$err = $_[0] if ref $err; return undef };
    return $errsub->( LJ::Lang::ml( "/manage/moodthemes.bml.error.cantupdatetheme" ) )
        unless $self->id and $moodid and ref $pic and $moodid =~ /^\d+$/;

    my ( $picurl, $w, $h ) = @{ $pic }{ qw/ picurl width height / };
    return $errsub->( LJ::Lang::ml( "/manage/moodthemes.bml.error.notanumber",
                      { moodname => $self->mood_name( $moodid ) } ) )
        if ( $w and $w !~ /^\d+$/ ) or ( $h and $h !~ /^\d+$/ );
    return $errsub->( LJ::Lang::ml( "/manage/moodthemes.bml.error.picurltoolong" ) )
        if $picurl and length $picurl > 200;

    $dbh ||= LJ::get_db_writer() or
        return $errsub->( LJ::Lang::ml( "error.nodb" ) );

    if ( $picurl && $w && $h ) {  # do update
        $dbh->do( "REPLACE INTO moodthemedata (moodthemeid, moodid," .
                  " picurl, width, height) VALUES (?, ?, ?, ?, ?)",
                 undef, $self->id, $moodid, $picurl, $w, $h );
    } else {  # do delete
        $dbh->do( "DELETE FROM moodthemedata WHERE moodthemeid = ?" .
                  " AND moodid= ?", undef, $self->id, $moodid );
    }
    return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr )
        if $dbh->err;
    $self->clear_cache;

    return 1;
}

# object method to update or delete multiple mood icons in one transaction
# arguments: arrayref of data arrayrefs [ $moodid => \%pic ]; error ref
# returns: 1 on success, undef otherwise.
sub set_picture_multi {
    my ( $self, $data, $err ) = @_;
    die "Need array reference for set_picture_multi"
        unless ref $data eq "ARRAY";

    my $errsub = sub { $$err = $_[0] if ref $err; return undef };
    my $dbh = LJ::get_db_writer() or
        return $errsub->( LJ::Lang::ml( "error.nodb" ) );
    $dbh->begin_work;
    return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr )
        if $dbh->err;

    foreach ( @$data ) {
        # we pass the database handle for transaction continuity
        my $rv = $self->set_picture( $_->[0], $_->[1], $err, $dbh );
        unless ( $rv ) {  # abort transaction
            $dbh->rollback;
            return undef;  # error message already in $err
        }
    }

    $dbh->commit;
    return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr )
        if $dbh->err;

    return 1;
}

# get theme description (adapted from LJ::mood_theme_des)
# arguments: theme id (only required if called as class method)
sub des {
    my $self = shift;
    return $self->prop( 'des', @_ );
}

# get named property of mood theme from cache
sub prop {
    my ( $self, $prop, $themeid ) = @_;

    if ( defined $themeid ) {
        # make sure the theme is valid and cached
        $self = $self->load_theme( $themeid ) or return;
    } else {
        # make sure we have an object loaded
        $themeid = $self->id or return;
    }

    my $m = $LJ::CACHE_MOOD_THEME{$themeid};
    return $m ? $m->{$prop} : undef;
}

# given a theme, lookup the user who owns it
# arguments: theme id (only required if called as class method)
# returns: userid, undef on failure
sub ownerid {
    my $self = shift;
    return $self->prop( 'ownerid', @_ );
}

# given a theme, check whether it is public
# arguments: theme id (only required if called as class method)
# returns: Y/N/undef
sub is_public {
    my $self = shift;
    return $self->prop( 'is_public', @_ );
}

# set named property of mood theme and clear cache
sub update {
    my ( $self, $prop, $newval, $themeid ) = @_;

    if ( defined $themeid ) {
        # make sure the theme is valid and cached
        $self = $self->load_theme( $themeid ) or return;
    } else {
        # make sure we have an object loaded
        $themeid = $self->id or return;
    }

    # validity check
    my $m = $LJ::CACHE_MOOD_THEME{$themeid};
    return unless $m && $m->{$prop};
    my $ownerid = $m->{ownerid};

    # do the update
    my $dbh = LJ::get_db_writer() or return;
    $dbh->do( "UPDATE moodthemes SET $prop = ? WHERE moodthemeid = ?",
              undef, $newval, $themeid );
    die $dbh->errstr if $dbh->err;

    $self->clear_cache;
    LJ::MemCache::delete( "moods_public" ) if $prop eq 'is_public';
    # the following are equivalent to $u->delete_moodtheme_cache
    LJ::MemCache::delete( [$ownerid, "moodthemes:$ownerid"] );
    LJ::MemCache::delete( [$newval, "moodthemes:$newval"] )
        if $prop eq 'ownerid';

    return 1;
}

# clear cached theme data from memory
# arguments: theme id (only required if called as class method)
# returns: nothing
sub clear_cache {
    my ( $self, $themeid ) = @_;

    # load theme id from object if needed
    $themeid ||= $self->id if ref $self;

    # clear the caches
    LJ::MemCache::delete( [$themeid, "moodthemedata:$themeid"] );
    delete $LJ::CACHE_MOOD_THEME{$themeid};
}

# get list of theme data for given theme and/or user
# arguments: hashref { themeid => ?, ownerid => ? }
# returns: array of hashrefs from memcache or db, undef on failure
sub get_themes {
    my ( $self, $arg ) = @_;
    # if called with no arguments, check for object id
    $arg ||= { themeid => $self->id } if ref $self;
    return undef unless $arg;

    my ( $themeid, $ownerid ) = ( $arg->{themeid}, $arg->{ownerid} );
    $ownerid ||= $self->ownerid( $themeid );
    return undef unless $ownerid;

    # cache contains list of all themes for this user
    my $memkey = [$ownerid, "moodthemes:$ownerid"];
    my $ids = LJ::MemCache::get( $memkey );
    unless ( defined $ids ) {
        # check database
        my $dbr = LJ::get_db_reader() or return undef;
        $ids = $dbr->selectcol_arrayref(
            "SELECT moodthemeid FROM moodthemes" .
            " WHERE ownerid=? ORDER BY name", undef, $ownerid );
        die $dbr->errstr if $dbr->err;
        # update memcache
        LJ::MemCache::set( $memkey, $ids, 3600 );
    }

    # if they specified a theme, see if it's in the list
    if ( $themeid and grep { $_ == $themeid } @$ids ) {
        $self->load_theme( $themeid );
        my $data = $LJ::CACHE_MOOD_THEME{$themeid};
        return wantarray ? ( $data ) : $data;
    } elsif ( $themeid ) {
        # not in the list: ownerid doesn't own themeid
        return undef;
    }

    # if they didn't specify a theme, return everything
    return $self->_load_data_multiple( $ids );
}

sub _load_data_multiple {
    my ( $self, $themes ) = @_;
    my @data;
    foreach ( @$themes ) {
        $self->load_theme( $_ );
        push @data, $LJ::CACHE_MOOD_THEME{$_};
    }
    return @data;
}

# class method to get data for all public themes
# arguments: class
# returns: array of hashrefs from memcache or db, undef on failure
sub public_themes {
    my ( $self ) = @_;
    my $memkey = "moods_public";
    # only ids are in memcache
    my $ids = LJ::MemCache::get( $memkey );
    unless ( defined $ids ) {
        # check database
        my $dbr = LJ::get_db_reader() or return undef;
        $ids = $dbr->selectcol_arrayref(
            "SELECT moodthemeid FROM moodthemes" .
            " WHERE is_public='Y' ORDER BY name" );
        die $dbr->errstr if $dbr->err;
        # update memcache
        LJ::MemCache::set( $memkey, $ids, 3600 );
    }
    return $self->_load_data_multiple( $ids );
}


# END package DW::Mood;

package LJ::User;

# user method for accessing the currently selected moodtheme
sub moodtheme { return $_[0]->{moodthemeid}; }

# user method for expiring moodtheme cache
# NOTE: any code that updates the moodthemes table needs to use this!
sub delete_moodtheme_cache { $_[0]->memc_delete( 'moodthemes' ); }

# user method for deleting existing mood theme
sub delete_moodtheme {
    my ( $u, $id ) = @_;
    my $dbh = LJ::get_db_writer() or return;
    my $rv = $dbh->do( "DELETE FROM moodthemes WHERE moodthemeid = ?" .
                       " AND ownerid = ?", undef, $id, $u->userid );
    die $dbh->errstr if $dbh->err;
    return unless $rv;  # will return if $u doesn't own this theme
    $dbh->do( "DELETE FROM moodthemedata WHERE moodthemeid = ?", undef, $id );
    die $dbh->errstr if $dbh->err;

    # Kill any memcache data about this moodtheme
    DW::Mood->clear_cache( $id );
    $u->delete_moodtheme_cache;

    return 1;
}

# user method for creating new mood theme
# args: theme name, description, errorref
# returns: id of new theme or undef on failure
sub create_moodtheme {
    my ( $u, $name, $desc, $err ) = @_;
    my $errsub = sub { $$err = $_[0] if ref $err; return undef };

    return $errsub->( LJ::Lang::ml( "/manage/moodthemes.bml.error.cantcreatethemes" ) )
        unless $u->can_create_moodthemes;
    return $errsub->( LJ::Lang::ml( "/manage/moodthemes.bml.error.nonamegiven" ) )
        unless $name;
    $desc ||= '';

    my $dbh = LJ::get_db_writer() or
        return $errsub->( LJ::Lang::ml( "error.nodb" ) );
    my $sth = $dbh->prepare( "INSERT INTO moodthemes " .
        "(ownerid, name, des, is_public) VALUES (?, ?, ?, 'N')" );
    $sth->execute( $u->id, $name, $desc ) or
        return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr );

    $u->delete_moodtheme_cache;
    return $dbh->{mysql_insertid};
}


1;
