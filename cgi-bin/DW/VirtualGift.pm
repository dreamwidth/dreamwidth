#!/usr/bin/perl
#
# DW::VirtualGift - Provide virtual gifts for users
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::VirtualGift;

use strict;
use warnings;

use constant PROPLIST => qw/ vgiftid name created_t creatorid active
                             approved approved_by approved_why
                             custom featured description cost
                             mime_small mime_large /;
# NOTE: remember to update &validate if you add new props

use base 'LJ::MemCacheable';
# MemCacheable methods ###################################
   *_memcache_id                = \&id;                  #
   *_memcache_hashref_to_object = \&absorb_row;          #
sub _memcache_key_prefix   { 'vgift_obj' }               #
sub _memcache_expires      { 24*3600 }                   #
sub _memcache_stored_props { return ( '1', PROPLIST ) }  #
# end MemCacheable methods ###############################

use Digest::MD5 qw/ md5_hex /;
use DW::BlobStore;

use LJ::Global::Constants;

# Because events use this module, Perl warns about redefined subroutines.
{
    no warnings 'redefine';
    use LJ::Event::VgiftApproved;
}


# TABLE OF CONTENTS
#
# 1. Constructor methods (anything that modifies db values)
# 2. Accessor methods (simple db reads and booleans)
# 3. Memcache methods (for referencing & expiring keys)
# 4. Validation methods (for checking user-supplied data)
# 5. Aggregate methods (for mass lookups)
# 6. End-user display methods (making things look purty)
# 7. Notification methods (let people know about things)

# Transaction methods moved to DW::VirtualGiftTransaction



# 1. Constructor methods
sub new {
    my ( $class, $id ) = @_;
    return undef if !$id || $id !~ /^\d+$/;
    my $self = { vgiftid => $id };
    bless $self, ( ref $class ? ref $class : $class );
    return $self;
}

sub _init {
    # This should only be called by the "create" method.
    # It grabs an ID for the new vgift before calling the "new" method.
    my ( $class, $err ) = @_;
    if ( ref $class ) {
        $$err = LJ::Lang::ml('vgift.error.init.reuse') if $err;
        return undef;
    }

    my $vgiftid = LJ::alloc_global_counter('V');
    unless ( $vgiftid ) {
        $$err = LJ::Lang::ml('vgift.error.init.alloc') if $err;
        return undef;
    }

    # we have an id, now initialize the object
    return $class->new( $vgiftid );
}

sub create {
    # opts are values for object properties as defined in PROPLIST.
    # also allowed: 'error' which should be a scalar reference;
    # 'img_small' & 'img_large' which should contain raw
    # image data to be stored in media storage (blobstore).
    my ( $class, %opts ) = @_;
    my %vg;  # hash for storing row data
    foreach ( PROPLIST ) {
        $vg{$_} = $opts{$_} if defined $opts{$_};
        # translate Perl nulls into MySQL nulls
        $vg{$_} = undef if exists $vg{$_} && $vg{$_} eq '';
    }
    # don't allow created_t to be overridden
    $vg{created_t} = time;

    # enforce active/approved defaults for new gifts
    if ( $vg{custom} && $vg{custom} eq 'Y' ) {
        $vg{active} = 'Y';
        $vg{approved} = 'N';
    } else {
        delete @vg{qw( active approved )};
    }

    # name is required
    unless ( $vg{name} ) {
        ${$opts{error}} = LJ::Lang::ml('vgift.error.create.noname');
        return undef;
    }

    # name must be unique
    my $dbr = LJ::get_db_reader();
    my $exists = $dbr->selectrow_array( "SELECT name FROM vgift_ids " .
                                        "WHERE name=?", undef, $vg{name} );
    die $dbr->errstr if $dbr->err;

    if ( $exists ) {
        ${$opts{error}} = LJ::Lang::ml('vgift.error.create.samename');
        return undef;
    }
    undef $dbr;  # release handle

    # creatorid defaults to the logged in user if there is one
    $vg{creatorid} = LJ::get_remote() unless defined $vg{creatorid};
    $vg{creatorid} = LJ::want_userid( $vg{creatorid} );

    # validate input
    return undef unless $class->validate_all( $opts{error}, \%vg );

    # now that we're reasonably certain we have good data,
    # grab an id and get to work
    my $self = $class->_init( $opts{error} ) or return undef;
    $vg{vgiftid} = $self->id;

    # save pictures here, after getting id but before updating DB
    return undef unless $self->_savepics( \%vg, %opts );

    # construct SQL statement
    my $dbh = LJ::get_db_writer();
    my $props = join( ', ', keys %vg );
    my $qs = join( ', ', map { '?' } keys %vg );
    $dbh->do( "INSERT INTO vgift_ids ($props) VALUES ($qs)", undef, values %vg );
    die $dbh->errstr if $dbh->err;

    # initialize this gift in the vgift_counts table
    $dbh->do( "INSERT INTO vgift_counts (vgiftid,count) VALUES (?,0)",
              undef, $self->id );
    die $dbh->errstr if $dbh->err;

    $self->_expire_aggregate_keys;
    return $self->absorb_row( \%vg );
}

sub _savepic {
    my ( $self, $size, $data ) = @_;
    return undef unless $data && $self->id;

    # img_mogkey checks $size, don't need to explicitly check here
    return undef unless my $key = $self->img_mogkey( $size );

    my %mime = ( JPG => 'image/jpeg',
                 GIF => 'image/gif',
                 PNG => 'image/png',
               );
    my ( undef, undef, $filetype ) = Image::Size::imgsize( $data );
    return undef unless $mime{$filetype};

    return undef unless
        DW::BlobStore->store( vgifts => $key, $data );

    return $mime{$filetype};
}

