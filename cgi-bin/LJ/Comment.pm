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
#
# LiveJournal comment object.
#
# Just framing right now, not much to see here!
#

package LJ::Comment;

use strict;
use Carp qw/ croak /;

use LJ::Entry;
use LJ::HTMLControls;
use LJ::Talk;

=head1 NAME

LJ::Comment

=head1 CLASS METHODS

=cut

# internal fields:
#
#    journalid:     journalid where the comment was
#                   posted,                          always present
#    jtalkid:       jtalkid identifying this comment
#                   within the journal_u,            always present
#
#    nodetype:      single-char nodetype identifier, loaded if _loaded_row
#    nodeid:        nodeid to which this comment
#                   applies (often an entry itemid), loaded if _loaded_row
#
#    parenttalkid:  talkid of parent comment,        loaded if _loaded_row
#    posterid:      userid of posting user           lazily loaded at access
#    datepost_unix: unixtime from the 'datepost'     loaded if _loaded_row
#    state:         comment state identifier,        loaded if _loaded_row

#    body:          text of comment,                 loaded if _loaded_text
#    body_orig:     text of comment w/o transcoding, present if unknown8bit

#    subject:       subject of comment,              loaded if _loaded_text
#    subject_orig   subject of comment w/o transcoding, present if unknown8bit

#    props:   hashref of props,                    loaded if _loaded_props
#    childids:   arrayref of child ids              loaded if _loaded_childids

#    _loaded_text:   loaded talktext2 row
#    _loaded_row:    loaded talk2 row
#    _loaded_props:  loaded props
#    _loaded_childids:  loaded childids

my %singletons = ();    # journalid->jtalkid->singleton

# singletons still to be loaded
my %unloaded_singletons      = ();
my %unloaded_text_singletons = ();
my %unloaded_prop_singletons = ();

sub reset_singletons {
    %singletons               = ();
    %unloaded_singletons      = ();
    %unloaded_text_singletons = ();
    %unloaded_prop_singletons = ();
}

# <LJFUNC>
# name: LJ::Comment::new
# class: comment
# des: Gets a comment given journal_u entry and jtalkid.
# args: uobj, opts?
# des-uobj: A user id or user object ($u) to load the comment for.
# des-opts: Hash of optional keypairs.
#           jtalkid => talkid journal itemid (no anum)
# returns: A new LJ::Comment object. Returns undef on failure.
# </LJFUNC>
sub instance {
    croak("wrong number of arguments")
        unless scalar @_ == 4;
    my ( $class, $uuserid, $which, $value ) = @_;

    my $journalid = LJ::want_userid($uuserid)
        or croak("invalid journalid parameter");
    my $jtalkid = $which eq 'jtalkid' ? $value + 0 : ( $value + 0 >> 8 )
        or croak("need to supply jtalkid or dtalkid");

    # do we have a singleton for this comment?
    $singletons{$journalid} ||= {};
    return $singletons{$journalid}->{$jtalkid}
        if $singletons{$journalid}->{$jtalkid};

    # save the singleton if it doesn't exist
    my $self = bless {
        journalid => $journalid,
        jtalkid   => $jtalkid,
    }, $class;

    $unloaded_singletons{ $self->singletonkey }      = $self;
    $unloaded_text_singletons{ $self->singletonkey } = $self;
    $unloaded_prop_singletons{ $self->singletonkey } = $self;

    return $singletons{$journalid}->{$jtalkid} = $self;
}
*new = \&instance;

# class method. takes a ?thread= or ?replyto= URL
# to a comment, and returns that comment object
sub new_from_url {
    my ( $class, $url ) = @_;
    $url =~ s!#.*!!;

    if ( $url =~ /(.+?)\?(?:thread|replyto)\=(\d+)/ ) {
        my $entry = LJ::Entry->new_from_url($1);
        return undef unless $entry;
        return LJ::Comment->new( $entry->journal, dtalkid => $2 );
    }

    return undef;
}

# <LJFUNC>
# name: LJ::Comment::create
# class: comment
# des: Create a new comment. Add them to DB.
# args:
# returns: A new LJ::Comment object. Returns undef on failure.
# </LJFUNC>

sub create {
    my ( $class, %opts ) = @_;

    my $need_captcha = delete( $opts{need_captcha} ) || 0;
    my $err_ref      = delete $opts{err_ref};

    my $err = sub {
        $$err_ref = {
            code => $_[0],
            msg  => $_[1]
        };
        return undef;
    };

    # %talk_opts emulates parameters received from web form.
    # Fill it with nessesary options.
    my %talk_opts = map { $_ => delete $opts{$_} } qw(nodetype parenttalkid body subject props);

    # poster and journal should be $u objects,
    # but talklib wants usernames... we'll map here
    my $journalu = delete $opts{journal};
    return $err->( "bad_journal", "invalid journal for new comment: $journalu" )
        unless LJ::isu($journalu);

    my $posteru = delete $opts{poster};
    return $err->( "bad_poster", "invalid poster for new comment: $posteru" )
        unless LJ::isu($posteru);

    # LJ::Talk::init uses 'itemid', not 'ditemid'.
    $talk_opts{itemid} = delete $opts{ditemid};

    # LJ::Talk::init needs journal name
    $talk_opts{journal} = $journalu->user;

    # Strictly parameters check. Do not allow any unused params to be passed in.
    return $err->(
        "bad_args", __PACKAGE__ . "->create: Unsupported params: " . join " " => keys %opts
    ) if %opts;

    # Move props values to the talk_opts hash.
    # Because LJ::Talk::Post::init needs this.
    foreach my $key ( keys %{ $talk_opts{props} } ) {
        my $talk_key = "prop_$key";

        $talk_opts{$talk_key} = delete $talk_opts{props}->{$key}
            if not exists $talk_opts{$talk_key};
    }

    # The following 2 options are necessary for successful user authentification
    # in the depth of LJ::Talk::Post::init.
    #
    # FIXME: this almost certainly should be 'usertype=user' rather than
    #        'cookieuser' with $remote passed below.  Gross.
    $talk_opts{cookieuser} ||= $posteru->user;
    $talk_opts{usertype}   ||= 'cookieuser';
    $talk_opts{nodetype}   ||= 'L';

    ## init.  this handles all the error-checking, as well.
    my @errors = ();
    my $init   = LJ::Talk::Post::init( \%talk_opts, $posteru, \$need_captcha, \@errors );
    return $err->( "init_comment", join "\n" => @errors )
        unless defined $init;

    # check max comments
    return $err->(
        "too_many_comments", "Sorry, this entry already has the maximum number of comments allowed."
    ) if LJ::Talk::Post::over_maxcomments( $init->{journalu}, $init->{item}->{'jitemid'} );

    # no replying to frozen comments
    my $parent_state = $init->{parent}->{state} // '';
    return $err->( "frozen", "Can't reply to frozen thread." ) if $parent_state eq 'F';

    ## insertion
    my $post_err_ref;
    return $err->( "post_comment", $post_err_ref )
        unless LJ::Talk::Post::post_comment(
        $init->{entryu}, $init->{journalu}, $init->{comment},
        $init->{parent}, $init->{item},     \$post_err_ref,
        );

    return LJ::Comment->new( $init->{journalu}, jtalkid => $init->{comment}->{talkid} );

}

