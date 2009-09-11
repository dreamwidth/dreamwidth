package LJ::Userpic;
use strict;
use Carp qw(croak);
use Digest::MD5;
use Class::Autouse qw (LJ::Event::NewUserpic);
use LJ::Constants;

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
# altext	: description with keyword fallback; keyword-recently-used dependent
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

# LJ::Userpic constructor. Returns a LJ::Userpic object.
# Return existing with userid and picid populated, or make new.
sub instance {
    my ($class, $u, $picid) = @_;
    my $up;

    # return existing one, if loaded
    if (my $us = $singletons{$u->{userid}}) {
        return $up if $up = $us->{$picid};
    }

    # otherwise construct a new one with the given picid
    $up = $class->_skeleton($u, $picid);
    $singletons{$u->{userid}}->{$picid} = $up;
    return $up;
}
*new = \&instance;

# LJ::Userpic accessor. Returns a LJ::Userpic object indicated by $picid, or
# undef if userpic doesn't exist in the db.
sub get {
    my ($class, $u, $picid) = @_;

    my @cache = LJ::Userpic->load_user_userpics($u);

    if (@cache) {
        foreach my $curr (@cache) {
            return LJ::Userpic->new( $u, $curr->{picid} ) if $curr->{picid} == $picid;
        }
    }

    return undef;
}

sub _skeleton {
    my ($class, $u, $picid) = @_;
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
    my ($class, $u, $md5sum) = @_;
    die unless $u && length($md5sum) == 22;

    my $sth = $u->prepare( "SELECT * FROM userpic2 WHERE userid=? " .
                           "AND md5base64=?" );
    $sth->execute($u->{'userid'}, $md5sum);
    my $row = $sth->fetchrow_hashref
        or return undef;
    return LJ::Userpic->new_from_row($row);
}

sub preload_default_userpics {
    my ($class, @us) = @_;
    my %upics;
    LJ::load_userpics(\%upics, [
                                map { [ $_, $_->{defaultpicid} ] }
                                grep { $_->{defaultpicid} }
                                @us
                                ]);
    foreach my $u (@us) {
        my $up = $u->userpic       or next;
        my $row = $upics{$up->id}  or next;
        $row->{picid} = $up->id;
        $up->absorb_row($row);
    }
}

sub new_from_row {
    my ($class, $row) = @_;
    die unless $row && $row->{userid} && $row->{picid};
    my $self = LJ::Userpic->new(LJ::load_userid($row->{userid}), $row->{picid});
    $self->absorb_row($row);
    return $self;
}

sub new_from_keyword
{
    my ($class, $u, $kw) = @_;

    my $picid = LJ::get_picid_from_keyword($u, $kw) or
        return undef;

    return $class->new($u, $picid);
}

# instance methods

sub valid {
    my $self = shift;
    return defined $self->state;
}

sub absorb_row {
    my ($self, $row) = @_;
    for my $f (qw(userid picid width height comment description location state url pictime flags md5base64)) {
        $self->{$f} = $row->{$f};
    }
    my $key = $row->{fmt} || $row->{contenttype}; # avoid warnings on uninitialized value in hash element FIXME
    $self->{_ext} = $MimeTypeMap{$key} if defined $key;
    return $self;
}

##
## accessors
##

# FIXME: id and picid are identical. Eventually "id"
# should go.

# returns the picture ID associated with the object
sub picid {
    return $_[0]->{picid};
}

*id = \&picid;

#  returns the userid associated with the object
sub userid {
    return $_[0]->{userid};
}

# FIXME: u and owner are identical in practice, since the method
# userid returns the userid data element.  Eventually "owner" should
# go.

# given a userpic with a known userid, return the user object
sub u {
    return LJ::load_userid($_[0]->userid);
}

*owner = \&u;

sub inactive {
    return $_[0]->state eq 'I';
}

sub state {
    my $self = shift;
    return $self->{state} if defined $self->{state};
    $self->load_row;
    return $self->{state};
}

sub comment {
    my $self = shift;
    return $self->{comment} if exists $self->{comment};
    $self->load_row;
    return $self->{comment};
}