sub _savepics {
    my ( $self, $ref, %opts ) = @_;
    return undef unless $self->id;
    return undef unless ref $ref eq 'HASH';

    my $mime_small = $self->_savepic( 'small', $opts{img_small} );
    if ( $opts{img_small} && ! $mime_small ) {
        ${$opts{error}} = LJ::Lang::ml( 'vgift.error.savepics',
                                   { size => 'small' } );
        return undef;
    }
    my $mime_large = $self->_savepic( 'large', $opts{img_large} );
    if ( $opts{img_large} && ! $mime_large ) {
        ${$opts{error}} = LJ::Lang::ml( 'vgift.error.savepics',
                                   { size => 'large' } );
        return undef;
    }
    $ref->{mime_small} = $mime_small if $mime_small;
    $ref->{mime_large} = $mime_large if $mime_large;

    return 1;
}

sub edit {
    # opts are values for object properties as defined in PROPLIST.
    # also allowed: 'error' which should be a scalar reference;
    # 'img_small' & 'img_large' which should contain raw
    # image data to be stored in media storage (blobstore).
    my ( $self, %opts ) = @_;
    return undef unless $self->id;

    my %vg;  # hash for storing row data
    foreach ( PROPLIST ) {
        $vg{$_} = $opts{$_} if defined $opts{$_};
        # translate Perl nulls into MySQL nulls
        $vg{$_} = undef if exists $vg{$_} && $vg{$_} eq '';
    }
    # don't allow created_t or vgiftid to be overridden
    delete @vg{qw( created_t vgiftid )};

    $vg{creatorid} = LJ::want_userid( $vg{creatorid} )
        if defined $vg{creatorid};

    # save pictures first
    return undef unless $self->_savepics( \%vg, %opts );

    return $self unless %vg;  # no DB updates

    # validate input
    return undef unless $self->validate_all( $opts{error}, \%vg );

    # expire aggregate keys based on current values
    # (we expire again below, but that is based on the new values)
    $self->_expire_aggregate_keys;

    # construct SQL statement with new values
    my $dbh = LJ::get_db_writer();
    my @keys = keys %vg;
    my $props = join( ', ', map { "$_=?" } @keys );
    $dbh->do( "UPDATE vgift_ids SET $props WHERE vgiftid=?",
              undef, values %vg, $self->id );
    die $dbh->errstr if $dbh->err;

    # update objects in memory
    $self->{$_} = $vg{$_} foreach @keys;
    $self->_remove_from_memcache;  # LJ::MemCacheable
    $self->_expire_relevant_keys( @keys );

    return $self;
}

sub mark_active   { $_[0]->edit( active => 'Y' ) }
sub mark_inactive { $_[0]->edit( active => 'N' ) }

sub mark_sold {
    my ( $self ) = @_;
    return undef unless $self->id;

    my $dbh = LJ::get_db_writer();
    $dbh->do( "UPDATE vgift_counts SET count=count+1 WHERE vgiftid=?",
              undef, $self->id );
    die $dbh->errstr if $dbh->err;

    LJ::MemCache::delete( $self->num_sold_memkey );
    return $self;
}

sub tags {
    # taglist is a comma separated string of tagnames.
    # opts allowed: 'error' which should be a scalar reference;
    # 'autovivify' boolean allowing new tags to be created in the DB.
    # returns array of tagnames (or arrayref in scalar context)
    my ( $self, $taglist, %opts ) = @_;
    return undef unless my $id = $self->id;
    return undef if $self->is_custom;  # can't tag custom gifts
    my $autovivify = $opts{autovivify};

    my $error = sub {
        ${$opts{error}} = shift if $opts{error};
        return undef;
    };

    my $tagnames;

    if ( defined $taglist ) {  # save new tags
        # taglist can be an arrayref or a comma separated string
        my @newtags = ref $taglist eq 'ARRAY' ? @$taglist :
                      LJ::interest_string_to_list( $taglist );
        # vgift tags are similar enough to interests that we can reuse code
        unless ( @newtags ) {  # just wipe existing tags and return
            $self->_tagwipe;
            return wantarray ? () : [];
        }

        # make sure the tags we've specified are valid
        my @valid_tags;
        foreach my $tag ( @newtags ) {
            my ( $bytes, $chars ) = LJ::text_length( $tag );
            next if $bytes > LJ::BMAX_SITEKEYWORD;
            next if $chars > LJ::CMAX_SITEKEYWORD;
            next if $tag =~ /[\<\>]/;
            push @valid_tags, $tag;
        }

        my %invalid_tags = map { $_ => 1 } @newtags;
        delete @invalid_tags{@valid_tags};

        if ( %invalid_tags ) {
            return $error->( LJ::Lang::ml( 'vgift.error.tags.invalid', { taglist =>
                    $self->display_taglist( [ keys %invalid_tags ] ) } ) );
        }

        # this shouldn't be possible, but just in case...
        return $error->( LJ::Lang::ml('vgift.error.tags.novalidtags') )
            unless @valid_tags;

        $tagnames = \@valid_tags;  # save for later

        # At this point we have the list of tag names to return,
        # but we still need to store the tag ids in the database.

        my $dbr = LJ::get_db_reader();
        my $qs = join( ', ', map { '?' } @valid_tags );
        my $dbdata = $dbr->selectall_arrayref( "SELECT keyword, kwid FROM sitekeywords " .
                                               "WHERE keyword IN ($qs)", undef, @valid_tags );
        die $dbr->errstr if $dbr->err;

        my %dbtags = map { $_->[0] => $_->[1] } @$dbdata;
        foreach my $tag ( @valid_tags ) {
            next if $dbtags{$tag};
            # try to create the tag if it didn't already exist
            my $tagid = LJ::get_sitekeyword_id( $tag, $autovivify, allowmixedcase => 1 );
            return $error->( LJ::Lang::ml( 'vgift.error.tags.create',
                { tag => LJ::ehtml( $tag ) } ) ) unless $tagid;
            $dbtags{$tag} = $tagid;
        }

        # delete previous tags & clear memcached tag data
        $self->_tagwipe;

        # construct SQL statement for adding new tags
        my $dbh = LJ::get_db_writer();
        my @tagids = values %dbtags;
        my $qps = join( ', ', map { '(?,?)' } @tagids );
        my @vals = map { ( $id, $_ ) } @tagids;
        $dbh->do( "INSERT INTO vgift_tags (vgiftid, tagid) VALUES $qps", undef, @vals );
        die $dbh->errstr if $dbh->err;

    } else {  # fetch existing tags
        my $tags = LJ::MemCache::get( $self->taglist_memkey );
        if ( $tags && ref $tags eq "ARRAY" ) {
            return wantarray ? @$tags : $tags;  # fast path out
        }
        my $dbr = LJ::get_db_reader();
        $tagnames = $dbr->selectcol_arrayref(
            "SELECT keyword FROM sitekeywords WHERE kwid IN " .
            "(SELECT tagid FROM vgift_tags WHERE vgiftid=$id)"
            );
        die $dbr->errstr if $dbr->err;
    }

    LJ::MemCache::set( $self->taglist_memkey, $tagnames, 3600*24 );
    return wantarray ? @$tagnames : $tagnames;
}