=head1 INSTANCE METHODS

=cut

sub absorb_row {
    my ( $self, %row ) = @_;

    $self->{$_} = $row{$_} foreach (qw(nodetype nodeid parenttalkid posterid datepost state));
    $self->{_loaded_row} = 1;
    delete $unloaded_singletons{ $self->singletonkey };
}

sub url {
    my ( $self, $url_args ) = @_;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return
          "$url?thread=$dtalkid"
        . ( $url_args ? "&$url_args" : "" )
        . LJ::Talk::comment_anchor($dtalkid);
}
*thread_url = \&url;

=head2 C<< $self->threadroot_url >>
URL to the thread root. It would be unnecessarily expensive to look up the thread
root, since it is only rarely needed. So we set up a redirect then look up the
thread root only if the user clicks the link.
=cut

sub threadroot_url {
    my ( $self, $url_args ) = @_;
    my $dtalkid = $self->dtalkid;
    my $jitemid = $self->entry->jitemid;
    my $journal = $self->entry->journal->user;

    return "$LJ::SITEROOT/go?redir_type=threadroot&journal=$journal&talkid=$dtalkid"
        . ( $url_args ? "&$url_args" : "" );
}

sub reply_url {
    my $self = $_[0];

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return "$url?replyto=$dtalkid";
}

sub parent_url {
    my ( $self, $url_args ) = @_;

    my $parent = $self->parent;

    return undef unless $parent;
    return $parent->url($url_args);
}

sub unscreen_url {
    my $self = $_[0];

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $journal = $entry->journal->{user};

    return "$LJ::SITEROOT/talkscreen" . "?mode=unscreen&journal=$journal" . "&talkid=$dtalkid";
}

sub delete_url {
    my $self = $_[0];

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $journal = $entry->journal->{user};

    return "$LJ::SITEROOT/delcomment" . "?journal=$journal&id=$dtalkid";
}

sub edit_url {
    my $self = $_[0];

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return "$url?edit=$dtalkid";
}

# return LJ::User of journal comment is in
sub journal {
    return LJ::load_userid( $_[0]->{journalid} );
}

sub journalid {
    return $_[0]->{journalid};
}

sub singletonkey {
    return $_[0]->{journalid} . "-" . $_[0]->{jtalkid};
}

# return LJ::Entry of entry comment is in, or undef if it's not
# a nodetype of L
sub entry {
    my $self = $_[0];

    return undef unless $self && $self->valid;
    return LJ::Entry->new( $self->journal, jitemid => $self->nodeid );
}

sub jtalkid {
    return $_[0]->{jtalkid};
}

sub dtalkid {
    my $self  = $_[0];
    my $entry = $self->entry or return undef;
    return ( $self->jtalkid * 256 ) + $entry->anum;
}

sub nodeid {
    __PACKAGE__->preload_rows();
    return $_[0]->{nodeid};
}

sub nodetype {
    __PACKAGE__->preload_rows();
    return $_[0]->{nodetype};
}

=head2 C<< $self->threadrootid >>
Gets the id of the topmost comment in the thread this comment is part of.
If you just want to create a link, do not call this directly. Instead, use
$self->threadroot_url.
=cut

sub threadrootid {

    my ($self) = @_;

    # if this has no parent, then this is the thread root
    return $self->jtalkid unless $self->parenttalkid;

    # if we have the information already, then just return it
    return $self->{threadrootid} if $self->{threadrootid};

    my $entry = $self->entry;

    # if it is in memcache, then use the cached value
    my $jid    = $entry->journalid;
    my $memkey = [ $jid, "talkroot:$jid:" . $self->jtalkid ];

    my $cached_threadrootid = LJ::MemCache::get($memkey);
    if ($cached_threadrootid) {
        $self->{threadrootid} = $cached_threadrootid;
        return $cached_threadrootid;
    }

    # not cached anywhere; let's look it up

    # get all comments to post
    my $comments = LJ::Talk::get_talk_data( $entry->journal, 'L', $entry->jitemid ) || {};

    # see if our comment exists
    return undef unless $comments->{ $self->jtalkid };

    # walk up the tree
    my $id = $self->jtalkid;
    while ( $comments->{$id} && $comments->{$id}->{parenttalkid} ) {

        # avoid (the unlikely chance of) an infinite loop
        $id = delete $comments->{$id}->{parenttalkid};
    }

    # cache the value, for future lookup
    $self->{threadrootid} = $id;
    LJ::MemCache::set( $memkey, $id );
    return $id;
}

sub parenttalkid {
    __PACKAGE__->preload_rows();
    return $_[0]->{parenttalkid};
}

# returns a LJ::Comment object for the parent
sub parent {
    my $self    = $_[0];
    my $ptalkid = $self->parenttalkid or return undef;

    return LJ::Comment->new( $self->journal, jtalkid => $ptalkid );
}

# returns an array of LJ::Comment objects with parentid == $self->jtalkid
sub children {
    my $self = $_[0];

    if ( $self->{_loaded_childids} ) {
        my @children = ();
        my $u        = $self->journal;
        if ( $self->{childids} && scalar @{ $self->{childids} } ) {
            my @childids = @{ $self->{childids} };
            foreach my $talkid (@childids) {
                my $child = LJ::Comment->new( $u, jtalkid => $talkid );
                push @children, $child;
            }
        }
        return @children;
    }

    my $entry = $self->entry;
    return grep { $_->{parenttalkid} == $self->{jtalkid} } $entry->comment_list;

    # FIXME: It might be a good idea to check to see if the entry object had
    #        comments cached above, then fall back to a query to select a list
    #        from db or memcache
}

sub has_children {
    return $_[0]->children ? 1 : 0;
}

sub has_nondeleted_children {
    my $nondeleted_children = grep { !$_->is_deleted } $_[0]->children;
    return $nondeleted_children ? 1 : 0;
}

# returns true if entry currently exists.  (it's possible for a given
# $u, to make a fake jitemid and that'd be a valid skeleton LJ::Entry
# object, even though that jitemid hasn't been created yet, or was
# previously deleted)
sub valid {
    my $self = $_[0];
    my $u    = $self->journal;
    return 0 unless $u && $u->{clusterid};
    __PACKAGE__->preload_rows();
    return $self->{_loaded_row};
}

# when was this comment left?
sub unixtime {
    __PACKAGE__->preload_rows();
    return LJ::mysqldate_to_time( $_[0]->{datepost}, 0 );
}

# returns LJ::User object for the poster of this entry, or undef for anonymous
sub poster {
    return LJ::load_userid( $_[0]->posterid );
}

sub posterid {
    __PACKAGE__->preload_rows();
    return $_[0]->{posterid};
}

sub all_singletons {
    my $self = $_[0];
    my @singletons;
    push @singletons, values %{ $singletons{$_} } foreach keys %singletons;
    return @singletons;
}

