# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Userpic;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Digest::MD5;
use Storable;

use DW::BlobStore;
use LJ::Event::NewUserpic;
use LJ::Global::Constants;

##
## Potential properties of an LJ::Userpic object
##
# picid		: (accessors picid, id) unique identifier for the object, generated
# userid	: (accessor userid) the userid  associated with the object
# state		: state
# comment	: user submitted descriptive comment
# description	: user submitted description
# keywords	: user submitted keywords (all keywords in a single string)
# dim		: (accessors width, height, dimensions) array:[width][height]
# pictime	: pictime
# flags		: flags
# md5base64	: md5sum of of the image bitstream to prevent duplication
# ext		: file extension, corresponding to mime types
# location	: whether the image is stored in database or mogile

##
## virtual accessors
##
# url		: returns a URL directly to the userpic
# fullurl	: returns the URL used at upload time, it if exists
# altext	: "username: keyword, comment (description)"
# u, owner	: return the user object indicated by the userid

# legal image types
my %MimeTypeMap = (
    'image/gif'  => 'gif',
    'G'          => 'gif',
    'image/jpeg' => 'jpg',
    'J'          => 'jpg',
    'image/png'  => 'png',
    'P'          => 'png',
);

# all LJ::Userpics in memory
# userid -> picid -> LJ::Userpic
my %singletons;

sub reset_singletons {
    %singletons = ();
}

=head1 NAME

LJ::Userpic

=head1 Class Methods

=cut

# LJ::Userpic constructor. Returns a LJ::Userpic object.
# Return existing with userid and picid populated, or make new.
sub instance {
    my ( $class, $u, $picid ) = @_;
    $picid = 0 unless defined $picid;
    my $up;

    # return existing one, if loaded
    if ( my $us = $singletons{ $u->{userid} } ) {
        return $up if $up = $us->{$picid};
    }

    # otherwise construct a new one with the given picid
    $up = $class->_skeleton( $u, $picid );
    $singletons{ $u->{userid} }->{$picid} = $up;
    return $up;
}
*new = \&instance;

# LJ::Userpic accessor. Returns a LJ::Userpic object indicated by $picid, or
# undef if userpic doesn't exist in the db.
# TODO: add in lazy peer loading here?
sub get {
    my ( $class, $u, $picid, $opts ) = @_;
    return unless LJ::isu($u);
    return if $u->is_expunged || $u->is_suspended;
    return unless defined $picid;

    my $obj   = ref $class ? $class : $class->new( $u, $picid );
    my @cache = $class->load_user_userpics($u);

    foreach my $curr (@cache) {
        return $obj->absorb_row($curr) if $curr->{picid} == $picid;
    }

    # check the database directly (for expunged userpics,
    # which aren't included in load_user_userpics)
    return undef if $opts && $opts->{no_expunged};
    my $row = $u->selectrow_hashref(
        "SELECT userid, picid, width, height, state, "
            . "fmt, comment, description, location, url, "
            . "UNIX_TIMESTAMP(picdate) AS 'pictime', flags, md5base64 "
            . "FROM userpic2 WHERE userid=? AND picid=?",
        undef, $u->userid, $picid
    );
    return $obj->absorb_row($row) if $row;

    return undef;
}

sub _skeleton {
    my ( $class, $u, $picid ) = @_;
    $picid = 0 unless defined $picid;

    # starts out as a skeleton and gets loaded in over time, as needed:
    return bless {
        userid => $u->{userid},
        picid  => int($picid),
    };
}

# given a md5sum, load a userpic
# takes $u, $md5sum (base64)
# TODO: croak if md5sum is wrong number of bytes
sub new_from_md5 {
    my ( $class, $u, $md5sum ) = @_;
    die unless $u && length($md5sum) == 22;

    my $sth = $u->prepare( "SELECT * FROM userpic2 WHERE userid=? " . "AND md5base64=?" );
    $sth->execute( $u->{'userid'}, $md5sum );
    my $row = $sth->fetchrow_hashref
        or return undef;
    return LJ::Userpic->new_from_row($row);
}

sub preload_default_userpics {
    my ( $class, @us ) = @_;

    foreach my $u (@us) {
        my $up = $u->userpic or next;
        $up->load_row;
    }
}

sub new_from_row {
    my ( $class, $row ) = @_;
    die unless $row && $row->{userid} && $row->{picid};
    my $self = LJ::Userpic->new( LJ::load_userid( $row->{userid} ), $row->{picid} );
    $self->absorb_row($row);
    return $self;
}

=head2 C<< $class->new_from_keyword( $u, $kw ) >>

Returns the LJ::Userpic for the given keyword

=cut

sub new_from_keyword {
    my ( $class, $u, $kw ) = @_;
    return undef unless LJ::isu($u);

    my $picid = $u->get_picid_from_keyword($kw);

    return $picid ? $class->new( $u, $picid ) : undef;
}

=head2 C<< $class->new_from_mapid( $u, $mapid ) >>

Returns the LJ::Userpic for the given mapid

=cut

sub new_from_mapid {
    my ( $class, $u, $mapid ) = @_;
    return undef unless LJ::isu($u);

    my $picid = $u->get_picid_from_mapid($mapid);

    return $picid ? $class->new( $u, $picid ) : undef;
}

=head1 Instance Methods

=cut

sub valid {
    return defined $_[0]->state;
}

sub absorb_row {
    my ( $self, $row ) = @_;
    return $self unless $row && ref $row eq 'HASH';
    for my $f (
        qw(userid picid width height comment description location state url pictime flags md5base64)
        )
    {
        $self->{$f} = $row->{$f};
    }
    my $key;
    $key ||= $row->{fmt}         if exists $row->{fmt};
    $key ||= $row->{contenttype} if exists $row->{contenttype};
    $self->{_ext} = $MimeTypeMap{$key} if defined $key;
    return $self;
}