sub _tagwipe {
    my ( $self, $tagid ) = @_;
    return undef unless my $id = $self->id;

    # Acts on a single gift.  Remove $tagid from this gift,
    # or if no $tagid specified, remove ALL tags from this gift.

    my $dbh = LJ::get_db_writer();
    if ( $tagid ) {
        $dbh->do( "DELETE FROM vgift_tags WHERE vgiftid=$id AND tagid=?",
                  undef, $tagid );
    } else {
        $dbh->do( "DELETE FROM vgift_tags WHERE vgiftid=$id" );
    }
    die $dbh->errstr if $dbh->err;
    $self->_expire_taglist_keys;
    return 1;
}

sub remove_tag_by_id {
    my ( $self, $tagid ) = @_;
    return undef unless $tagid && $tagid =~ /^\d+$/;
    return $self->_tagwipe( $tagid );
}

sub alter_tag {
    my ( $self, $tagname, $newname ) = @_;

    # For every gift that has $tagname, remove that tag.
    # If $newname is provided, replace $tagname with $newname.

    my $oldid = $self->get_tagid( $tagname );
    return undef unless $oldid;

    # We need to cache @vgs here before we do the SQL update,
    # so that we remember which gifts we were acting on
    # once the tags have been rewritten in the database.

    my @vgs = $self->list_tagged_with( $tagname );
    my $dbh = LJ::get_db_writer();

    if ( $newname ) {
        my $newid = $self->create_tag( $newname );
        return undef unless $newid;

        $dbh->do( "UPDATE vgift_tags SET tagid=$newid WHERE tagid=$oldid" );
        die $dbh->errstr if $dbh->err;
        $dbh->do( "UPDATE vgift_tagpriv SET tagid=$newid WHERE tagid=$oldid" );
        die $dbh->errstr if $dbh->err;

    } else {
        $dbh->do( "DELETE FROM vgift_tags WHERE tagid=$oldid" );
        die $dbh->errstr if $dbh->err;
        $dbh->do( "DELETE FROM vgift_tagpriv WHERE tagid=$oldid" );
        die $dbh->errstr if $dbh->err;
    }

    $self->_expire_taglist_keys( @vgs );
    return 1;
}

sub create_tag {
    my ( $self, $tagname ) = @_;
    return LJ::get_sitekeyword_id( $tagname, 1, allowmixedcase => 1 );
}

sub _addremove_tagpriv {
    my ( $self, $sql, $tagname, $privname, $arg ) = @_;
    return undef unless $sql && $tagname && $privname;
    my $tagid = $self->get_tagid( $tagname ) or return undef;
    my $prlid = $self->validate_priv( $privname ) or return undef;

    my $dbh = LJ::get_db_writer();
    $dbh->do( $sql, undef, $tagid, $prlid, $arg );
    die $dbh->errstr if $dbh->err;
    return 1;
}

sub add_priv_to_tag {
    my $self = shift;
    return $self->_addremove_tagpriv(
        "INSERT IGNORE INTO vgift_tagpriv (tagid, prlid, arg)" .
        " VALUES (?,?,?)", @_ );
}

sub remove_priv_from_tag {
    my $self = shift;
    return $self->_addremove_tagpriv(
        "DELETE FROM vgift_tagpriv WHERE tagid=? AND prlid=?" .
        " AND arg=?", @_ );
}