sub description {
    my $self = shift;
    return $self->{description} if exists $self->{description};
    $self->load_row;
    return $self->{description};
}

sub width {
    my $self = shift;
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[0];
}

sub height {
    my $self = shift;
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[1];
}
sub pictime {
    return $_[0]->{pictime};
}

sub flags {
    return $_[0]->{flags};
}

sub md5base64 {
    my $self = shift;
    return $self->{md5base64};
}

sub extension {
    my $self = shift;
    return $self->{_ext} if $self->{_ext};
    $self->load_row;
    return $self->{_ext};
}

sub location {
    my $self = shift;
    return $self->{location} if $self->{location};
    $self->load_row;
    return $self->{location};
}

# returns (width, height)
sub dimensions {
    my $self = shift;

    # width and height probably loaded from DB
    return ($self->{width}, $self->{height}) if ($self->{width} && $self->{height});

    my %upics;
    my $u = LJ::load_userid($self->{userid});
    LJ::load_userpics(\%upics, [ $u, $self->{picid} ]);
    my $up = $upics{$self->{picid}} or
        return ();

    return ($up->{width}, $up->{height});
}

sub max_allowed_bytes {
    my ($class, $u) = @_;
    return 40960;
}


# Returns the direct link to the uploaded userpic
sub url {
    my $self = shift;

    if (my $hook_path = LJ::run_hook('construct_userpic_url', $self)) {
        return $hook_path;
    }

    return "$LJ::USERPIC_ROOT/$self->{picid}/$self->{userid}";
}

# Returns original URL used if userpic was originally uploaded
# via a URL.
# FIXME: Is this ever used? If not, should be deleted. If so,
# should be renamed to source_url
sub fullurl {
    my $self = shift;
    return $self->{url} if $self->{url};
    $self->load_row;
    return $self->{url};
}

# given a userpic and a keyword, return the alt text
sub alttext {
    my ( $self, $kw ) = @_;

    # load the alttext.  use description by default, keyword as fallback,
    # and all keywords as final fallback (should be for default icon only).

    # NOTE: This returns the alttext raw, and relies on the callers (usually
    # but not always Userpic->imgtag) to strip any special characters.

    if ($self->description) {
        return $self->description;
    } elsif ($kw) {
        return $kw;
    } else {
        return $self->keywords;
    }

}

# returns an image tag of this userpic
# optional parameters (which must be explicitly passed) include
# width, keyword, and user (object)
sub imgtag {
    my $self = shift;
    my %opts = @_;

    # if the width and keyword have been passed in  as explicit
    # parameters, set them. Otherwise, take what ever is set in
    # the userpic
    my $width = $opts{width} || $self->width;
    my $height = $opts{height} || $self->height;
    my $keyword = $opts{keyword} || $self->keywords;

    # if no description is available for alttext, try to fall
    # back to the keyword selected by the user (passed as a
    # parameter to imgtag). Otherwise, use the entire keyword
    # string from the userpic.

    my $alttext = LJ::ehtml( $self->alttext( $keyword ) );

    # if we passed in a user, format as if for entries or comments
    # otherwise, print out keywords for additional context
    my $title = "";
    if ( $opts{user} ) {
        $title = $opts{user}->display_name;
        $title .= $opts{keyword} ? ": $opts{keyword}" : ": (default)";
    } else {
        $title = $keyword;
    }    
    $title = LJ::ehtml( $title );

    return '<img src="' . $self->url . '" width="' . $width . 
        '" height="' . $height . '" alt="' . $alttext . 
        '" title="' . $title . '" class="userpic-img" />';
}

# FIXME: should have alt text, if it should be kept
sub imgtag_lite {
    my $self = shift;
    return '<img src="' . $self->url . '" width="' . $self->width . '" height="' . $self->height .
        '" class="userpic-img" />';
}

# FIXME: should have alt text, if it should be kept
sub imgtag_nosize {
    my $self = shift;
    return '<img src="' . $self->url . '" class="userpic-img" />';
}