# class method:
sub preload_rows {
    my @to_load = ();
    push @to_load, map { [ $_->journal, $_->jtalkid ] } values %unloaded_singletons;

    # already loaded?
    return 1 unless @to_load;

    # args: ([ journalid, jtalkid ], ...)
    my @rows = LJ::Talk::get_talk2_row_multi(@to_load);

    # make a mapping of journalid-jtalkid => $row
    my %row_map = map { join( "-", $_->{journalid}, $_->{jtalkid} ) => $_ } @rows;

    foreach my $obj ( values %unloaded_singletons ) {
        my $u = $obj->journal;

        my $row = $row_map{ join( "-", $u->id, $obj->jtalkid ) };
        next unless $row;

        # absorb row into the given LJ::Comment object
        $obj->absorb_row(%$row);
    }

    %unloaded_singletons = ();
    return 1;
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = $_[0];
    return 1 if $self->{_loaded_text};

    my $entry     = $self->entry;
    my $entryu    = $entry->journal;
    my $entry_uid = $entryu->id;

    # find singletons which don't already have text loaded
    my @to_load;
    foreach my $c_obj ( values %unloaded_text_singletons ) {
        if ( $c_obj->journalid == $entry_uid ) {
            push @to_load, $c_obj;
        }
    }

    my $ret = LJ::get_talktext2( $entryu, map { $_->jtalkid } @to_load );
    return 0 unless $ret && ref $ret;

    # iterate over comment objects we retrieved and set their subject/body/loaded members
    foreach my $c_obj (@to_load) {
        my $tt = $ret->{ $c_obj->jtalkid };
        next unless ( $tt && ref $tt );

        # raw subject and body
        $c_obj->{subject} = $tt->[0];
        $c_obj->{body}    = $tt->[1];

        if ( $c_obj->prop("unknown8bit") ) {

            # save the old ones away, so we can get back at them if we really need to
            $c_obj->{subject_orig} = $c_obj->{subject};
            $c_obj->{body_orig}    = $c_obj->{body};

            # FIXME: really convert all the props?  what if we binary-pack some in the future?
            LJ::item_toutf8( $c_obj->journal, \$c_obj->{subject}, \$c_obj->{body},
                $c_obj->{props} );
        }

        $c_obj->{_loaded_text} = 1;
        delete $unloaded_text_singletons{ $self->singletonkey };
    }

    return 1;
}

sub _set_text {
    my ( $self, %opts ) = @_;

    my $jtalkid = $self->jtalkid;
    die "can't set text on unsaved comment"
        unless $jtalkid;

    my %doing      = ();
    my %original   = ();
    my %compressed = ();

    foreach my $part (qw(subject body)) {
        next unless exists $opts{$part};

        $original{$part} = delete $opts{$part};
        die "$part is not utf-8" unless LJ::is_utf8( $original{$part} );

        $doing{$part}++;
        $compressed{$part} = LJ::text_compress( $original{$part} );
    }

    croak "must set either body or subject" unless %doing;

    # if the comment is unknown8bit, then we must be setting both subject and body,
    # else we'll have one side utf-8 and the other side unknown, but no metadata
    # capable of expressing "subject is unknown8bit, but not body".
    if ( $self->prop('unknown8bit') ) {
        die "Can't set text on unknown8bit comments unless both subject and body are specified"
            unless $doing{subject} && $doing{body};
    }

    my $journalu  = $self->journal;
    my $journalid = $self->journalid;

    # need to set new values in the database
    my $set_sql  = join( ", ", map { "$_=?" } grep { $doing{$_} } qw(subject body) );
    my @set_vals = map { $compressed{$_} } grep { $doing{$_} } qw(subject body);

    # update is okay here because we verified we have a jtalkid, presumably from this table
    # -- compressed versions of the text here
    $journalu->do( "UPDATE talktext2 SET $set_sql WHERE journalid=? AND jtalkid=?",
        undef, @set_vals, $journalid, $jtalkid );
    die $journalu->errstr if $journalu->err;

    # need to also update memcache
    # -- uncompressed versions here
    my $memkey = join( ":", $journalu->clusterid, $journalid, $jtalkid );
    foreach my $part (qw(subject body)) {
        next unless $doing{$part};
        LJ::MemCache::set( [ $journalid, "talk$part:$memkey" ], $original{$part} );
    }

    # got this far in setting text, and we know we used to be unknown8bit, except the text
    # we just set was utf8, so clear the unknown8bit flag
    if ( $self->prop('unknown8bit') ) {

        # set to 0 instead of delete so we can find these records later
        $self->set_prop( 'unknown8bit', '0' );

    }

    # if text is already loaded, then we can just set whatever we've modified in $self
    if ( $doing{subject} && $doing{body} ) {
        $self->{$_} = $original{$_} foreach qw(subject body);
        $self->{_loaded_text} = 1;
    }
    else {
        $self->{$_}                                      = undef foreach qw(subject body);
        $self->{_loaded_text}                            = 0;
        $unloaded_text_singletons{ $self->singletonkey } = $self;
    }

    # otherwise _loaded_text=0 and we won't do any optimizations

    return 1;
}

sub set_subject {
    my ( $self, $text ) = @_;

    return $self->_set_text( subject => $text );
}

sub set_body {
    my ( $self, $text ) = @_;

    return $self->_set_text( body => $text );
}

sub set_subject_and_body {
    my ( $self, $subject, $body ) = @_;

    return $self->_set_text( subject => $subject, body => $body );
}

sub prop {
    my ( $self, $prop ) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props}{$prop};
}

sub set_prop {
    my ( $self, $prop, $val ) = @_;

    return $self->set_props( $prop => $val );
}

# allows the caller to pass raw SQL to set a prop (e.g. UNIX_TIMESTAMP())
# do not use this if setting a value given by the user
sub set_prop_raw {
    my ( $self, $prop, $val ) = @_;

    return $self->set_props_raw( $prop => $val );
}

sub delete_prop {
    my ( $self, $prop ) = @_;

    return $self->set_props( $prop => undef );
}

sub props {
    my ( $self, $prop ) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props} || {};
}

# class method:  preloads the props on the provided list of Comment objects.
sub preload_props {
    my ( $class, $journalid, @to_load ) = @_;

    my $prop_ret = {};
    LJ::load_talk_props2( $journalid, [ map { $_->jtalkid } @to_load ], $prop_ret );

    # iterate over comment objects to load and fill in their props members
    foreach my $c_obj (@to_load) {
        $c_obj->{props}         = $prop_ret->{ $c_obj->jtalkid } || {};
        $c_obj->{_loaded_props} = 1;
        delete $unloaded_prop_singletons{ $c_obj->singletonkey };
    }

    return 1;
}

sub _load_props {
    my $self = $_[0];
    return 1 if $self->{_loaded_props};

    my $journalid = $self->journalid;

    # find singletons which don't already have props loaded
    my @to_load;
    foreach my $c_obj ( values %unloaded_prop_singletons ) {
        if ( $c_obj->journalid == $journalid ) {
            push @to_load, $c_obj;
        }
    }

    my $prop_ret = {};
    LJ::load_talk_props2( $journalid, [ map { $_->jtalkid } @to_load ], $prop_ret );

    # iterate over comment objects to load and fill in their props members
    foreach my $c_obj (@to_load) {
        $c_obj->{props}         = $prop_ret->{ $c_obj->jtalkid } || {};
        $c_obj->{_loaded_props} = 1;
        delete $unloaded_prop_singletons{ $c_obj->singletonkey };
    }

    return 1;
}