sub delete {
    my ( $self, $u ) = @_;
    return undef unless my $id = $self->id;
    $u = $self->creator unless LJ::isu( $u );
    return undef unless $self->can_be_deleted_by( $u );

    # delete pictures from storage
    DW::BlobStore->delete( vgifts => $self->img_mogkey( 'large' ) );
    DW::BlobStore->delete( vgifts => $self->img_mogkey( 'small' ) );

    # wipe the relevant rows from the database
    $self->_tagwipe;
    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM vgift_ids WHERE vgiftid=$id" );
    die $dbh->errstr if $dbh->err;
    $dbh->do( "DELETE FROM vgift_counts WHERE vgiftid=$id" );
    die $dbh->errstr if $dbh->err;

    # wipe the relevant keys from memcache
    LJ::MemCache::delete( $self->num_sold_memkey );
    $self->_expire_relevant_keys;
    $self->_remove_from_memcache;  # LJ::MemCacheable

    return 1;
}


# 2. Accessor methods
sub id { return $_[0]->{vgiftid} }
*vgiftid = \&id;

sub name { return $_[0]->_access( 'name' ) || ''; }
sub name_ehtml { return LJ::ehtml( $_[0]->name ); }
sub description { return $_[0]->_access( 'description' ) || ''; }
sub description_ehtml { return LJ::ehtml( $_[0]->description ); }

sub cost { return $_[0]->_access( 'cost' )           ||  0  }
sub active { return $_[0]->_access( 'active' )       || 'N' }
sub custom { return $_[0]->_access( 'custom' )       || 'N' }
sub featured { return $_[0]->_access( 'featured' )   || 'N' }
sub creatorid { return $_[0]->_access( 'creatorid' ) ||  0  }
sub created_t { return $_[0]->_access( 'created_t' ) }

sub creator { return LJ::load_userid( $_[0]->creatorid ) }
sub is_inactive { return $_[0]->active eq 'N' ? 1 : 0 }
sub is_active { return $_[0]->active eq 'Y' ? 1 : 0 }
sub is_custom { return $_[0]->custom eq 'Y' ? 1 : 0 }
sub is_featured { return $_[0]->featured eq 'Y' ? 1 : 0 }
sub is_free { return $_[0]->cost ? 0 : 1 }

sub approved { return $_[0]->_access( 'approved' )         || '' }
sub approved_by { return $_[0]->_access( 'approved_by' )   || '' }
sub approved_why { return $_[0]->_access( 'approved_why' ) || '' }
sub is_approved { return $_[0]->approved eq 'Y' ? 1 : 0 }
sub is_rejected { return $_[0]->approved eq 'N' ? 1 : 0 }
sub is_queued   { return $_[0]->approved ? 0 : 1 }
sub approver { return LJ::load_userid( $_[0]->approved_by ) }

sub img_small { return $_[0]->_loadpic( 'small' ) }
sub img_large { return $_[0]->_loadpic( 'large' ) }
sub img_small_html { return $_[0]->_loadpic_html( 'small' ) }
sub img_large_html { return $_[0]->_loadpic_html( 'large' ) }
sub mime_small { return $_[0]->_access( 'mime_small' ) }
sub mime_large { return $_[0]->_access( 'mime_large' ) }
sub mime_type {
    my ( $self, $size ) = @_;
    return undef unless $size;
    return $self->mime_small if $size eq 'small';
    return $self->mime_large if $size eq 'large';
    return undef;  # invalid size
}

sub _access {
    my ( $self, $prop ) = @_;
    return undef unless $prop = lc $prop;
    return $self->{$prop} if defined $self->{$prop};
    $self->_load;
    return $self->{$prop};
}

sub _load {
    my $self = shift;
    return undef unless $self->id;

    return $self if $self->{_loaded};  # from absorb_row
    return $self if $self->_load_from_memcache;  # LJ::MemCacheable

    # find row in database
    my $dbr = LJ::get_db_reader();
    my $props = join( ', ', PROPLIST );

    my $row = $dbr->selectrow_hashref(
        "SELECT $props FROM vgift_ids WHERE vgiftid=?",
        undef, $self->id );
    die $dbr->errstr if $dbr->err;
    return undef unless $row;

    # store retrieved data
    $self->absorb_row( $row );
    $self->_store_to_memcache;  # LJ::MemCacheable

    return $self;
}

sub absorb_row {
    my ( $self, $row ) = @_;
    return undef unless $row;

    $self->{$_} = $row->{$_} foreach PROPLIST;
    $self->{_loaded} = 1;
    return $self;
}

sub _loadpic {
    my ( $self, $size ) = @_;

    return undef unless my $id = $self->id;
    return undef unless $self->mime_type( $size );

    return "$LJ::SITEROOT/vgift/$id/$size";
}

sub _loadpic_html {
    my ( $self, $size ) = @_;

    return '' unless $size && $size =~ /^(small|large)$/;
    return '' unless $self->id;
    my $url = $self->_loadpic( $size );
    return LJ::Lang::ml( 'vgift.error.loadpic', { size => $size } )
        unless $url;

    my $name = $self->name_ehtml;
    my $desc = $self->description_ehtml;
    return "<img alt='$desc' title='$name' src='$url' />";
}

sub img_mogkey {
    my ( $self, $size ) = @_;
    return undef unless $size && $size =~ /^(small|large)$/;
    return undef unless my $id = $self->id;
    return "vgift_img_$size:$id";
}

# tagnames and interests are both in sitekeywords
sub get_tagname { return LJ::get_interest( $_[1] ) }

sub get_tagid { return LJ::get_sitekeyword_id( $_[1], 0, allowmixedcase => 1 ) }