# pass the decimal version of a percentage that you want to shrink/increase the userpic by
# default is 50% of original size
sub imgtag_percentagesize {
    my $self = shift;
    my $percentage = shift || 0.5;

    my $width = int($self->width * $percentage);
    my $height = int($self->height * $percentage);

    return '<img src="' . $self->url . '" width="' . $width . '" height="' . $height . '" class="userpic-img" />';
}

# pass a fixed height or width that you want to be the size of the userpic
# must include either a height or width, if both are given the smaller of the two is used
# returns the width and height attributes as a string to insert into an img tag
sub img_fixedsize {
    my $self = shift;
    my %opts = @_;

    my $width = $opts{width} || 0;
    my $height = $opts{height} || 0;

    if ( $width > 0 && $width < $self->width && 
        ( !$height || ( $width <= $height && $self->width >= $self->height ) ) ) {
        my $ratio = $width / $self->width;
        $height = int( $self->height * $ratio );
    } elsif ( $height > 0 && $height < $self->height ) {
        my $ratio = $height / $self->height;
        $width = int( $self->width * $ratio );
    } else {
        $width = $self->width;
        $height = $self->height;
    }

    return 'height="' . $height . '" width="' . $width . '"';
}



# in scalar context returns comma-seperated list of keywords or "pic#12345" if no keywords defined
# in list context returns list of keywords ( (pic#12345) if none defined )
# opts: 'raw' = return '' instead of 'pic#12345'
sub keywords {
    my $self = shift;
    my %opts = @_;

    my $raw = delete $opts{raw} || undef;

    croak "Invalid opts passed to LJ::Userpic::keywords" if keys %opts;

    my $picinfo = LJ::get_userpic_info($self->{userid}, {load_comments => 0});

    # $picinfo is a hashref of userpic data
    # keywords are stored in the "kw" field in the format keyword => {hash of some picture info}

    # create a hash of picids => keywords
    my $keywords = {};
    foreach my $keyword (keys %{$picinfo->{kw}}) {
        my $picid = $picinfo->{kw}->{$keyword}->{picid};
        $keywords->{$picid} = [] unless $keywords->{$picid};
        push @{$keywords->{$picid}}, $keyword if ($keyword && $picid);
    }

    # return keywords for this picid
    my @pickeywords = $keywords->{$self->id} ? @{$keywords->{$self->id}} : ();

    if (wantarray) {
        # if list context return the array
        return ($raw ? ('') : ("pic#" . $self->id)) unless @pickeywords;

        return @pickeywords;
    } else {
        # if scalar context return comma-seperated list of keywords, or "pic#12345" if no keywords
        return ($raw ? '' : "pic#" . $self->id) unless @pickeywords;

        return join(', ', sort @pickeywords);
    }
}

sub imagedata {
    my $self = shift;

    my %upics;
    my $u = $self->owner;
    LJ::load_userpics(\%upics, [ $u, $self->{picid} ]);
    my $pic = $upics{$self->{picid}} or
        return undef;

    return undef if $pic->{'userid'} != $self->{userid} || $pic->{state} eq 'X';

    if ($pic->{location} eq "M") {
        my $key = $u->mogfs_userpic_key( $self->{picid} );
        my $data = LJ::mogclient()->get_file_data( $key );
        return $$data;
    }

    my %MimeTypeMapd6 = (
                         'G' => 'gif',
                         'J' => 'jpg',
                         'P' => 'png',
                         );

    my $data;
    if ($LJ::USERPIC_BLOBSERVER) {
        my $fmt = $MimeTypeMapd6{ $pic->{fmt} };
        $data = LJ::Blob::get($u, "userpic", $fmt, $self->{picid});
        return $data if $data;
    }

    my $dbb = LJ::get_cluster_reader($u)
        or return undef;

    $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                  "userid=? AND picid=?", undef, $self->{userid},
                                  $self->{picid});
    return $data ? $data : undef;
}