sub set_props {
    my ( $self, %props ) = @_;

    # call this so that get_prop() calls below will be cached
    LJ::load_props("talk");

    my $set_raw = delete $props{_raw} ? 1 : 0;

    my $journalid = $self->journalid;
    my $journalu  = $self->journal;
    my $jtalkid   = $self->jtalkid;

    my @vals      = ();
    my @to_del    = ();
    my %tprops    = ();
    my @prop_vals = ();
    foreach my $key ( keys %props ) {
        my $p = LJ::get_prop( "talk", $key );
        next unless $p;

        my $val = $props{$key};

        # build lists for inserts and deletes, also update $self
        if ( defined $val ) {
            if ($set_raw) {
                push @vals, ( $journalid, $jtalkid, $p->{tpropid} );
                push @prop_vals, $val;
                $tprops{ $p->{tpropid} } = $key;
            }
            else {
                push @vals, ( $journalid, $jtalkid, $p->{tpropid}, $val );
                $self->{props}->{$key} = $props{$key};
            }
        }
        else {
            push @to_del, $p->{tpropid};
            delete $self->{props}->{$key};
        }
    }

    if (@vals) {
        my $bind;
        if ($set_raw) {
            my @binds;
            foreach my $prop_val (@prop_vals) {
                push @binds, "(?,?,?,$prop_val)";
            }
            $bind = join( ",", @binds );
        }
        else {
            $bind = join( ",", map { "(?,?,?,?)" } 1 .. ( @vals / 4 ) );
        }
        $journalu->do(
            "REPLACE INTO talkprop2 (journalid, jtalkid, tpropid, value) " . "VALUES $bind",
            undef, @vals );
        die $journalu->errstr if $journalu->err;

        # get the raw prop values back out of the database to store on the object
        if ($set_raw) {
            my $bind = join( ",", map { "?" } keys %tprops );
            my $sth  = $journalu->prepare(
"SELECT tpropid, value FROM talkprop2 WHERE journalid = ? AND jtalkid = ? AND tpropid IN ($bind)"
            );
            $sth->execute( $journalid, $jtalkid, keys %tprops );

            while ( my $row = $sth->fetchrow_hashref ) {
                my $tpropid = $row->{tpropid};
                $self->{props}->{ $tprops{$tpropid} } = $row->{value};
            }
        }

        if ($LJ::_T_COMMENT_SET_PROPS_INSERT) {
            $LJ::_T_COMMENT_SET_PROPS_INSERT->();
        }
    }

    if (@to_del) {
        my $bind = join( ",", map { "?" } @to_del );
        $journalu->do(
            "DELETE FROM talkprop2 WHERE journalid=? AND jtalkid=? AND tpropid IN ($bind)",
            undef, $journalid, $jtalkid, @to_del );
        die $journalu->errstr if $journalu->err;

        if ($LJ::_T_COMMENT_SET_PROPS_DELETE) {
            $LJ::_T_COMMENT_SET_PROPS_DELETE->();
        }
    }

    if ( @vals || @to_del ) {
        LJ::MemCache::delete( [ $journalid, "talkprop:$journalid:$jtalkid" ] );
    }

    return 1;
}

sub set_props_raw {
    my ( $self, %props ) = @_;

    return $self->set_props( %props, _raw => 1 );
}