sub can_be_approved_by {
    my ( $self, $u ) = @_;
    $u = LJ::want_user( $u ) or return undef;

    # creators can't approve their own gifts
    return 0 if $u->equals( $self->creator );

    # otherwise, same privileges as for edits
    return $self->can_be_edited_by( $u );
}

sub can_be_edited_by {
    my ( $self, $u ) = @_;

    # don't allow editing of gifts that are active in the shop
    return 0 if $self->is_active;

    $u = LJ::want_user( $u ) or return undef;
    # creators can edit their own inactive gifts
    return 1 if $u->equals( $self->creator );
    # siteadmins can edit any inactive gift
    return 1 if $u->has_priv( 'siteadmin', 'vgifts' );

    return 0;
}

sub can_be_deleted_by {
    my $self = shift;

    # if the vgift has been purchased, don't allow
    return 0 if $self->num_sold;

    # otherwise, same privileges as for edits
    return $self->can_be_edited_by( @_ );
}

sub checksum {
    my ( $self ) = @_;
    return unless $self->_load;

    # generate a checksum based on attribute values
    my @attrvals;
    foreach my $prop ( PROPLIST ) {
        push @attrvals, $self->{$prop} || 'NULL';
    }

    foreach my $size ( qw( large small ) ) {
        my $data = DW::BlobStore->retrieve( vgifts => $self->img_mogkey( $size ) );
        push @attrvals, ref $data eq 'SCALAR' ? $$data : 'NULL';
    }

    return md5_hex( join ' ', @attrvals );
}

sub created_ago_text {
    my ( $self ) = @_;
    return '' unless $self->id;
    return LJ::diff_ago_text( $self->created_t );
}

sub is_untagged {
    my ( $self ) = @_;
    my $id = $self->id or return undef;
    foreach ( $self->list_untagged ) {
        return 1 if $id == $_->id;
    }
    return 0;  # not in the untagged list
}

sub num_sold {
    my ( $self ) = @_;
    my $id = $self->id or return undef;
    my $count = LJ::MemCache::get( $self->num_sold_memkey );
    return $count if defined $count;

    # check db if not in cache
    my $dbr = LJ::get_db_reader();
    $count = $dbr->selectrow_array(
             "SELECT count FROM vgift_counts WHERE vgiftid=$id" ) || 0;
    die $dbr->errstr if $dbr->err;

    LJ::MemCache::set( $self->num_sold_memkey, $count, 3600*24 );
    return $count;
}


# 3. Memcache methods
sub _expire_relevant_keys {
    # this is called from delete/edit to expire specific keys
    # relevant to the particular object being acted on.
    my ( $self, @props ) = @_;
    return undef unless $self->id;
    @props = PROPLIST unless @props;
    my %prop = map { $_ => 1 } @props;

    if ( $prop{mime_small} ) {
        # expire memcache for img_small (set in Apache::LiveJournal)
        LJ::MemCache::delete( $self->img_memkey( 'small' ) );
    }

    if ( $prop{mime_large} ) {
        # expire memcache for img_large (set in Apache::LiveJournal)
        LJ::MemCache::delete( $self->img_memkey( 'large' ) );
    }

    return $self->_expire_aggregate_keys( @props );
}

sub _expire_aggregate_keys {
    # this is called from create/edit to expire aggregate keys
    # based on specified values, or from _expire_relevant_keys.
    my ( $self, @props ) = @_;
    return undef unless $self->id;
    @props = PROPLIST unless @props;
    my %prop = map { $_ => 1 } @props;

    if ( $prop{creatorid} ) {
        # expire memcache for list_created_by
        LJ::MemCache::delete( $self->created_by_memkey );
    }

    if ( $prop{creatorid} || $prop{active} || $prop{approved} ) {
        # expire memcache for fetch_creatorcounts
        LJ::MemCache::delete( $self->creatorcounts_memkey );
    }

    return $self;
}

sub _expire_taglist_keys {
    # this is called from _tagwipe to expire tag-related keys.
    my ( $self, @vgs ) = @_;  # may pass in additional vgift objects
    @vgs = ( $self ) unless @vgs;
    foreach ( @vgs ) {
        next unless $_->id;
        # expire memcache for vgift list of tags
        LJ::MemCache::delete( $_->taglist_memkey );
    }
    # the rest are aggregate and only need to be expired once

    # expire memcache for fetch_tagcounts methods
    LJ::MemCache::delete( $self->tagcounts_approved_memkey );
    LJ::MemCache::delete( $self->tagcounts_active_memkey );
    # expire memcache for list_untagged
    LJ::MemCache::delete( $self->untagged_memkey );
    # expire memcache for list_nonpriv_tags
    LJ::MemCache::delete( $self->nonpriv_tags_memkey );
    # we can't force expiry of all individual user taglists
    # or tagid lists - these are uncached every few minutes

    return $self;
}

sub img_memkey {
    my ( $self, $size ) = @_;
    return undef unless $size && $size =~ /^(small|large)$/;
    return undef unless my $id = $self->id;
    return [$id, "mogp.vg.$size.$id"];
}

sub created_by_memkey {
    my ( $self, $uid )  = @_;
    $uid = $self->creatorid unless defined $uid;
    return [$uid, "vgift.creatorid.$uid"];
}

sub taglist_memkey {
    my ( $self )  = @_;
    return undef unless my $id = $self->id;
    return [$id, "vgift.taglist.$id"];  # list of tags for this giftid
}

sub tagged_with_memkey {
    my ( $self, $tagid )  = @_;
    return undef unless defined $tagid;
    return [$tagid, "vgift.tagid.$tagid"];  # list of gifts for this tagid
}