##
## accessors
##

# returns the picture ID associated with the object
sub picid {
    return $_[0]->{picid};
}

*id = \&picid;

#  returns the userid associated with the object
sub userid {
    return $_[0]->{userid};
}

# given a userpic with a known userid, return the user object
sub u {
    return LJ::load_userid( $_[0]->userid );
}

*owner = \&u;

sub inactive {
    my $self  = $_[0];
    my $state = defined $self->state ? $self->state : '';
    return $state eq 'I';
}

sub expunged {
    my $self  = $_[0];
    my $state = defined $self->state ? $self->state : '';
    return $state eq 'X';
}

sub state {
    my $self = $_[0];
    return $self->{state} if defined $self->{state};
    $self->load_row;
    return $self->{state};
}

sub comment {
    my $self = $_[0];
    return $self->{comment} if exists $self->{comment};
    $self->load_row;
    return $self->{comment};
}

sub description {
    my $self = $_[0];
    return $self->{description} if exists $self->{description};
    $self->load_row;
    return $self->{description};
}

sub width {
    my $self = $_[0];
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[0];
}

sub height {
    my $self = $_[0];
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[1];
}

sub picdate {
    return LJ::mysql_time( $_[0]->pictime );
}

sub pictime {
    return $_[0]->{pictime};
}

sub flags {
    return $_[0]->{flags};
}

sub md5base64 {
    return $_[0]->{md5base64};
}

sub mimetype {
    my $self = $_[0];
    return {
        gif => 'image/gif',
        jpg => 'image/jpeg',
        png => 'image/png'
    }->{ $self->extension };
}

sub extension {
    my $self = $_[0];
    return $self->{_ext} if $self->{_ext};
    $self->load_row;
    return $self->{_ext};
}

sub location {
    my $self = $_[0];
    return $self->{location} if $self->{location};
    $self->load_row;
    return $self->{location};
}

sub storage_key {
    my ( $self, $userid, $picid ) = @_;

    # If called on LJ::Userpic...
    return 'up:' . $self->userid . ':' . $self->picid
        if ref $self;

    # Else...
    $log->logcroak('Invalid usage of storage_key.')
        unless defined $userid && defined $picid;
    return 'up:' . ( $userid + 0 ) . ':' . ( $picid + 0 );
}