# TODO: add in lazy peer loading here
sub load_row {
    my $self = shift;
    my $u = $self->owner;
    return unless defined $u;
    return if $u->is_expunged;

    # Load all of the userpics from cache, or load them from the database and write them to cache
    my @cache = LJ::Userpic->load_user_userpics($u);

    if (@cache) {
        foreach my $curr (@cache) {
            return $self->absorb_row($curr) if $curr->{picid} eq $self->picid;
        }
    }

    # If you get past this conditional something is wrong
    # load_user_userpics  always returns a value

    my $row = $u->selectrow_hashref( "SELECT userid, picid, width, height, state, fmt, comment, description, location, url, " .
                                     "UNIX_TIMESTAMP(picdate) AS 'pictime', flags, md5base64 " .
                                     "FROM userpic2 WHERE userid=? AND picid=?", undef,
                                     $u->userid, $self->{picid} );
    $self->absorb_row($row) if $row;
}

# checks request cache and memcache, 
# returns: undef if nothing in cache
#          arrayref of LJ::Userpic instances if found in cache
sub get_cache {
    my $class = shift;
    my $u = shift;

    # check request cache first!
    # -- this gets populated when a ->load_user_userpics call happens,
    #    so the actual guts of the LJ::Userpic objects is cached in
    #    the singletons
    if ($u->{_userpicids}) {
        return [ map { LJ::Userpic->instance($u, $_) } @{$u->{_userpicids}} ];
    }

    my $memkey = $class->memkey($u);
    my $memval = LJ::MemCache::get($memkey);

    # nothing found in cache, return undef
    return undef unless $memval;

    my @ret = ();
    foreach my $row (@$memval) {
        my $curr = LJ::MemCache::array_to_hash('userpic2', $row);
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
    my $class = shift;
    my $u = shift;
    my $rows = shift;

    my $memkey = $class->memkey( $u );
    my @vals = map { LJ::MemCache::hash_to_array( 'userpic2', $_ ) } @$rows;
    LJ::MemCache::set( $memkey, \@vals, 60*30 );

    # set cache of picids on $u
    $u->{_userpicids} = [ map { $_->{picid} } @$rows ];

    return 1;
}

sub load_user_userpics {
    my ($class, $u) = @_;
    local $LJ::THROW_ERRORS = 1;
    my @ret;

    my $cache = $class->get_cache($u);
    return @$cache if $cache;

    # select all of their userpics and iterate through them
    my $sth = $u->prepare( "SELECT userid, picid, width, height, state, fmt, comment, description, location, " .
                           "UNIX_TIMESTAMP(picdate) AS 'pictime', flags, md5base64 " .
                           "FROM userpic2 WHERE userid=?" );
    $sth->execute( $u->userid );
    die "Error loading userpics: clusterid=$u->{clusterid}, errstr=" . $sth->errstr if $sth->err;

    while (my $rec = $sth->fetchrow_hashref) {
        # ignore anything expunged
        next if $rec->{state} eq 'X';
        push @ret, $rec;
    }

    # set cache if reasonable
    $class->set_cache($u, \@ret);

    return map { LJ::Userpic->new_from_row($_) } @ret;
}

sub create {
    my ( $class, $u, %opts ) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $dataref = delete $opts{data};
    my $maxbytesize = delete $opts{maxbytesize};
    my $nonotify = delete $opts{nonotify};
    croak("dataref not a scalarref") unless ref $dataref eq 'SCALAR';

    croak("Unknown options: " . join(", ", scalar keys %opts)) if %opts;

    my $err = sub {
        my $msg = shift;
    };

    eval "use Image::Size;";
    # FIXME the filetype is supposed to be returned intthe next call
    # but according to the docs of Image::Size v3.2 it does not return that value
    my ($w, $h, $filetype) = Image::Size::imgsize($dataref);
    my $MAX_UPLOAD = $maxbytesize || LJ::Userpic->max_allowed_bytes($u);

    my $size = length $$dataref;

    my $fmterror = 0;

    my @errors;
    if ($size > $MAX_UPLOAD) {
        push @errors, LJ::errobj("Userpic::Bytesize",
                                 size => $size,
                                 max  => int($MAX_UPLOAD / 1024));
    }

    unless ($filetype eq "GIF" || $filetype eq "JPG" || $filetype eq "PNG") {
        push @errors, LJ::errobj("Userpic::FileType",
                                 type => $filetype);
        $fmterror = 1;
    }

    # don't throw a dimensions error if it's the wrong file type because its dimensions will always
    # be 0x0
    unless ($w >= 1 && $w <= 100 && $h >= 1 && $h <= 100) {
        push @errors, LJ::errobj("Userpic::Dimensions",
                                 w => $w, h => $h) unless $fmterror;
    }

    LJ::throw(@errors);

    my $base64 = Digest::MD5::md5_base64($$dataref);

    my $target;
    if ( $LJ::USERPIC_MOGILEFS ) {
        $target = 'mogile';
    } elsif ( $LJ::USERPIC_BLOBSERVER ) {
        $target = 'blob';
    }

    my $dbh = LJ::get_db_writer();

    # see if it's a duplicate, return it if it is
    if (my $dup_up = LJ::Userpic->new_from_md5($u, $base64)) {
        return $dup_up;
    }

    # start making a new onew
    my $picid = LJ::alloc_global_counter('P');

    my $contenttype = {
            'GIF' => 'G',
            'PNG' => 'P',
            'JPG' => 'J',
        }->{$filetype};

    @errors = (); # TEMP: FIXME: remove... using exceptions

    my $dberr = 0;
    $u->do( "INSERT INTO userpic2 (picid, userid, fmt, width, height, " .
            "picdate, md5base64, location) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?)",
            undef, $picid, $u->userid, $contenttype, $w, $h, $base64, $target );
    if ( $u->err ) {
        push @errors, $err->( $u->errstr );
        $dberr = 1;
    }

    my $clean_err = sub {
        $u->do( "DELETE FROM userpic2 WHERE userid=? AND picid=?",
                undef, $u->userid, $picid ) if $picid;
        return $err->(@_);
    };

    ### insert the blob
    $target ||= ''; # avoid warnings FIXME should this be set before the INSERT call?
    if ($target eq 'mogile' && !$dberr) {
        my $fh = LJ::mogclient()->new_file($u->mogfs_userpic_key($picid), 'userpics');
        if (defined $fh) {
            $fh->print($$dataref);
            my $rv = $fh->close;
            push @errors, $clean_err->("Error saving to storage server: $@") unless $rv;
        } else {
            # fatal error, we couldn't get a filehandle to use
            push @errors, $clean_err->("Unable to contact storage server.  Your picture has not been saved.");
        }

        # even in the non-LJ::Blob case we use the userblob table as a means
        # to track the number and size of user blob assets
        my $dmid = LJ::get_blob_domainid('userpic');
        $u->do("INSERT INTO userblob (journalid, domain, blobid, length) ".
               "VALUES (?, ?, ?, ?)", undef, $u->{userid}, $dmid, $picid, $size);

    } elsif ($target eq 'blob' && !$dberr) {
        my $et;
        my $fmt = lc($filetype);
        my $rv = LJ::Blob::put($u, "userpic", $fmt, $picid, $$dataref, \$et);
        push @errors, $clean_err->("Error saving to media server: $et") unless $rv;
    } elsif (!$dberr) {
        my $dbcm = LJ::get_cluster_master($u);
        return $err->($BML::ML{'error.nodb'}) unless $dbcm;
        $u->do("INSERT INTO userpicblob2 (userid, picid, imagedata) " .
               "VALUES (?, ?, ?)",
               undef, $u->{'userid'}, $picid, $$dataref);
        push @errors, $clean_err->($u->errstr) if $u->err;

    } else { # We should never get here!
        push @errors, "User picture uploading failed for unknown reason";
    }

    LJ::throw(@errors);

    # now that we've created a new pic, invalidate the user's memcached userpic info
    LJ::Userpic->delete_cache( $u );

    my $upic = LJ::Userpic->new( $u, $picid ) or die "Error insantiating userpic";
    LJ::Event::NewUserpic->new( $upic )->fire if LJ::is_enabled('esn') && !$nonotify;

    return $upic;
}

# make this picture the default
sub make_default {
    my $self = shift;
    my $u = $self->owner
        or die;

    LJ::update_user($u, { defaultpicid => $self->id });
    $u->{'defaultpicid'} = $self->id;
}

# returns true if this picture if the default userpic
sub is_default {
    my $self = shift;
    my $u = $self->owner;

    return $u->{'defaultpicid'} == $self->id;
}

sub delete_cache {
    my ($class, $u) = @_;
    my $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);
    $memkey = [$u->{'userid'},"upiccom:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);
    $memkey = [$u->{'userid'},"upicurl:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);
    $memkey = [$u->{'userid'},"upicdes:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);

    # userpic2 rows for a given $u
    $memkey = LJ::Userpic->memkey($u);
    LJ::MemCache::delete($memkey);

    delete $u->{_userpicids};

    # clear process cache
    $LJ::CACHE_USERPIC_INFO{$u->{'userid'}} = undef;
}

# delete this userpic
# TODO: error checking/throw errors on failure
sub delete {
    my $self = shift;
    local $LJ::THROW_ERRORS = 1;

    my $fail = sub {
        LJ::errobj("WithSubError",
                   main   => LJ::errobj("DeleteFailed"),
                   suberr => $@)->throw;
    };

    my $u = $self->owner;
    my $picid = $self->id;

    # delete meta-data first so it doesn't get stranded if errors
    # between this and deleting row
    $u->do("DELETE FROM userblob WHERE journalid=? AND blobid=? " .
           "AND domain=?", undef, $u->{'userid'}, $picid,
           LJ::get_blob_domainid('userpic'));
    $fail->() if $@;

    # userpic keywords
    eval {
        $u->do( "DELETE FROM userpicmap2 WHERE userid=? " .
                "AND picid=?", undef, $u->userid, $picid ) or die;
        $u->do( "DELETE FROM userpic2 WHERE picid=? AND userid=?",
                undef, $picid, $u->userid ) or die;
        };
    $fail->() if $@;

    $u->log_event('delete_userpic', { picid => $picid });

    # best-effort on deleteing the blobs
    # TODO: we could fire warnings if they fail, then if $LJ::DIE_ON_WARN is set,
    # the ->warn methods on errobjs are actually dies.
    eval {
        my $location = $self->location; # avoid warnings FIXME
        if (defined $location and $location eq 'mogile') {
            LJ::mogclient()->delete($u->mogfs_userpic_key($picid));
        } elsif ($LJ::USERPIC_BLOBSERVER &&
                 LJ::Blob::delete($u, "userpic", $self->extension, $picid)) {
        } elsif ($u->do("DELETE FROM userpicblob2 WHERE ".
                        "userid=? AND picid=?", undef,
                        $u->{userid}, $picid) > 0) {
        }
    };

    LJ::Userpic->delete_cache($u);

    return 1;
}

sub set_comment {
    my ($self, $comment) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $u = $self->owner;
    $comment = LJ::text_trim($comment, LJ::BMAX_UPIC_COMMENT(), LJ::CMAX_UPIC_COMMENT());
    $u->do("UPDATE userpic2 SET comment=? WHERE userid=? AND picid=?",
                  undef, $comment, $u->{'userid'}, $self->id)
        or die;
    $self->{comment} = $comment;

    LJ::Userpic->delete_cache($u);
    return 1;
}

sub set_description {
    my ($self, $description) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $u = $self->owner;
    #return 0 unless LJ::Userpic->user_supports_descriptions($u);
    $description = LJ::text_trim($description, LJ::BMAX_UPIC_DESCRIPTION, LJ::CMAX_UPIC_DESCRIPTION);
    $u->do("UPDATE userpic2 SET description=? WHERE userid=? AND picid=?",
                  undef, $description, $u->{'userid'}, $self->id)
        or die;
    $self->{description} = $description;

    LJ::Userpic->delete_cache($u);
    return 1;
}

# instance method:  takes a string of comma-separate keywords, or an array of keywords
sub set_keywords {
    my $self = shift;

    my @keywords;
    if (@_ > 1) {
        @keywords = @_;
    } else {
        @keywords = split(',', $_[0]);
    }
    @keywords = grep { !/^pic\#\d+$/ } grep { s/^\s+//; s/\s+$//; $_; } @keywords;

    my $u = $self->owner;
    my $sth;
    my $dbh;

    $sth = $u->prepare( "SELECT kwid FROM userpicmap2 WHERE userid=? AND picid=?" );
    $sth->execute( $u->userid, $self->id );

    my %exist_kwids;
    while (my ($kwid) = $sth->fetchrow_array) {
        $exist_kwids{$kwid} = 1;
    }

    my (@bind, @data, @kw_errors);
    my $c = 0;
    my $picid = $self->{picid};

    foreach my $kw (@keywords) {
        my $kwid = LJ::get_keyword_id( $u, $kw );
        next unless $kwid; # TODO: fire some warning that keyword was bogus

        if (++$c > $LJ::MAX_USERPIC_KEYWORDS) {
            push @kw_errors, $kw;
            next;
        }

        unless (delete $exist_kwids{$kwid}) {
            push @bind, '(?, ?, ?)';
            push @data, $u->{'userid'}, $kwid, $picid;
        }
    }

    LJ::Userpic->delete_cache($u);

    foreach my $kwid (keys %exist_kwids) {
        $u->do("DELETE FROM userpicmap2 WHERE userid=? AND picid=? AND kwid=?", undef, $u->{userid}, $self->id, $kwid);
    }

    # save data if any
    if (scalar @data) {
        my $bind = join(',', @bind);

        $u->do( "REPLACE INTO userpicmap2 (userid, kwid, picid) VALUES $bind",
                undef, @data );
    }

    # Let the user know about any we didn't save
    # don't throw until the end or nothing will be saved!
    if (@kw_errors) {
        my $num_words = scalar(@kw_errors);
        LJ::errobj("Userpic::TooManyKeywords",
                   userpic => $self,
                   lost    => \@kw_errors)->throw;
    }

    return 1;
}

sub set_fullurl {
    my ($self, $url) = @_;
    my $u = $self->owner;
    $u->do("UPDATE userpic2 SET url=? WHERE userid=? AND picid=?",
           undef, $url, $u->{'userid'}, $self->id);
    $self->{url} = $url;

    LJ::Userpic->delete_cache($u);

    return 1;
}

####
# error classes:

package LJ::Error::Userpic::TooManyKeywords;

sub user_caused { 1 }
sub fields      { qw(userpic lost); }

sub number_lost {
    my $self = shift;
    return scalar @{ $self->field("lost") };
}

sub lost_keywords_as_html {
    my $self = shift;
    return join(", ", map { LJ::ehtml($_) } @{ $self->field("lost") });
}

sub as_html {
    my $self = shift;
    my $num_words = $self->number_lost;
    return BML::ml("/editpics.bml.error.toomanykeywords", {
        numwords => $self->number_lost,
        words    => $self->lost_keywords_as_html,
        max      => $LJ::MAX_USERPIC_KEYWORDS,
    });
}

package LJ::Error::Userpic::Bytesize;
sub user_caused { 1 }
sub fields      { qw(size max); }
sub as_html {
    my $self = shift;
    return BML::ml('/editpics.bml.error.filetoolarge',
                   { 'maxsize' => $self->{'max'} .
                         BML::ml('/editpics.bml.kilobytes')} );
}

package LJ::Error::Userpic::Dimensions;
sub user_caused { 1 }
sub fields      { qw(w h); }
sub as_html {
    my $self = shift;
    return BML::ml('/editpics.bml.error.imagetoolarge', {
        imagesize => $self->{'w'} . 'x' . $self->{'h'}
        });
}

package LJ::Error::Userpic::FileType;
sub user_caused { 1 }
sub fields      { qw(type); }
sub as_html {
    my $self = shift;
    return BML::ml("/editpics.bml.error.unsupportedtype",
                          { 'filetype' => $self->{'type'} });
}

package LJ::Error::Userpic::DeleteFailed;
sub user_caused { 0 }

1;