sub num_sold_memkey {
    my ( $self )  = @_;
    return undef unless my $id = $self->id;
    return [$id, "vgift.count.$id"];
}

sub untagged_memkey { return 'vgift_untagged'; }

sub tagcounts_approved_memkey { return 'vgift_tagcounts_approved'; }

sub tagcounts_active_memkey { return 'vgift_tagcounts_active'; }

sub creatorcounts_memkey { return 'vgift_creatorcounts'; }

sub nonpriv_tags_memkey { return 'vgift_nonpriv_tags'; }


# 4. Validation methods
sub validate_all {
    my ( $self, $err, $arg ) = @_;
    # err is optional scalar reference for error message.
    # arg is optional hashref; if missing, validate the object.
    my $data = $arg || $self;
    my $ok = 1;
    $ok &&= $self->validate( $_ => $data->{$_}, $err ) foreach PROPLIST;
    return $ok;
}

sub validate {
    my ( $self, $key, $val, $err ) = @_;

    return $self->_valid_mime( $val, $err, $key ) if $key eq 'mime_small';
    return $self->_valid_mime( $val, $err, $key ) if $key eq 'mime_large';
    return $self->_valid_text( $val, $err, $key ) if $key eq 'description';
    return $self->_valid_text( $val, $err, $key ) if $key eq 'approved_why';
    return $self->_valid_name( $val, $err, $key ) if $key eq 'name';
    return $self->_valid_y_n( $val, $err, $key )  if $key eq 'active';
    return $self->_valid_y_n( $val, $err, $key )  if $key eq 'custom';
    return $self->_valid_y_n( $val, $err, $key )  if $key eq 'featured';
    return $self->_valid_y_n( $val, $err, $key )  if $key eq 'approved';
    return $self->_valid_uid( $val, $err, $key )  if $key eq 'approved_by';
    return $self->_valid_uid( $val, $err, $key )  if $key eq 'creatorid';
    return $self->_valid_int( $val, $err, $key )  if $key eq 'vgiftid';
    return $self->_valid_int( $val, $err, $key )  if $key eq 'created_t';
    return $self->_valid_int( $val, $err, $key )  if $key eq 'cost';

    # default case if no test defined for $key: assume invalid
    $$err = LJ::Lang::ml( 'vgift.error.validate.property', { key => $key } );
    return 0;
}

sub _valid_name {
    my ( $self, $name, $err ) = @_;

    return 1 unless $name;

    if ( $name !~ /\S/ || $name =~ /[\r\n\t\0]/ ) {
        $$err = LJ::Lang::ml('vgift.error.validate.name');
        return 0;
    }
    return $self->_valid_text( $name, $err, 'name' );
}

sub _valid_mime {
    my ( $self, $mime, $err, $prop ) = @_;

    if ( $mime && $mime !~ /^image\// ) {
        $$err = LJ::Lang::ml( 'vgift.error.validate.value', { prop => $prop } );
        return 0;
    }
    return 1;
}

sub _valid_int {
    my ( $self, $int, $err, $prop ) = @_;

    if ( $int && $int !~ /^\d+$/ ) {
        $$err = LJ::Lang::ml( 'vgift.error.validate.value', { prop => $prop } );
        return 0;
    }
    return 1;
}

sub _valid_y_n {
    my ( $self, $yn, $err, $prop ) = @_;

    if ( $yn && $yn !~ /^[YN]$/i ) {
        $$err = LJ::Lang::ml( 'vgift.error.validate.value', { prop => $prop } );
        return 0;
    }
    return 1;
}

sub _valid_uid {
    my ( $self, $uid, $err, $prop ) = @_;

    if ( defined $uid && ! LJ::load_userid( $uid ) ) {
        $$err = LJ::Lang::ml( 'vgift.error.validate.value', { prop => $prop } );
        return 0;
    }
    # Not going to check user privileges at this level.
    # Also, uid 0 ought to be valid (indicates created by "the site").
    return 1;
}

sub _valid_text {
    my ( $self, $text, $err, $prop ) = @_;

    unless ( LJ::text_in( $text ) ) {
        $$err = LJ::Lang::ml( 'vgift.error.validate.text', { prop => $prop } );
        return 0;
    }
    return 1;
}

sub validate_priv {
    my ( $self, $priv ) = @_;
    return undef unless $priv;
    my $dbr = LJ::get_db_reader();
    if ( $priv =~ /^\d+$/ ) {
        # id->name
        return $dbr->selectrow_array(
            'SELECT privcode FROM priv_list WHERE prlid = ?',
                undef, $priv )
    } else {
        # name->id
        return $dbr->selectrow_array(
            'SELECT prlid FROM priv_list WHERE privcode = ?',
                undef, $priv )
    }
}


# 5. Aggregate methods
sub _findall {
    my ( $self, $sql )  = @_;
    return undef unless $sql;
    my $dbr = LJ::get_db_reader();
    my $ids = $dbr->selectcol_arrayref(
        "SELECT vgiftid FROM vgift_ids WHERE $sql ORDER BY created_t DESC" );
    die $dbr->errstr if $dbr->err;
    return undef unless $ids;
    return map { $self->new( $_ ) } @$ids;
}

sub _findall_cached {
    my ( $self, $memkey, $sql )  = @_;
    return undef unless $sql;
    return $self->_findall( $sql ) unless $memkey;

    my $data = LJ::MemCache::get( $memkey );
    return map { $self->new( $_ ) } @$data if $data && ref $data;

    # if it's not in memcache, run the query and update memcache
    my @vgs = $self->_findall( $sql );
    my @ids = map { $_->id } @vgs;
    LJ::MemCache::set( $memkey, \@ids, 24*3600 );
    return @vgs;
}