sub in_mogile {
    my $self = $_[0];
    return ( $self->location // '' ) eq 'mogile';
}

sub in_blobstore {
    my $self = $_[0];
    return ( $self->location // '' ) eq 'blobstore';
}

# returns (width, height)
sub dimensions {
    my $self = $_[0];

    # width and height probably loaded from DB
    return ( $self->{width}, $self->{height} ) if ( $self->{width} && $self->{height} );

    # if not, load them explicitly
    $self->load_row;
    return ( $self->{width}, $self->{height} );
}

sub max_allowed_bytes {
    my ( $class, $u ) = @_;
    return 61440;
}

# Returns the direct link to the uploaded userpic
sub url {
    my $self = $_[0];

    if ( my $hook_path = LJ::Hooks::run_hook( 'construct_userpic_url', $self ) ) {
        return $hook_path;
    }

    return "$LJ::USERPIC_ROOT/$self->{picid}/$self->{userid}";
}

# Returns original URL used if userpic was originally uploaded
# via a URL.
# FIXME: should be renamed to source_url
sub fullurl {
    my $self = $_[0];
    return $self->{url} if $self->{url};
    $self->load_row;
    return $self->{url};
}

# given a userpic and a keyword, return the alt text
sub alttext {
    my ( $self, $kw, $mark_default ) = @_;

    # load the alttext.
    # "username: description (keyword)"
    # If any of those are not present leave them (and their
    # affiliated punctuation) out.

    # always  include the username
    my $u   = $self->owner;
    my $alt = $u->username . ":";

    if ( $self->description ) {
        $alt .= " " . $self->description;
    }

    # 1. If there is a keyword associated with the icon, use it.
    if ( defined $kw ) {
        $alt .= " (" . $kw . ")";
    }

    # 2. If it was chosen via the default icon, show "(Default)".
    if ( $mark_default // !defined $kw ) {
        $alt .= " (Default)";
    }

    return LJ::ehtml($alt);

}

# given a userpic and a keyword, return the title text
sub titletext {
    my ( $self, $kw, $mark_default ) = @_;

    # load the titletext.
    # "username: keyword (description)"
    # If any of those are not present leave them (and their
    # affiliated punctuation) out.

    # always  include the username
    my $u     = $self->owner;
    my $title = $u->username . ":";

    # 1. If there is a keyword associated with the icon, use it.
    if ( defined $kw ) {
        $title .= " " . $kw;
    }

    # 2. If it was chosen via the default icon, show "(Default)".
    if ( $mark_default // !defined $kw ) {
        $title .= " (Default)";
    }

    if ( $self->description ) {
        $title .= " (" . $self->description . ")";
    }

    return LJ::ehtml($title);

}

# returns an image tag of this userpic
# optional parameters (which must be explicitly passed) include
# width, keyword, and user (object)
sub imgtag {
    my ( $self, %opts ) = @_;

    # if the width and keyword have been passed in  as explicit
    # parameters, set them. Otherwise, take what ever is set in
    # the userpic
    my $width   = $opts{width}   || $self->width;
    my $height  = $opts{height}  || $self->height;
    my $keyword = $opts{keyword} || $self->keywords;

    my $alttext = $self->alttext($keyword);
    my $title   = $self->titletext($keyword);

    return
          '<img src="'
        . $self->url
        . '" width="'
        . $width
        . '" height="'
        . $height
        . '" alt="'
        . $alttext
        . '" title="'
        . $title
        . '" class="userpic-img" />';
}

# FIXME: should have alt text, if it should be kept
sub imgtag_lite {
    my $self = $_[0];
    return
          '<img src="'
        . $self->url
        . '" width="'
        . $self->width
        . '" height="'
        . $self->height
        . '" class="userpic-img" />';
}

# FIXME: should have alt text, if it should be kept
sub imgtag_nosize {
    my $self = $_[0];
    return '<img src="' . $self->url . '" class="userpic-img" />';
}

# pass the decimal version of a percentage that you want to shrink/increase the userpic by
# default is 50% of original size
sub imgtag_percentagesize {
    my ( $self, $percentage ) = @_;
    $percentage ||= 0.5;

    my $width  = int( $self->width * $percentage );
    my $height = int( $self->height * $percentage );

    return
          '<img src="'
        . $self->url
        . '" width="'
        . $width
        . '" height="'
        . $height
        . '" class="userpic-img" />';
}

# pass a fixed height or width that you want to be the size of the userpic
# must include either a height or width, if both are given the smaller of the two is used
# returns the width and height attributes as a string to insert into an img tag
sub img_fixedsize {
    my ( $self, %opts ) = @_;

    my $width  = $opts{width}  || 0;
    my $height = $opts{height} || 0;

    if (   $width > 0
        && $width < $self->width
        && ( !$height || ( $width <= $height && $self->width >= $self->height ) ) )
    {
        my $ratio = $width / $self->width;
        $height = int( $self->height * $ratio );
    }
    elsif ( $height > 0 && $height < $self->height ) {
        my $ratio = $height / $self->height;
        $width = int( $self->width * $ratio );
    }
    else {
        $width  = $self->width;
        $height = $self->height;
    }

    return 'height="' . $height . '" width="' . $width . '"';
}

# in scalar context returns comma-seperated list of keywords or "pic#12345" if no keywords defined
# in list context returns list of keywords ( (pic#12345) if none defined )
# opts: 'raw' = return '' instead of 'pic#12345'
sub keywords {
    my ( $self, %opts ) = @_;

    my $raw = delete $opts{raw} || undef;

    $log->logcroak("Invalid opts passed to LJ::Userpic::keywords")
        if keys %opts;

    my $u = $self->owner;

    my $keywords = $u->get_userpic_kw_map();

    # return keywords for this picid
    my @pickeywords = $keywords->{ $self->id } ? @{ $keywords->{ $self->id } } : ();

    if (wantarray) {

        # if list context return the array
        return ( $raw ? ('') : ( "pic#" . $self->id ) ) unless @pickeywords;

        return @pickeywords;
    }
    else {
        # if scalar context return comma-seperated list of keywords, or "pic#12345" if no keywords
        return ( $raw ? '' : "pic#" . $self->id ) unless @pickeywords;

        return join( ', ', sort { lc $a cmp lc $b } @pickeywords );
    }
}

sub imagedata {
    my $self = $_[0];
    $self->load_row or return undef;
    return undef if $self->expunged;

    my $data = DW::BlobStore->retrieve( userpics => $self->storage_key );
    return $data ? $$data : undef;
}

# get : class :: load_row : object
sub load_row {
    my $self = $_[0];

    # use class method
    return $self->get( $self->owner, $self->picid );
}

# checks request cache and memcache,
# returns: undef if nothing in cache
#          arrayref of LJ::Userpic instances if found in cache
sub get_cache {
    my ( $class, $u ) = @_;

    # check request cache first!
    # -- this gets populated when a ->load_user_userpics call happens,
    #    so the actual guts of the LJ::Userpic objects is cached in
    #    the singletons
    if ( $u->{_userpicids} ) {
        return [ map { LJ::Userpic->instance( $u, $_ ) } @{ $u->{_userpicids} } ];
    }

    my $memkey = $class->memkey($u);
    my $memval = LJ::MemCache::get($memkey);

    # nothing found in cache, return undef
    return undef unless $memval;

    my @ret = ();
    foreach my $row (@$memval) {
        my $curr = LJ::MemCache::array_to_hash( 'userpic2', $row );
        $curr->{userid} = $u->id;
        push @ret, LJ::Userpic->new_from_row($curr);
    }

    # set cache of picids on $u since we got them from memcache
    $u->{_userpicids} = [ map { $_->picid } @ret ];

    # return arrayref of LJ::Userpic instances
    return \@ret;
}

# $class->memkey( $u )
sub memkey {
    return [ $_[1]->id, "userpic2:" . $_[1]->id ];
}

sub set_cache {
    my ( $class, $u, $rows ) = @_;

    my $memkey = $class->memkey($u);
    my @vals   = map { LJ::MemCache::hash_to_array( 'userpic2', $_ ) } @$rows;
    LJ::MemCache::set( $memkey, \@vals, 60 * 30 );

    # set cache of picids on $u
    $u->{_userpicids} = [ map { $_->{picid} } @$rows ];

    return 1;
}

sub load_user_userpics {
    my ( $class, $u ) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $cache = $class->get_cache($u);
    return @$cache if $cache;

    # select all of their userpics
    my $data = $u->selectall_hashref(
        "SELECT userid, picid, width, height, state, fmt, comment,"
            . " description, location, url, UNIX_TIMESTAMP(picdate) AS 'pictime',"
            . " flags, md5base64 FROM userpic2 WHERE userid=? AND state <> 'X'",
        'picid', undef, $u->userid
    );
    die "Error loading userpics: clusterid=$u->{clusterid}, errstr=" . $u->errstr
        if $u->err;

    my @ret = sort { $a->{picid} <=> $b->{picid} } values %$data;

    # set cache if reasonable
    $class->set_cache( $u, \@ret );

    return map { $class->new_from_row($_) } @ret;
}

sub create {
    my ( $class, $u, %opts ) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $dataref     = delete $opts{data};
    my $maxbytesize = delete $opts{maxbytesize};
    my $nonotify    = delete $opts{nonotify};
    $log->logcroak("dataref not a scalarref")
        unless ref $dataref eq 'SCALAR';
    $log->logcroak( "Unknown extra options: " . join( ", ", scalar keys %opts ) )
        if %opts;

    my $err = sub {
        my $msg = $_[0];
    };

    # FIXME the filetype is supposed to be returned in the next call
    # but according to the docs of Image::Size v3.2 it does not return that value
    eval "use Image::Size;";
    my ( $w, $h, $filetype ) = Image::Size::imgsize($dataref);
    my $MAX_UPLOAD = $maxbytesize || LJ::Userpic->max_allowed_bytes($u);

    my $size     = length $$dataref;
    my $fmterror = 0;

    my @errors;
    if ( $size > $MAX_UPLOAD ) {
        push @errors,
            LJ::errobj(
            "Userpic::Bytesize",
            size => $size,
            max  => int( $MAX_UPLOAD / 1024 )
            );
    }

    unless ( $filetype eq "GIF" || $filetype eq "JPG" || $filetype eq "PNG" ) {
        push @errors, LJ::errobj( "Userpic::FileType", type => $filetype );
        $fmterror = 1;
    }

    # don't throw a dimensions error if it's the wrong file type because its dimensions will always
    # be 0x0
    unless ( $w && $w >= 1 && $w <= 100 && $h && $h >= 1 && $h <= 100 ) {
        push @errors,
            LJ::errobj(
            "Userpic::Dimensions",
            w => $w,
            h => $h
            ) unless $fmterror;
    }

    LJ::throw(@errors);

    # see if it's a duplicate, return it if it is
    my $base64 = Digest::MD5::md5_base64($$dataref);
    if ( my $dup_up = LJ::Userpic->new_from_md5( $u, $base64 ) ) {
        return $dup_up;
    }

    # start making a new onew
    my $picid = LJ::alloc_global_counter('P');

    my $contenttype = {
        'GIF' => 'G',
        'PNG' => 'P',
        'JPG' => 'J',
    }->{$filetype};

    @errors = ();    # TEMP: FIXME: remove... using exceptions

    $u->do(
        q{INSERT INTO userpic2 (
            picid, userid, fmt, width, height, picdate, md5base64, location)
        VALUES (?, ?, ?, ?, ?, NOW(), ?, ?)},
        undef, $picid, $u->userid, $contenttype, $w, $h, $base64, 'blobstore'
    );
    push @errors, $err->( $u->errstr )
        if $u->err;

    # All pictures are now stored to blobstore
    my $storage_key = LJ::Userpic->storage_key( $u->userid, $picid );
    unless ( DW::BlobStore->store( userpics => $storage_key, $dataref ) ) {
        $u->do( q{DELETE FROM userpic2 WHERE userid=? AND picid=?}, undef, $u->userid, $picid );
        push @errors, 'Failed to store userpic in blobstore.';
    }
    LJ::throw(@errors);

    # now that we've created a new pic, invalidate the user's memcached userpic info
    LJ::Userpic->delete_cache($u);

    # Fire ESN and return
    my $pic = LJ::Userpic->new( $u, $picid )
        or $log->logcroak('Error insantiating userpic after creation');
    LJ::Event::NewUserpic->new($pic)->fire
        if LJ::is_enabled('esn') && !$nonotify;
    return $pic;
}

# this will return a user's userpicfactory image stored in mogile scaled down.
# if only $size is passed, will return image scaled so the largest dimension will
# not be greater than $size. If $x1, $y1... are set then it will return the image
# scaled so the largest dimension will not be greater than 100
# all parameters are optional, default size is 640.
#
# if maxfilesize option is passed, get_upf_scaled will decrease the image quality
# until it reaches maxfilesize, in kilobytes. (only applies to the 100x100 userpic)
#
# returns [imageref, mime, width, height] on success, undef on failure.
#
# note: this will always keep the image's original aspect ratio and not distort it.
sub get_upf_scaled {
    my ( $class, %opts ) = @_;
    my $size        = delete $opts{size} || 640;
    my $x1          = delete $opts{x1};
    my $y1          = delete $opts{y1};
    my $x2          = delete $opts{x2};
    my $y2          = delete $opts{y2};
    my $border      = delete $opts{border} || 0;
    my $maxfilesize = delete $opts{maxfilesize} || 38;
    my $u           = LJ::want_user( delete $opts{userid} || delete $opts{u} ) || LJ::get_remote();
    my $mogkey      = delete $opts{mogkey};
    my $downsize_only = delete $opts{downsize_only};
    $log->logcroak("No userid or remote")
        unless $u || $mogkey;

    $maxfilesize *= 1024;

    $log->logcroak("Invalid parameters to get_upf_scaled")
        if scalar keys %opts;

    my $mode = ( $x1 || $y1 || $x2 || $y2 ) ? "crop" : "scale";

    eval "use Image::Magick (); 1;"
        or return undef;

    eval "use Image::Size (); 1;"
        or return undef;

    $mogkey ||= 'upf:' . $u->{userid};
    my $dataref = DW::BlobStore->retrieve( temp => $mogkey )
        or return undef;

    # original width/height
    my ( $ow, $oh ) = Image::Size::imgsize($dataref);
    return undef unless $ow && $oh;

    # converts an ImageMagick object to the form returned to our callers
    my $imageParams = sub {
        my $im   = $_[0];
        my $blob = $im->ImageToBlob;
        return [ \$blob, $im->Get('MIME'), $im->Get('width'), $im->Get('height') ];
    };

    # compute new width and height while keeping aspect ratio
    my $getSizedCoords = sub {
        my ( $newsize, $img ) = @_;

        my $fromw = $img ? $img->Get('width')  : $ow;
        my $fromh = $img ? $img->Get('height') : $oh;

        return ( int( $newsize * $fromw / $fromh ), $newsize ) if $fromh > $fromw;
        return ( $newsize,                          int( $newsize * $fromh / $fromw ) );
    };

    # get the "medium sized" width/height.  this is the size which
    # the user selects from
    my ( $medw, $medh ) = $getSizedCoords->($size);
    return undef unless $medw && $medh;

    # simple scaling mode
    if ( $mode eq "scale" ) {
        my $image = Image::Magick->new( size => "${medw}x${medh}" )
            or return undef;
        $image->BlobToImage($$dataref);
        unless ( $downsize_only && ( $medw > $ow || $medh > $oh ) ) {
            $image->Resize( width => $medw, height => $medh );
        }
        return $imageParams->($image);
    }

    # else, we're in 100x100 cropping mode

    # scale user coordinates  up from the medium pixelspace to full pixelspace
    $x1 *= ( $ow / $medw );
    $x2 *= ( $ow / $medw );
    $y1 *= ( $oh / $medh );
    $y2 *= ( $oh / $medh );

    # cropping dimensions from the full pixelspace
    my $tw = $x2 - $x1;
    my $th = $y2 - $y1;

    # but if their selected region in full pixelspace is 800x800 or something
    # ridiculous, no point decoding the JPEG to its full size... we can
    # decode to a smaller size so we get 100px when we crop
    my $min_dim = $tw < $th ? $tw : $th;
    my ( $decodew, $decodeh ) = ( $ow, $oh );
    my $wanted_size = 100;
    if ( $min_dim > $wanted_size ) {

        # then let's not decode the full JPEG down from its huge size
        my $de_scale = $wanted_size / $min_dim;
        $decodew = int( $de_scale * $decodew );
        $decodeh = int( $de_scale * $decodeh );
        $_ *= $de_scale foreach ( $x1, $x2, $y1, $y2 );
    }

    $_ = int($_) foreach ( $x1, $x2, $y1, $y2, $tw, $th );

    # make the pristine (uncompressed) 100x100 image
    my $timage = Image::Magick->new( size => "${decodew}x${decodeh}" )
        or return undef;
    $timage->BlobToImage($$dataref);
    $timage->Scale( width => $decodew, height => $decodeh );

    my $w   = ( $x2 - $x1 );
    my $h   = ( $y2 - $y1 );
    my $foo = $timage->Mogrify( crop => "${w}x${h}+$x1+$y1" );

    my $targetSize = $border ? 98 : 100;

    my ( $nw, $nh ) = $getSizedCoords->( $targetSize, $timage );
    $timage->Scale( width => $nw, height => $nh );

    # add border if desired
    $timage->Border( geometry => "1x1", color => 'black' ) if $border;

    foreach my $qual (qw(100 90 85 75)) {

        # work off a copy of the image so we aren't recompressing it
        my $piccopy = $timage->Clone();
        $piccopy->Set( 'quality' => $qual );
        my $ret = $imageParams->($piccopy);
        return $ret if length( ${ $ret->[0] } ) < $maxfilesize;
    }

    return undef;
}

# make this picture the default
sub make_default {
    my $self = shift;
    my $u    = $self->owner
        or die;

    $u->update_self( { defaultpicid => $self->id } );
    $u->{'defaultpicid'} = $self->id;
}

# returns true if this picture is the default userpic
sub is_default {
    my $self = $_[0];
    my $u    = $self->owner;
    return unless defined $u->{'defaultpicid'};

    return $u->{'defaultpicid'} == $self->id;
}

sub delete_cache {
    my ( $class, $u ) = @_;
    my $memkey = [ $u->{'userid'}, "upicinf:$u->{'userid'}" ];
    LJ::MemCache::delete($memkey);
    $memkey = [ $u->{'userid'}, "upiccom:$u->{'userid'}" ];
    LJ::MemCache::delete($memkey);
    $memkey = [ $u->{'userid'}, "upicurl:$u->{'userid'}" ];
    LJ::MemCache::delete($memkey);
    $memkey = [ $u->{'userid'}, "upicdes:$u->{'userid'}" ];
    LJ::MemCache::delete($memkey);

    # userpic2 rows for a given $u
    $memkey = LJ::Userpic->memkey($u);
    LJ::MemCache::delete($memkey);

    delete $u->{_userpicids};

    # clear process cache
    $LJ::CACHE_USERPIC_INFO{ $u->{'userid'} } = undef;
}

# delete this userpic
# TODO: error checking/throw errors on failure
sub delete {
    my $self = $_[0];
    local $LJ::THROW_ERRORS = 1;

    my $fail = sub {
        LJ::errobj(
            "WithSubError",
            main   => LJ::errobj("DeleteFailed"),
            suberr => $@
        )->throw;
    };

    my $u     = $self->owner;
    my $picid = $self->id;

    # userpic keywords
    eval {
        if ( $u->userpic_have_mapid ) {
            $u->do( "DELETE FROM userpicmap3 WHERE userid = ? AND picid = ? AND kwid=NULL",
                undef, $u->userid, $picid )
                or die;
            $u->do( "UPDATE userpicmap3 SET picid=NULL WHERE userid=? AND picid=?",
                undef, $u->userid, $picid )
                or die;
        }
        else {
            $u->do( "DELETE FROM userpicmap2 WHERE userid=? AND picid=?",
                undef, $u->userid, $picid )
                or die;
        }
        $u->do( "DELETE FROM userpic2 WHERE picid=? AND userid=?", undef, $picid, $u->userid )
            or die;
    };
    $fail->() if $@;

    $u->log_event( 'delete_userpic', { picid => $picid } );
    DW::BlobStore->delete( userpics => $self->storage_key );
    LJ::Userpic->delete_cache($u);

    return 1;
}

sub set_comment {
    my ( $self, $comment ) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $u = $self->owner;
    $comment = LJ::text_trim( $comment, LJ::BMAX_UPIC_COMMENT(), LJ::CMAX_UPIC_COMMENT() );
    $u->do( "UPDATE userpic2 SET comment=? WHERE userid=? AND picid=?",
        undef, $comment, $u->{'userid'}, $self->id )
        or die;
    $self->{comment} = $comment;

    LJ::Userpic->delete_cache($u);
    return 1;
}

sub set_description {
    my ( $self, $description ) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $u = $self->owner;

    #return 0 unless LJ::Userpic->user_supports_descriptions($u);
    $description =
        LJ::text_trim( $description, LJ::BMAX_UPIC_DESCRIPTION, LJ::CMAX_UPIC_DESCRIPTION );
    $u->do( "UPDATE userpic2 SET description=? WHERE userid=? AND picid=?",
        undef, $description, $u->{'userid'}, $self->id )
        or die;
    $self->{description} = $description;

    LJ::Userpic->delete_cache($u);
    return 1;
}

# instance method:  takes a string of comma-separate keywords, or an array of keywords
sub set_keywords {
    my $self = shift;

    my @keywords;
    if ( @_ > 1 ) {
        @keywords = @_;
    }
    else {
        @keywords = split( ',', $_[0] );
    }

    @keywords = grep { !/^pic\#\d+$/ } map { s/^\s+//; s/\s+$//; $_ } @keywords;

    my $u          = $self->owner;
    my $have_mapid = $u->userpic_have_mapid;

    my $sth;
    my $dbh;

    if ($have_mapid) {
        $sth = $u->prepare("SELECT kwid FROM userpicmap3 WHERE userid=? AND picid=?");
    }
    else {
        $sth = $u->prepare("SELECT kwid FROM userpicmap2 WHERE userid=? AND picid=?");
    }
    $sth->execute( $u->userid, $self->id );

    my %exist_kwids;
    while ( my ($kwid) = $sth->fetchrow_array ) {

        # This is an edge case to catch keyword changes where the existing keyword
        # is in the pic#  format.  In this case kwid is NULL and we want to
        # delete any records from userpicmap3 that involve it.
        unless ($kwid) {
            $u->do( "DELETE FROM userpicmap3 WHERE userid=? AND picid=? AND kwid IS NULL",
                undef, $u->id, $self->id );
        }

        $exist_kwids{$kwid} = 1;
    }

    my %kwid_to_mapid;
    if ($have_mapid) {
        $sth =
            $u->prepare("SELECT mapid, kwid FROM userpicmap3 WHERE userid=? AND kwid IS NOT NULL");
        $sth->execute( $u->userid );

        while ( my ( $mapid, $kwid ) = $sth->fetchrow_array ) {
            $kwid_to_mapid{$kwid} = $mapid;
        }
    }

    my ( @bind, @data, @kw_errors );
    my $c     = 0;
    my $picid = $self->{picid};

    foreach my $kw (@keywords) {
        my $kwid = $u->get_keyword_id($kw);

        next unless $kwid;    # TODO: fire some warning that keyword was bogus

        if ( ++$c > $LJ::MAX_USERPIC_KEYWORDS ) {
            push @kw_errors, $kw;
            next;
        }

        if ( exists $exist_kwids{$kwid} ) {
            delete $exist_kwids{$kwid};
        }
        else {
            if ($have_mapid) {
                $kwid_to_mapid{$kwid} ||= LJ::alloc_user_counter( $u, 'Y' );

                push @bind, '(?, ?, ?, ?)';
                push @data, $u->userid, $kwid_to_mapid{$kwid}, $kwid, $picid;
            }
            else {
                push @bind, '(?, ?, ?)';
                push @data, $u->userid, $kwid, $picid;
            }
        }
    }

    LJ::Userpic->delete_cache($u);

    foreach my $kwid ( keys %exist_kwids ) {
        if ($have_mapid) {
            $u->do( "UPDATE userpicmap3 SET picid=NULL WHERE userid=? AND picid=? AND kwid=?",
                undef, $u->id, $self->id, $kwid );
        }
        else {
            $u->do( "DELETE FROM userpicmap2 WHERE userid=? AND picid=? AND kwid=?",
                undef, $u->id, $self->id, $kwid );
        }
    }

    # save data if any
    if ( scalar @data ) {
        my $bind = join( ',', @bind );

        if ($have_mapid) {
            $u->do( "REPLACE INTO userpicmap3 (userid, mapid, kwid, picid) VALUES $bind",
                undef, @data );
        }
        else {
            $u->do( "REPLACE INTO userpicmap2 (userid, kwid, picid) VALUES $bind", undef, @data );
        }
    }

    # clear the userpic-keyword map.
    $u->clear_userpic_kw_map;

    # Let the user know about any we didn't save
    # don't throw until the end or nothing will be saved!
    if (@kw_errors) {
        my $num_words = scalar(@kw_errors);
        LJ::errobj(
            "Userpic::TooManyKeywords",
            userpic => $self,
            lost    => \@kw_errors
        )->throw;
    }

    return 1;
}

# instance method:  takes two strings of comma-separated keywords, the first
# being the new set of keywords, the second being the old set of keywords.
#
# the new keywords must be the same number as the old keywords; that is,
# if the userpic has three keywords and you want to rename them, you must
# rename them to three keywords (some can match).  otherwise there would be
# some ambiguity about which old keywords should match up with the new
# keywords.  if the number of keywords don't match, then an error is thrown
# and no changes are made to the keywords for this userpic.
#
# all new keywords must not currently be in use; you can't rename a keyword
# to a keyword currently mapped to another (or the same) userpic.  this will
# result in an error and no changes made to these keywords.
sub set_and_rename_keywords {
    my ( $self, $new_keyword_string, $orig_keyword_string ) = @_;

    my $u = $self->owner;
    LJ::errobj(
        "Userpic::RenameKeywords",
        origkw => $orig_keyword_string,
        newkw  => $new_keyword_string
        )->throw
        unless LJ::is_enabled("icon_renames") || $u->userpic_have_mapid;

    my @keywords      = split( ',', $new_keyword_string );
    my @orig_keywords = split( ',', $orig_keyword_string );

    if ( grep ( /^\s*pic\#\d+\s*$/, @keywords ) ) {
        LJ::errobj(
            "Userpic::RenameBlankKeywords",
            origkw => $orig_keyword_string,
            newkw  => $new_keyword_string
        )->throw;
    }

    # compare sizes
    if ( scalar @keywords ne scalar @orig_keywords ) {
        LJ::errobj(
            "Userpic::MismatchRenameKeywords",
            origkw => $orig_keyword_string,
            newkw  => $new_keyword_string
        )->throw;
    }

    #interleave these into a map, excluding duplicates
    my %keywordmap;
    foreach my $newkw (@keywords) {
        my $origkw = shift(@orig_keywords);

        # clear whitespace
        $newkw  =~ s/^\s+//;
        $newkw  =~ s/\s+$//;
        $origkw =~ s/^\s+//;
        $origkw =~ s/\s+$//;

        $keywordmap{$origkw} = $newkw if $origkw ne $newkw;
    }

    # make sure there is at least one change.
    if ( keys(%keywordmap) ) {

        #make sure that none of the target keywords already exist.
        foreach my $kw ( values %keywordmap ) {
            if ( $u && $u->get_picid_from_keyword( $kw, -1 ) != -1 ) {
                LJ::errobj( "Userpic::RenameKeywordExisting", keyword => $kw )->throw;
            }
        }

        while ( my ( $origkw, $newkw ) = each(%keywordmap) ) {

            # need to check if the kwid already has a mapid
            my $mapid = $u->get_mapid_from_keyword($newkw);

            # if it does, we have to remap it
            if ($mapid) {
                my $oldid = $u->get_mapid_from_keyword($origkw);

                # redirect the old mapid to the new mapid
                $u->do(
"UPDATE userpicmap3 SET kwid = NULL, picid = NULL, redirect_mapid = ? WHERE mapid = ? AND userid = ?",
                    undef, $mapid, $oldid, $u->id
                );
                if ( $u->err ) {
                    warn $u->errstr;
                    LJ::errobj(
                        "Userpic::RenameKeywords",
                        origkw => $origkw,
                        newkw  => $newkw
                    )->throw;
                }

                # change any redirects pointing to the old mapid to the new mapid
                $u->do(
"UPDATE userpicmap3 SET redirect_mapid = ? WHERE redirect_mapid = ? AND userid = ?",
                    undef, $mapid, $oldid, $u->id
                );
                if ( $u->err ) {
                    warn $u->errstr;
                    LJ::errobj(
                        "Userpic::RenameKeywords",
                        origkw => $origkw,
                        newkw  => $newkw
                    )->throw;
                }

                # and set the new mapid to point to the picture
                $u->do( "UPDATE userpicmap3 SET picid = ? WHERE mapid = ? AND userid = ?",
                    undef, $self->picid, $mapid, $u->id );
                if ( $u->err ) {
                    warn $u->errstr;
                    LJ::errobj(
                        "Userpic::RenameKeywords",
                        origkw => $origkw,
                        newkw  => $newkw
                    )->throw;
                }

            }
            else {
                if ( $origkw !~ /^\s*pic\#(\d+)\s*$/ ) {
                    $u->do(
                        "UPDATE userpicmap3 SET kwid = ? WHERE kwid = ? AND userid = ?",
                        undef,
                        $u->get_keyword_id($newkw),
                        $u->get_keyword_id($origkw), $u->id
                    );
                    if ( $u->err ) {
                        warn $u->errstr;
                        LJ::errobj(
                            "Userpic::RenameKeywords",
                            origkw => $origkw,
                            newkw  => $newkw
                        )->throw;
                    }
                }
                else {    # pic#xx
                    my $picid = $1;

                    # get (or create) the mapid for picxx
                    my $mapid_for_picxx = $u->get_mapid_from_keyword($origkw);
                    $u->do(
"UPDATE userpicmap3 SET kwid = ? WHERE kwid is NULL AND userid = ? AND picid = ?",
                        undef, $u->get_keyword_id($newkw), $u->id, $picid
                    );
                    if ( $u->err ) {
                        warn $u->errstr;
                        LJ::errobj(
                            "Userpic::RenameKeywords",
                            origkw => $origkw,
                            newkw  => $newkw
                        )->throw;
                    }
                }
            }
        }
        LJ::Userpic->delete_cache($u);
        $u->clear_userpic_kw_map;
    }

    return 1;
}

sub set_fullurl {
    my ( $self, $url ) = @_;
    my $u = $self->owner;
    $u->do( "UPDATE userpic2 SET url=? WHERE userid=? AND picid=?",
        undef, $url, $u->{'userid'}, $self->id );
    $self->{url} = $url;

    LJ::Userpic->delete_cache($u);

    return 1;
}

# Sorts the given list of Userpics.
sub sort {
    my ( $class, $userpics ) = @_;

    return () unless ( $userpics && ref $userpics );

    my %kwhash;
    my %nokwhash;

    for my $pic (@$userpics) {
        my $pickw = $pic->keywords( raw => 1 );
        if ( defined $pickw ) {
            $kwhash{$pickw} = $pic;
        }
        else {
            $pickw = $pic->keywords;
            $nokwhash{$pickw} = $pic;
        }
    }
    my @sortedkw   = sort { lc $a cmp lc $b } keys %kwhash;
    my @sortednokw = sort { lc $a cmp lc $b } keys %nokwhash;

    my @sortedpics;
    foreach my $kw (@sortedkw) {
        push @sortedpics, $kwhash{$kw};
    }
    foreach my $kw (@sortednokw) {
        push @sortedpics, $nokwhash{$kw};
    }

    return @sortedpics;
}

# Organizes the given userpics by keyword.  Returns an array of hashes,
# with values of keyword and userpic.
sub separate_keywords {
    my ( $class, $userpics ) = @_;

    return () unless ( $userpics && ref $userpics );

    my @userpic_array;
    my @nokw_array;

    foreach my $userpic (@$userpics) {
        my @keywords = $userpic->keywords( raw => 1 );
        foreach my $keyword (@keywords) {
            if ( defined $keyword ) {
                push @userpic_array, { keyword => $keyword, userpic => $userpic };
            }
            else {
                $keyword = $userpic->keywords;
                push @nokw_array, { keyword => $keyword, userpic => $userpic };
            }
        }
    }

    @userpic_array = sort { lc( $a->{keyword} ) cmp lc( $b->{keyword} ) } @userpic_array;
    push @userpic_array, sort { $a->{keyword} cmp $b->{keyword} } @nokw_array;

    return @userpic_array;
}

# convert to json
sub TO_JSON {
    my $self = shift;

    my $remote    = LJ::get_remote();
    my @keywords  = $self->keywords;
    my $returnval = {
        username => $self->u->user,
        picid    => int( $self->picid ),
        url      => $self->url,
        comment  => $self->comment,
        keywords => \@keywords,
    };

    if ( $remote && $remote eq $self->u ) {
        $returnval->{inactive} = $self->inactive;
    }
    return $returnval;
}

####
# error classes:

package LJ::Error::Userpic::TooManyKeywords;

sub user_caused { 1 }
sub fields      { qw(userpic lost); }

sub number_lost {
    my $self = $_[0];
    return scalar @{ $self->field("lost") };
}

sub lost_keywords_as_html {
    my $self = $_[0];
    return join( ", ", map { LJ::ehtml($_) } @{ $self->field("lost") } );
}

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.editicons.toomanykeywords",
        {
            numwords => $self->number_lost,
            words    => $self->lost_keywords_as_html,
            max      => $LJ::MAX_USERPIC_KEYWORDS,
        }
    );
}

package LJ::Error::Userpic::Bytesize;
sub user_caused { 1 }
sub fields      { qw(size max); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        'error.editicons.filetoolarge',
        {
            maxsize => $self->{'max'},
        }
    );
}

package LJ::Error::Userpic::Dimensions;
sub user_caused { 1 }
sub fields      { qw(w h); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        'error.editicons.imagetoolarge',
        {
            imagesize => $self->{'w'} . 'x' . $self->{'h'},
        }
    );
}