# raw utf8 text, with no HTML cleaning
sub subject_raw {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return $self->{subject};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub subject_orig {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return $self->{subject_orig} || $self->{subject};
}

# raw utf8 text, with no HTML cleaning
sub body_raw {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};

    # die if we didn't load any body text
    die "Couldn't load body text" unless $self->{_loaded_text};

    return $self->{body};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub body_orig {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return $self->{body_orig} || $self->{body};
}

# comment body, cleaned
sub body_html {
    my ( $self, %extra_opts ) = @_;

    my $opts;
    $opts->{preformatted} = $self->prop("opt_preformatted");
    $opts->{anon_comment} = LJ::Talk::treat_as_anon( $self->poster, $self->journal );
    $opts->{nocss}        = $opts->{anon_comment};
    $opts->{editor}       = $self->prop("editor");
    $opts->{journal}      = $self->journal->user;
    $opts->{ditemid}      = $self->entry->ditemid;

    my $body = $self->body_raw;
    LJ::CleanHTML::clean_comment( \$body, $opts ) if $body;
    return $body;
}

# comement body, but trimmed to $char_max
sub body_html_summary {
    my ( $self, $char_max, %opts ) = @_;
    return LJ::html_trim( $self->body_html(%opts), $char_max );
}

# comment body, plaintext
sub body_text {
    my $self = $_[0];
    my $body = $self->body_html;
    return LJ::strip_html($body);
}

sub subject_html {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return LJ::ehtml( $self->{subject} );
}

sub subject_text {
    my $self    = $_[0];
    my $subject = $self->subject_raw;
    return LJ::ehtml($subject);
}

sub state {
    __PACKAGE__->preload_rows();
    return $_[0]->{state} || '';
}

sub is_active {
    return $_[0]->state eq 'A' ? 1 : 0;
}

sub is_screened {
    return $_[0]->state eq 'S' ? 1 : 0;
}

sub is_deleted {
    return $_[0]->state eq 'D' ? 1 : 0;
}

sub is_frozen {
    return $_[0]->state eq 'F' ? 1 : 0;
}

sub viewable_by_others {
    my ($self) = @_;

    # Is the comment attached to a visible entry?
    my $remote = LJ::get_remote();
    return 0 unless $self->entry && $self->entry->visible_to($remote);

    # If the entry is visible, the comment should be generally viewable unless
    # the comment is deleted, screened, or posted by a suspended user.
    return 0 if $self->is_deleted;
    return 0 if $self->is_screened;
    return 0 if $self->poster && $self->poster->is_suspended;

    return 1;
}

sub visible_to {
    my ( $self, $u ) = @_;

    return 0 unless LJ::isu($u);
    return 0 unless $self->entry && $self->entry->visible_to($u);

    my $posted_comment = $self->poster && $u->equals( $self->poster );
    my $posted_entry   = $self->entry->poster
        && $u->equals( $self->entry->poster );
    my $posted_parent =
           $self->parent
        && $self->parent->poster
        && $u->equals( $self->parent->poster );
    my $posted_by_admin = $self->poster
        && $self->poster->can_manage( $self->journal );

    # screened comment
    return 0 if $self->is_screened && !    # allowed viewers:
        (
        $u->can_manage( $self->journal )       # owns the journal
        || $posted_comment || $posted_entry    # owns the content
        || ( $posted_parent && $posted_by_admin )
        );

    # person this is in reply to,
    # as long as this comment was by a moderator

    # comments from suspended users aren't visible
    return 0 if $self->poster && $self->poster->is_suspended;

    return 1;
}

sub remote_can_delete {
    my $self   = $_[0];
    my $remote = LJ::User->remote;
    return $self->user_can_delete($remote);
}

sub user_can_delete {
    my ( $self, $targetu ) = @_;
    return 0 unless LJ::isu($targetu);

    my $journalu = $self->journal;
    my $posteru  = $self->poster;
    my $poster   = $posteru ? $posteru->{user} : undef;

    return LJ::Talk::can_delete( $targetu, $journalu, $posteru, $poster );
}

sub remote_can_edit {
    my ( $self, $errref ) = @_;
    my $remote = LJ::get_remote();
    return $self->user_can_edit( $remote, $errref );
}

sub user_can_edit {
    my ( $self, $u, $errref ) = @_;

    return 0 unless $u;

    $$errref = LJ::Lang::ml('talk.error.cantedit.invalid');
    return 0 unless $self && $self->valid;

    # comment editing must be enabled and the user must have the cap
    $$errref = LJ::Lang::ml('talk.error.cantedit');
    return 0 unless LJ::is_enabled("edit_comments");
    return 0 unless $u->can_edit_comments;

    # entry cannot be suspended
    return 0 if $self->entry->is_suspended;

    # user must be the poster of the comment
    unless ( $u->equals( $self->poster ) ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.notyours');
        return 0;
    }

    # user cannot be read-only
    return 0 if $u->is_readonly;

    my $journal = $self->journal;

    # journal owner must have commenting enabled
    if ( $journal->prop('opt_showtalklinks') eq "N" ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.commentingdisabled');
        return 0;
    }

    # user cannot be banned from commenting
    if ( $journal->has_banned($u) ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.banned');
        return 0;
    }

    # user must be a friend if friends-only commenting is on
    if ( $journal->prop('opt_whocanreply') eq "friends" && !$journal->trusts_or_has_member($u) ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.notfriend');
        return 0;
    }

    # comment cannot have any replies; deleted comments don't count
    if ( $self->has_nondeleted_children ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.haschildren');
        return 0;
    }

    # comment cannot be deleted
    if ( $self->is_deleted ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.isdeleted');
        return 0;
    }

    # comment cannot be frozen
    if ( $self->is_frozen ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.isfrozen');
        return 0;
    }

    # comment must be visible to the user
    unless ( $self->visible_to($u) ) {
        $$errref = LJ::Lang::ml('talk.error.cantedit.notvisible');
        return 0;
    }

    $$errref = "";
    return 1;
}

sub mark_as_spam {
    my $self = $_[0];
    LJ::Talk::mark_comment_as_spam( $self->poster, $self->jtalkid );
}

# returns comment action buttons (screen, freeze, delete, etc...)
sub manage_buttons {
    my $self    = $_[0];
    my $dtalkid = $self->dtalkid;
    my $journal = $self->journal;
    my $jargent = "journal=$journal->{'user'}&amp;";

    my $remote = LJ::get_remote() or return '';

    my $managebtns = '';

    return '' unless $self->entry->poster;

    my $poster = $self->poster ? $self->poster->user : "";

    if ( $self->remote_can_edit ) {
        $managebtns .=
              "<a href='"
            . $self->edit_url . "'>"
            . LJ::img( "editcomment", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
    }

    if ( LJ::Talk::can_delete( $remote, $self->journal, $self->entry->poster, $poster ) ) {
        $managebtns .= "<a href='$LJ::SITEROOT/delcomment?${jargent}id=$dtalkid'>"
            . LJ::img( "btn_del", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
    }

    if ( LJ::Talk::can_freeze( $remote, $self->journal, $self->entry->poster, $poster ) ) {
        unless ( $self->is_frozen ) {
            $managebtns .=
                "<a href='$LJ::SITEROOT/talkscreen?mode=freeze&amp;${jargent}talkid=$dtalkid'>"
                . LJ::img( "btn_freeze", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
        }
        else {
            $managebtns .=
                "<a href='$LJ::SITEROOT/talkscreen?mode=unfreeze&amp;${jargent}talkid=$dtalkid'>"
                . LJ::img( "btn_unfreeze", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
        }
    }

    if ( LJ::Talk::can_screen( $remote, $self->journal, $self->entry->poster, $poster ) ) {
        unless ( $self->is_screened ) {
            $managebtns .=
                "<a href='$LJ::SITEROOT/talkscreen?mode=screen&amp;${jargent}talkid=$dtalkid'>"
                . LJ::img( "btn_scr", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
        }
        else {
            $managebtns .=
                "<a href='$LJ::SITEROOT/talkscreen?mode=unscreen&amp;${jargent}talkid=$dtalkid'>"
                . LJ::img( "btn_unscr", "", { align => 'absmiddle', hspace => 2 } ) . "</a>";
        }
    }

    return $managebtns;
}

# returns info for javascript comment management
# can be used as a class method if $journal is passed explicitly
sub info {
    my ( $self, $journal ) = @_;
    my $remote = LJ::get_remote();
    $journal ||= $self->journal or return {};

    return {
        canAdmin => $remote && $remote->can_manage($journal),
        canSpam  => !LJ::sysban_check( 'spamreport', $journal->user ),
        journal  => $journal->user,
        remote   => $remote ? $remote->user : '',
    };
}

sub thread_has_subscription {
    my ( $comment, $remote, $u ) = @_;

    my @unknown_tracking_status;
    my $watched = 0;

    while ( $comment && $comment->valid && $comment->parenttalkid ) {

        # check cache
        $comment->{_watchedby} ||= {};
        my $thread_watched = $comment->{_watchedby}->{ $u->{userid} };

        my $had_cached = defined $thread_watched;

        unless ($had_cached) {
            $thread_watched = $remote->has_subscription(
                event          => "JournalNewComment",
                journal        => $u,
                arg2           => $comment->parenttalkid,
                require_active => 1,
            );
        }

        if ($thread_watched) {
            $watched = 1;

            # we had to go up a couple of levels before we could figure out
            # whether we were watching or not
            # so fix the status of intervening levels
            foreach (@unknown_tracking_status) {
                my $c = LJ::Comment->new( $u, dtalkid => $_ );
                $c->{_watchedby}->{ $u->{userid} } = $thread_watched;
            }
            @unknown_tracking_status = ();
        }

        # cache in this comment object if it's being watched by this user
        $comment->{_watchedby}->{ $u->{userid} } = $thread_watched;

        # shortcircuit and stop going up the tree because:
        last if $thread_watched;    # current comment is watched
        last if $had_cached;        # we've been to this section of the ancestor tree already

        push @unknown_tracking_status, $comment->dtalkid;
        $comment = $comment->parent;
    }

    return $watched;
}

sub indent {
    return LJ::Talk::Post::indent(@_);
}

sub blockquote {
    return LJ::Talk::Post::blockquote(@_);
}

# used for comment email notification headers
sub email_messageid {
    my $self = $_[0];
    return "<" . join( "-", "comment", $self->journal->id, $self->dtalkid ) . "\@$LJ::DOMAIN>";
}

my @_ml_strings_en = (
    'esn.journal_new_comment.subject',    # 'Subject:',
    'esn.journal_new_comment.message',    # 'Message',

    'esn.screened',             # 'This comment was screened.',
    'esn.you_must_unscreen',    # 'You must respond to it or unscreen it before others can see it.',
    'esn.here_you_can',         # 'From here, you can:',

    'esn.reply_at_webpage',     # '[[openlink]]Reply[[closelink]] at the webpage',
    'esn.unscreen_comment',     # '[[openlink]]Unscreen the comment[[closelink]]',
    'esn.edit_comment',         # '[[openlink]]Edit the comment[[closelink]]',
    'esn.delete_comment',       # '[[openlink]]Delete the comment[[closelink]]',
    'esn.view_comments',        # '[[openlink]]View all comments[[closelink]] to this entry',
    'esn.view_threadroot'
    ,    # '[[openlink]]Go to the top of the thread[[closelink]] this comment is part of',
    'esn.view_thread',    # '[[openlink]]View the thread[[closelink]] beginning with this comment',

    'esn.if_suport_form', # 'If your mail client supports it, you can also reply here:',

    'esn.journal_new_comment.anonymous.comment',    # 'Their reply was:',
    'esn.journal_new_comment.anonymous.reply_to.anonymous_comment.to_your_post3'
    , # 'Somebody replied to another comment somebody left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.anonymous.reply_to.user_comment.to_your_post3'
    , # 'Somebody replied to another comment [[pwho]] left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.anonymous.reply_to.your_comment.to_post3'
    , # 'Somebody replied to another comment you left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.anonymous.reply_to.your_comment.to_your_post3'
    , # 'Somebody replied to another comment you left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.anonymous.reply_to.your_post3'
    , # 'Somebody replied to [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which you said:',

    'esn.journal_new_comment.edit_reason',
    'esn.journal_new_comment.user.comment',    # 'Their reply was:',
    'esn.journal_new_comment.user.edit_reply_to.anonymous_comment.to_your_post3'
    , # '[[who]] edited a reply to another comment somebody left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.edit_reply_to.user_comment.to_your_post3'
    , # '[[who]] edited a reply to another comment [[pwho]] left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.edit_reply_to.your_comment.to_post3'
    , # '[[who]] edited a reply to another comment you left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.edit_reply_to.your_comment.to_your_post3'
    , # '[[who]] edited a reply to another comment you left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.edit_reply_to.your_post3'
    , # '[[who]] edited a reply to [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which you said:',
    'esn.journal_new_comment.user.new_comment',    # 'Their new reply was:',

    'esn.journal_new_comment.user.reply_to.anonymous_comment.to_your_post3'
    , # '[[who]] replied to another comment somebody left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.reply_to.user_comment.to_your_post3'
    , # '[[who]] replied to another comment [[pwho]] left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.reply_to.your_comment.to_post3'
    , # '[[who]] replied to another comment you left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.reply_to.your_comment.to_your_post3'
    , # '[[who]] replied to another comment you left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment they replied to was:',
    'esn.journal_new_comment.user.reply_to.your_post3'
    , # '[[who]] replied to [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which you said:',

    'esn.journal_new_comment.you.edit_reply_to.anonymous_comment.to_post3'
    , # 'You edited a reply to another comment somebody left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.anonymous_comment.to_your_post3'
    , # 'You edited a reply to another comment somebody left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.post3'
    , # 'You edited a reply to [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which [[pwho]] said:',
    'esn.journal_new_comment.you.edit_reply_to.user_comment.to_post3'
    , # 'You edited a reply to another comment [[pwho]] left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.user_comment.to_your_post3'
    , # 'You edited a reply to another comment [[pwho]] left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.your_comment.to_post3'
    , # 'You edited a reply to another comment you left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.your_comment.to_your_post3'
    , # 'You edited a reply to another comment you left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.edit_reply_to.your_post3'
    , # 'You edited a reply to [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which you said:',

    'esn.journal_new_comment.you.reply_to.anonymous_comment.to_post3'
    , # 'You replied to another comment somebody left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.anonymous_comment.to_your_post3'
    , # 'You replied to another comment somebody left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.post3'
    , # 'You replied to [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which [[pwho]] said:',
    'esn.journal_new_comment.you.reply_to.user_comment.to_post3'
    , # 'You replied to another comment [[pwho]] left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.user_comment.to_your_post3'
    , # 'You replied to another comment [[pwho]] left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.your_comment.to_post3'
    , # 'You replied to another comment you left in [[openlink]]a [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.your_comment.to_your_post3'
    , # 'You replied to another comment you left in [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]]. The comment you replied to was:',
    'esn.journal_new_comment.you.reply_to.your_post3'
    , # 'You replied to [[openlink]]your [[sitenameshort]] post[[postsubject]][[closelink]][[postsecurity]] in which you said:',

    'esn.journal_new_comment.your.comment',        # 'Your reply was:',
    'esn.journal_new_comment.your.new_comment',    # 'Your new reply was:',
);

# Implementation for both format_text_mail and format_html_mail.
sub _format_mail_both {
    my ( $self, $targetu, $is_html ) = @_;

    my $parent  = $self->parent;
    my $entry   = $self->entry;
    my $posteru = $self->poster;
    my $edited  = $self->is_edited;

    my $who = '';                                  # Empty means anonymous

    my ( $k_who, $k_what, $k_reply_edit );
    if ($posteru) {
        if ( $posteru->{name} eq $posteru->display_username ) {
            if ($is_html) {
                my $profile_url = $posteru->profile_url;
                $who = " <a href=\"$profile_url\">" . $posteru->display_username . "</a>";
            }
            else {
                $who = $posteru->display_username;
            }
        }
        else {
            if ($is_html) {
                my $profile_url = $posteru->profile_url;
                $who =
                      LJ::ehtml( $posteru->{name} )
                    . " (<a href=\"$profile_url\">"
                    . $posteru->display_username . "</a>)";
            }
            else {
                $who = $posteru->{name} . " (" . $posteru->display_username . ")";
            }
        }
        if ( $targetu->equals($posteru) ) {
            if ($edited) {

                # 'You edit your comment to...';
                $k_who        = 'you.edit_reply_to';
                $k_reply_edit = 'your.new_comment';
            }
            else {
                # 'You replied to...'
                $k_who        = 'you.reply_to';
                $k_reply_edit = 'your.comment';
            }
        }
        else {
            if ($edited) {

                # 'LJ-user ' . $posteru->{name} . ' edit reply to...';
                $k_who        = 'user.edit_reply_to';
                $k_reply_edit = 'user.new_comment';
            }
            else {
                # 'LJ-user ' . $posteru->{name} . ' replied to...';
                $k_who        = 'user.reply_to';
                $k_reply_edit = 'user.comment';
            }
        }
    }
    else {
        # 'Somebody replied to';
        $k_who        = 'anonymous.reply_to';
        $k_reply_edit = 'anonymous.comment';
    }

    # Parent post author. Empty string means 'You'.
    my $parentu = $entry->journal;
    my $pwho = '';    #author of the commented post/comment. If empty - it's you or anonymous

    if ($is_html) {
        if ( !$parent && !$parentu->equals($targetu) ) {

            # comment to a post and e-mail is going to be sent to not-AUTHOR of the journal
            my $p_profile_url = $entry->poster->profile_url;

            # pwho - author of the post
            # If the user's name hasn't been set (it's the same as display_username), then
            # don't display both
            if ( $entry->poster->{name} eq $entry->poster->display_username ) {
                $pwho = "<a href=\"$p_profile_url\">" . $entry->poster->display_username . "</a>";
            }
            else {
                $pwho =
                      LJ::ehtml( $entry->poster->{name} )
                    . " (<a href=\"$p_profile_url\">"
                    . $entry->poster->display_username . "</a>)";
            }
        }
        elsif ($parent) {
            my $threadu = $parent->poster;
            if ( $threadu && !$threadu->equals($targetu) ) {
                my $p_profile_url = $threadu->profile_url;
                if ( $threadu->{name} eq $threadu->display_username ) {
                    $pwho = "<a href=\"$p_profile_url\">" . $threadu->display_username . "</a>";
                }
                else {
                    $pwho =
                          LJ::ehtml( $threadu->{name} )
                        . " (<a href=\"$p_profile_url\">"
                        . $threadu->display_username . "</a>)";
                }
            }
        }
    }
    else {
        if ( !$parent && !$parentu->equals($targetu) ) {
            if ( $entry->poster->{name} eq $entry->poster->display_username ) {
                $pwho = $entry->poster->display_username;
            }
            else {
                $pwho = $entry->poster->{name} . " (" . $entry->poster->display_username . ")";
            }
        }
        elsif ($parent) {
            my $threadu = $parent->poster;
            if ( $threadu && !$threadu->equals($targetu) ) {
                if ( $threadu->{name} eq $threadu->display_username ) {
                    $pwho = $threadu->display_username;
                }
                else {
                    $pwho = $threadu->{name} . " (" . $threadu->display_username . ")";
                }
            }
        }
    }

    # Parent post security. Only include if post is locked/filtered.
    my $postsecurity = '';    # if empty, the post is public or private

    if ( $self->entry->security eq 'usemask' ) {
        $postsecurity = ' [locked]';
    }

    # ESN directed to comment poster
    if ( $targetu->equals( $self->poster ) ) {

        # ->parent returns undef/0 if parent is an entry.
        if ($parent) {
            if ($pwho) {

                # '... a comment ' . $pwho . ' left in post.';
                $k_what = 'user_comment';
            }
            else {
                # '... a comment you left in post.';
                if ( $parent->poster ) {
                    $k_what = 'your_comment';
                }
                else {
                    $k_what = 'anonymous_comment';
                }
            }
            if ( $targetu->equals( $entry->journal ) ) {
                $k_what .= '.to_your_post3';
            }
            else {
                $k_what .= '.to_post3';
            }
        }
        else {
            if ($pwho) {
                $k_what = 'post3';
            }
            else {
                $k_what = 'your_post3';
            }
        }

        # ESN directed to entry author
    }
    elsif ( $targetu->equals( $entry->journal ) ) {
        if ($parent) {
            if ($pwho) {

                # '... another comment ' . $pwho . ' left in your post.';
                $k_what = 'user_comment.to_your_post3';
            }
            else {
                if ( $parent->poster ) {
                    $k_what = 'your_comment.to_your_post3';
                }
                else {
                    # '... another comment you left in your post.';
                    $k_what = 'anonymous_comment.to_your_post3';
                }
            }
        }
        else {
            $k_what = 'your_post3';
        }

        # ESN directed to author parent comment or post
    }
    else {
        if ($parent) {
            if ( $parent->poster ) {
                if ($pwho) {
                    $k_what = 'user_comment.to_post3';
                }
                else {
                    $k_what = 'your_comment.to_post3';
                }
            }
            else {
                # '... another comment you left in your post.';
                $k_what = 'anonymous_comment.to_post3';
            }
        }
        else {
            if ($pwho) {
                $k_what = 'post3';
            }
            else {
                $k_what = 'your_post3';
            }
        }
    }

    # Precache text lines, using DEFAULT_LANG for $targetu
    my $lang = $LJ::DEFAULT_LANG;
    LJ::Lang::get_text_multi( $lang, undef, \@_ml_strings_en );

    my $body = '';
    $body = "<head><meta http-equiv=\"Content-Type\" content=\"text/html\" /></head><body>"
        if $is_html;

    my $vars = {
        who           => $who,
        pwho          => $pwho,
        sitenameshort => $LJ::SITENAMESHORT,
        postsecurity  => $postsecurity
    };

    # make hyperlinks for post
    my $talkurl = $entry->url;
    if ($is_html) {
        $vars->{openlink}  = "<a href=\"$talkurl\">";
        $vars->{closelink} = "</a>";
    }
    else {
        $vars->{openlink}  = '';
        $vars->{closelink} = " ( $talkurl )";
    }

    my $subject = $is_html ? $entry->subject_html : $entry->subject_text;
    $subject = " \"$subject\""
        if ($subject);

    $vars->{postsubject} = $subject;

    my $ml_prefix = "esn.journal_new_comment.";
    $k_who        = $ml_prefix . $k_who;
    $k_reply_edit = $ml_prefix . $k_reply_edit;

    my $intro = LJ::Lang::get_text( $lang, $k_who . '.' . $k_what, undef, $vars );

    if ($is_html) {
        my $pichtml;
        if ($posteru) {
            my ( $pic, $pic_kw ) = $self->userpic;

            if ( $pic && $pic->load_row ) {
                $pichtml =
                    "<img src=\"$LJ::USERPIC_ROOT/$pic->{picid}/$pic->{userid}\" align='absmiddle' "
                    . "width='$pic->{width}' height='$pic->{height}' "
                    . "hspace='1' vspace='2' alt='"
                    . $pic->alttext($pic_kw) . "' /> ";
            }
        }

        if ($pichtml) {
            $body .=
"<table summary=''><tr valign='top'><td>$pichtml</td><td width='100%'>$intro</td></tr></table>\n";
        }
        else {
            $body .=
                "<table summary=''><tr valign='top'><td width='100%'>$intro</td></tr></table>\n";
        }

        $body .= blockquote( $parent ? $parent->body_html : $entry->event_html );
    }
    else {
        $body .= $intro . "\n\n" . indent( $parent ? $parent->body_raw : $entry->event_raw, ">" );
    }

    # reason for editing, if applicable
    if ($edited) {
        my $reason = $self->edit_reason;
        if ($is_html) {
            $body .= "<br />"
                . LJ::Lang::get_text(
                $lang, "esn.journal_new_comment.edit_reason",
                undef, { reason => LJ::ehtml($reason) }
                )
                . "<br />"
                if $reason;
        }
        else {
            $body .= "\n\n"
                . LJ::Lang::get_text( $lang, "esn.journal_new_comment.edit_reason",
                undef, { reason => $reason } )
                if $reason;
        }
    }

    $body .= "\n\n" . LJ::Lang::get_text( $lang, $k_reply_edit, undef, $vars ) . "\n\n";

    if ($is_html) {
        my $subjecticon = LJ::Talk::print_subjecticon_by_id( $self->prop('subjecticon') );

        my $heading;
        if ( $self->subject_raw ) {
            $heading = "<b>"
                . LJ::Lang::get_text( $lang, $ml_prefix . 'subject', undef ) . "</b> "
                . $self->subject_html;
        }
        $heading .= $subjecticon;
        $heading .= "<br />" if $heading;

        # this needs to be one string so blockquote handles it properly.

        if ( $self->admin_post ) {
            $body .= '<br/>'
                . LJ::Lang::get_text(
                $lang, "esn.journal_new_entry.admin_post",
                undef, { img => LJ::img('admin-post') }
                ) . '<br/>';
        }

        $body .= blockquote( "$heading" . $self->body_html );

        $body .= "<br />";
    }
    else {
        if ( my $subj = $self->subject_raw ) {
            $body .= Text::Wrap::wrap(
                " " . LJ::Lang::get_text( $lang, $ml_prefix . 'subject', undef ) . " ",
                "", $subj )
                . "\n\n";
        }

        if ( $self->admin_post ) {
            $body .= LJ::Lang::get_text( $lang, "esn.journal_new_entry.admin_post.text" ) . "\n\n";
        }

        $body .= indent( $self->body_raw ) . "\n\n";

        # Don't wrap options, only text.
        $body = Text::Wrap::wrap( "", "", $body ) . "\n";
    }

    my $can_unscreen = $self->is_screened
        && LJ::Talk::can_unscreen( $targetu, $entry->journal, $entry->poster,
        $posteru ? $posteru->{user} : undef );

    if ( $self->is_screened ) {
        $body .= LJ::Lang::get_text( $lang, 'esn.screened',          undef ) . " ";
        $body .= LJ::Lang::get_text( $lang, 'esn.you_must_unscreen', undef )
            if $can_unscreen;
        $body .= "\n";
    }

    my $commentsurl = $talkurl . "#comments";

    $body .= LJ::Lang::get_text( $lang, 'esn.here_you_can', undef, $vars );
    $body .= LJ::Event::format_options(
        undef, $is_html, $lang, $vars,
        {
            'esn.reply_at_webpage' => [ 1, $self->reply_url ],
            'esn.unscreen_comment' => [ $can_unscreen ? 2 : 0, $self->unscreen_url ],
            'esn.edit_comment'     => [ $self->user_can_edit($targetu) ? 3 : 0, $self->edit_url ],
            'esn.delete_comment' => [ $self->user_can_delete($targetu) ? 4 : 0, $self->delete_url ],
            'esn.view_comments'  => [ 5, $commentsurl ],
            'esn.view_threadroot' => [ $self->parenttalkid != 0 ? 6 : 0, $self->threadroot_url ],
            'esn.view_thread'     => [ 7, $self->thread_url ],
        }
    );

    my $open_link  = "";
    my $close_link = "";
    my $reset_link = "$LJ::SITEROOT/manage/emailpost";
    if ($is_html) {
        $open_link  = qq{<a href="$reset_link">};
        $close_link = q{</a>};
    }
    else {
        $close_link = " ($reset_link)";
    }
    $body .= "\n"
        . LJ::Lang::get_text( $lang, 'esn.reply_to_email2', undef,
        { openlink => $open_link, closelink => $close_link } )
        . "\n";

    $body .= "<br></body>\n" if $is_html;

    return $body;
}

sub format_text_mail {
    my ( $self, $targetu ) = @_;
    croak "invalid targetu passed to format_text_mail"
        unless LJ::isu($targetu);

    return _format_mail_both( $self, $targetu, 0 );
}

sub format_html_mail {
    my ( $self, $targetu ) = @_;
    croak "invalid targetu passed to format_html_mail"
        unless LJ::isu($targetu);

    return _format_mail_both( $self, $targetu, 1 );
}

sub delete {
    my $self = $_[0];

    return LJ::Talk::delete_comment(
        $self->journal,
        $self->nodeid,    # jitemid
        $self->jtalkid,
        $self->state
    );
}

sub delete_thread {
    my $self = $_[0];

    return LJ::Talk::delete_thread(
        $self->journal,
        $self->nodeid,    # jitemid
        $self->jtalkid
    );
}

=head2 C<< $cmt->userpic >>

Returns a LJ::Userpic object for the poster of the comment, or undef.

If called in a list context, returns ( LJ::Userpic object, keyword )

=cut

sub userpic {
    my $self = $_[0];

    my $up = $self->poster;
    return unless $up;

    # return the picture from keyword, if defined
    # else return poster's default userpic
    my $kw  = $_[0]->userpic_kw;
    my $pic = LJ::Userpic->new_from_keyword( $up, $kw ) || $up->userpic;

    return wantarray ? ( $pic, $kw ) : $pic;
}

=head2 C<< $cmt->userpic_kw >>

Returns the userpic keyword used on this comment, or undef.

=cut

sub userpic_kw {
    my $self = $_[0];

    my $up = $self->poster;
    return unless $up;

    if ( $up->userpic_have_mapid ) {
        my $mapid = $self->prop('picture_mapid');

        return $up->get_keyword_from_mapid($mapid) if $mapid;
    }
    else {
        return $self->prop('picture_keyword');
    }
}

=head2 C<< $cmt->admin_post

Returns true if this comment is an official administrator comment.

=cut

sub admin_post {
    my $self = $_[0];

    return 0 unless $self->journal->is_community;
    return 0
        unless $self->poster && $self->poster->can_manage( $self->journal );

    if ( exists $_[1] ) {
        $_[0]->set_prop( 'admin_post', $_[1] ? 1 : 0 );
    }
    else {
        return $_[0]->prop('admin_post') ? 1 : 0;
    }
}

sub poster_ip {
    return $_[0]->prop("poster_ip");
}

# sets the new poster IP and returns the value that was set
sub set_poster_ip {
    my $self = $_[0];

    return "" unless LJ::is_web_context();

    my $current_ip = $self->poster_ip;

    my $new_ip    = BML::get_remote_ip();
    my $forwarded = BML::get_client_header('X-Forwarded-For');
    $new_ip = "$forwarded, via $new_ip" if $forwarded && $forwarded ne $new_ip;

    if ( !$current_ip || $new_ip eq $current_ip ) {
        $self->set_prop( poster_ip => $new_ip );
        return $new_ip;
    }

    if ( $current_ip =~ /\(originally ([\w\.]+)\)/ ) {
        if ( $new_ip eq $1 ) {
            $self->set_prop( poster_ip => $new_ip );
            return $new_ip;
        }

        $new_ip = "$new_ip (originally $1)";
    }
    else {
        $new_ip = "$new_ip (originally $current_ip)";
    }

    $self->set_prop( poster_ip => $new_ip );
    return $new_ip;
}

sub edit_reason {
    return $_[0]->prop("edit_reason");
}

sub edit_time {
    return $_[0]->prop("edit_time");
}

sub is_edited {
    return $_[0]->edit_time ? 1 : 0;
}

1;