sub list_inactive { $_[0]->_findall( "active='N'" ) }

sub list_queued { $_[0]->_findall( "approved IS NULL AND custom='N'" ) }

sub list_recent {
    my ( $self, $days ) = @_;
    return undef unless defined $days && $days =~ /^\d+$/;
    my $secs = time - $days * 24 * 3600;
    return $self->_findall( "created_t > $secs AND custom='N'" );
}

sub list_created_by {
    my ( $self, $u ) = @_;
    my $uid = LJ::want_userid( $u );
    return undef unless $uid;
    my $memkey = $self->created_by_memkey( $uid );
    return $self->_findall_cached( $memkey, "creatorid=$uid AND custom='N'" );
}

sub list_untagged {
    my ( $self ) = @_;
    return $self->_findall_cached( $self->untagged_memkey,
        "custom='N' AND vgiftid NOT IN (SELECT DISTINCT vgiftid FROM vgift_tags)" );
}

sub list_tagged_with {
    my ( $self, $tagname ) = @_;
    return undef if !$tagname || ref $tagname;

    my $tagid = $self->get_tagid( $tagname );
    return undef unless $tagid;

    my $memkey = $self->tagged_with_memkey( $tagid );
    my $vgs = LJ::MemCache::get( $memkey ) || [];

    unless ( @$vgs ) {
        my $dbr = LJ::get_db_reader();
        $vgs = $dbr->selectcol_arrayref( "SELECT vgiftid FROM vgift_tags " .
                                         "WHERE tagid=$tagid " .
                                         "ORDER BY vgiftid DESC" );
        die $dbr->errstr if $dbr->err;
        LJ::MemCache::set( $memkey, $vgs, 600 );
    }

    return map { $self->new( $_ ) } @$vgs;
}

sub _fetch_tagcounts {
    my ( $self, $memkey, $select ) = @_;
    my $counts = LJ::MemCache::get( $memkey ) || {};

    unless ( %$counts ) {
        my $dbr = LJ::get_db_reader();
        my $rows = $dbr->selectall_arrayref(
            "SELECT sk.keyword, COUNT(vt.vgiftid) " .
            "FROM sitekeywords AS sk, vgift_tags AS vt, vgift_ids AS vi " .
            "WHERE sk.kwid = vt.tagid AND vi.vgiftid = vt.vgiftid " .
            "AND vi.$select GROUP BY keyword ORDER BY keyword ASC" );
        die $dbr->errstr if $dbr->err;

        $counts = { map { $_->[0] => $_->[1] } @$rows };

        # also select from vgift_tagpriv in case we've defined
        # a privileged tag with no gifts available

        my $privempty = $dbr->selectcol_arrayref(
            "SELECT keyword FROM sitekeywords WHERE kwid IN " .
            "(SELECT DISTINCT tagid FROM vgift_tagpriv WHERE tagid NOT IN ".
            "(SELECT DISTINCT tagid FROM vgift_tags)) ORDER BY keyword ASC" );
        die $dbr->errstr if $dbr->err;

        $counts->{$_} = 0 foreach @$privempty;

        LJ::MemCache::set( $memkey, $counts, 24*3600 );
    }

    return $counts;
}

sub fetch_tagcounts_approved {
    my ( $self ) = @_;
    return $self->_fetch_tagcounts( $self->tagcounts_approved_memkey,
        "approved='Y'" );
}

sub fetch_tagcounts_active {
    my ( $self ) = @_;
    return $self->_fetch_tagcounts( $self->tagcounts_active_memkey,
        "active='Y'" );
}

sub fetch_creatorcounts {
    my ( $self, $type ) = @_;
    my $memkey = $self->creatorcounts_memkey;
    my $counts = LJ::MemCache::get( $memkey ) || {};

    unless ( %$counts ) {
        my $dbr = LJ::get_db_reader();
        my $ids = $dbr->selectcol_arrayref(
            "SELECT DISTINCT creatorid FROM vgift_ids WHERE custom='N'" );
        die $dbr->errstr if $dbr->err;

        foreach my $uid ( @$ids ) {
            $counts->{$uid}->{active} = 0;
            $counts->{$uid}->{approved} = 0;

            foreach my $vg ( $self->list_created_by( $uid ) ) {
                $counts->{$uid}->{active}++ if $vg->is_active;
                $counts->{$uid}->{approved}++ if $vg->is_approved;
            }
        }

        LJ::MemCache::set( $memkey, $counts, 24*3600 );
    }

    return { map { $_ => $counts->{$_}->{$type} } keys %$counts }
        if $type && $type =~ /^(active|approved)$/;
    return $counts;
}

sub list_nonpriv_tags {
    my ( $self ) = @_;
    my $memkey = $self->nonpriv_tags_memkey;
    my $names = LJ::MemCache::get( $memkey ) || [];

    unless ( @$names ) {
        my $dbr = LJ::get_db_reader();
        $names = $dbr->selectcol_arrayref(
            "SELECT keyword FROM sitekeywords WHERE kwid IN " .
            "(SELECT DISTINCT tagid FROM vgift_tags WHERE tagid NOT IN ".
            "(SELECT DISTINCT tagid FROM vgift_tagpriv)) ORDER BY keyword ASC"
            );
        die $dbr->errstr if $dbr->err;

        LJ::MemCache::set( $memkey, $names, 24*3600 );
    }
    return wantarray ? @$names : $names;
}