package LJ::Error::Userpic::FileType;
sub user_caused { 1 }
sub fields      { qw(type); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.editicons.unsupportedtype",
        {
            filetype => $self->{'type'},
        }
    );
}

package LJ::Error::Userpic::MismatchRenameKeywords;
sub user_caused { 1 }
sub fields      { qw(origkw newkw); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.iconkw.rename.mismatchedlength",
        {
            origkw => $self->{'origkw'},
            newkw  => $self->{'newkw'},
        }
    );
}

package LJ::Error::Userpic::RenameBlankKeywords;
sub user_caused { 1 }
sub fields      { qw(origkw newkw); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.iconkw.rename.blankkw",
        {
            origkw => $self->{'origkw'},
            newkw  => $self->{'newkw'},
        }
    );
}

package LJ::Error::Userpic::RenameKeywordExisting;
sub user_caused { 1 }
sub fields      { qw(keyword); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.iconkw.rename.keywordexists",
        {
            keyword => $self->{'keyword'},
        }
    );
}

package LJ::Error::Userpic::RenameKeywords;
sub user_caused { 0 }
sub fields      { qw(origkw newkw); }

sub as_html {
    my $self = $_[0];
    return LJ::Lang::ml(
        "error.iconkw.rename.keywords",
        {
            origkw => $self->{'origkw'},
            newkw  => $self->{'newkw'},
        }
    );
}

package LJ::Error::Userpic::DeleteFailed;
sub user_caused { 0 }

1;