sub list_tagprivs {
    my ( $self, $tagname ) = @_;
    return undef if !$tagname || ref $tagname;

    my $tagid = $self->get_tagid( $tagname );
    return undef unless $tagid;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectall_arrayref( "SELECT pl.privcode, tp.arg FROM "
                                       . "priv_list AS pl, vgift_tagpriv AS tp "
                                       . "WHERE tp.tagid=$tagid AND "
                                       . "pl.prlid=tp.prlid "
                                       . "ORDER BY privcode ASC, arg ASC" );
    die $dbr->errstr if $dbr->err;

    return @$rows;
}


# 6. End-user display methods
sub display_basic {
    my $self = shift;
    my $id = $self->id or return undef;
    my $ret = '';

    $ret .= "<h2>" . $self->name_ehtml . " (#" . $self->id . ")</h2><p><b>";
    $ret .= LJ::Lang::ml( 'vgift.display.createdby',
                     { user => $self->creator->ljuser_display,
                       ago => $self->created_ago_text } );
    $ret .= "</b></p>\n" . $self->img_small_html;
    $ret .= "<p>" . $self->description_ehtml . "</p>\n";
    $ret .= "<p><b>" . LJ::Lang::ml( 'vgift.display.label.tags' ) . "</b> ";
    $ret .= $self->display_taglist . "</p>\n";

    return $ret;
}

sub display_summary {
    my $self = shift;
    my $id = $self->id or return undef;
    my $ret = '';

    $ret .= "<div style='clear: left'></div>\n";
    $ret .= "<div style='float: left; margin-right: 2em'>";
    $ret .= $self->img_small_html;
    $ret .= "</div><p><b>";
    $ret .= $self->name_ehtml . '</b>: <em>' . $self->description_ehtml;
    $ret .= "</em><br />";
    $ret .= LJ::Lang::ml( 'vgift.display.createdby',
                     { user => $self->creator->ljuser_display,
                       ago => $self->created_ago_text } );
    $ret .= "<br />" . LJ::Lang::ml( 'vgift.display.label.cost' ) . " ";
    $ret .= $self->display_cost . "</p>";

    return $ret;
}

sub display_taglist {
    # reverse of tags method: take in arrayref, return string
    my ( $self, $tags ) = @_;
    $tags = $self->tags unless $tags && ref $tags eq 'ARRAY';
    return LJ::ehtml( join( ', ', sort { $a cmp $b } @$tags ) );
}

sub display_cost {
    my ( $self, $cost ) = @_;
    $cost ||= $self->cost unless $self->is_free;
    return $cost ? LJ::Lang::ml( 'vgift.display.cost.points', { cost => $cost } )
                 : LJ::Lang::ml( 'vgift.display.cost.free' );
}

sub display_vieweditlinks {
    my ( $self, $review ) = @_;
    my $id = $self->id or return '';
    my $linkroot = "$LJ::SITEROOT/admin/vgifts/";
    my %modes = ( view => LJ::Lang::ml('vgift.display.linktext.viewedit'),
                  review => LJ::Lang::ml('vgift.display.linktext.review'),
                  delete => LJ::Lang::ml('vgift.display.linktext.delete'),
                );
    delete $modes{review} unless $review;
    delete $modes{delete} if $self->is_active;

    my $text = "";
    foreach my $mode (qw( view review delete )) {
        next unless $modes{$mode};
        $text .= ' | ' if $text;
        $text .= "<a href='$linkroot?mode=$mode&id=$id'>$modes{$mode}</a>";
    }
    return $text;
}

sub display_viewbylink {
    my ( $self, $uid ) = @_;
    my $u = LJ::want_user( $uid ) or return '';
    my $user = $u->user;
    my $linkroot = "$LJ::SITEROOT/admin/vgifts/";
    return " <a href='$linkroot?mode=view&user=$user'>"
         . LJ::Lang::ml('vgift.display.linktext.viewgifts') . "</a>";
}

sub display_creatorlist {
    my ( $self, $num ) = @_;
    my $data = $self->fetch_creatorcounts;
    my $users = LJ::load_userids( keys %$data );
    my $sort = sub {
        $data->{$b}->{active} <=> $data->{$a}->{active} ||
        $data->{$b}->{approved} <=> $data->{$a}->{approved} ||
        $users->{$a}->user cmp $users->{$b}->user };
    my @creatorlist = map { [ $users->{$_}, $data->{$_}->{approved},
            $data->{$_}->{active} ] } sort $sort keys %$data;
    my @printlist;

    foreach ( @creatorlist ) {
        last if $num && $num == scalar @printlist;
        my ( $u, $approved, $active ) = @$_;
        my $text = '<li>';
        $text .= LJ::Lang::ml( 'vgift.display.creatorlist.counts',
            { user => $u->ljuser_display,
              approved => $approved,
              active => $active } );
        $text .= $self->display_viewbylink( $u ) . "</li>\n";
        push @printlist, $text;
    }
    return join '', @printlist;
}


# 7. Notification methods
sub notify_approved {
    my ( $self, $id ) = @_;

    if ( $id ) {  # transform class method -> object method
        $self = $self->new( $id ) or return;
    } else {  # verify object
        $id = $self->id or return;
    }
    # make sure the gift was actually reviewed
    return if $self->is_queued;

    # notify the user (inbox only, no opt-out)
    my @args = ( $self->creator, $self->approver, $self );
    LJ::Event::VgiftApproved->new( @args )->fire;
}


1;
