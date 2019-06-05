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
# LiveJournal entry object.
#
# Just framing right now, not much to see here!
#

package LJ::Entry;
use strict;
our $AUTOLOAD;
use Carp qw/ croak confess /;

=head1 NAME

LJ::Entry

=head1 CLASS METHODS

=cut

# internal fields:
#
#    u: object, always present
#    anum:    lazily loaded, either by ctor or _loaded_row
#    ditemid: lazily loaded
#    jitemid: always present
#    props:   hashref of props,  loaded if _loaded_props
#    subject: text of subject,   loaded if _loaded_text
#    event:   text of log event, loaded if _loaded_text
#    subject_orig: text of subject without transcoding,   present if unknown8bit
#    event_orig:   text of log event without transcoding, present if unknown8bit

#    eventtime:  mysql datetime of event, loaded if _loaded_row
#    logtime:    mysql datetime of event, loaded if _loaded_row
#    security:   "public", "private", "usemask", loaded if _loaded_row
#    allowmask:  if _loaded_row
#    posterid:   if _loaded_row
#    comments:   arrayref of comment objects on this entry
#    talkdata:   hash of raw comment data for this entry

#    userpic

#    _loaded_text:     loaded subject/text
#    _loaded_row:      loaded log2 row
#    _loaded_props:    loaded props
#    _loaded_comments: loaded comments
#    _loaded_talkdata: loaded talkdata

my %singletons = ();    # journalid->jitemid->singleton

sub reset_singletons {
    %singletons = ();
}

# <LJFUNC>
# name: LJ::Entry::new
# class: entry
# des: Gets a journal entry.
# args: uuserid, opts
# des-uuserid: A user id or user object ($u ) to load the entry for.
# des-opts: Hash of optional keypairs.
#           'jitemid' => a journal itemid (no anum)
#           'ditemid' => display itemid (a jitemid << 8 + anum)
#           'anum'    => the id passed was an ditemid, use the anum
#                        to create a proper jitemid.
#           'slug'    => the slug in the URL to load from
# returns: A new LJ::Entry object.  undef on failure.
# </LJFUNC>
sub new {
    my $class = shift;
    my $self  = bless {};

    my $uuserid = shift;
    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ( $n_arg % 2 == 0 );

    my %opts = @_;

    croak("can't supply both anum and ditemid")
        if defined $opts{anum} && defined $opts{ditemid};

    croak("can't supply both itemid and ditemid")
        if defined $opts{ditemid} && defined $opts{jitemid};

    croak("can't supply slug with anything else")
        if defined $opts{slug} && ( defined $opts{jitemid} || defined $opts{ditemid} );

    # FIXME: don't store $u in here, or at least call LJ::load_userids() on all singletons
    #        if LJ::want_user() would have been called
    $self->{u} = LJ::want_user($uuserid) or croak("invalid user/userid parameter: $uuserid");

    $self->{anum}    = delete $opts{anum};
    $self->{ditemid} = delete $opts{ditemid};
    $self->{jitemid} = delete $opts{jitemid};
    $self->{slug}    = LJ::canonicalize_slug( delete $opts{slug} );

    # make arguments numeric
    for my $f (qw(ditemid jitemid anum)) {
        $self->{$f} = int( $self->{$f} ) if defined $self->{$f};
    }

    croak("need to supply either a jitemid or ditemid or slug")
        unless defined $self->{ditemid}
        || defined $self->{jitemid}
        || defined $self->{slug};

    croak( "Unknown parameters: " . join( ", ", keys %opts ) )
        if %opts;

    if ( $self->{ditemid} ) {
        $self->{_untrusted_anum} = $self->{ditemid} & 255;
        $self->{jitemid}         = $self->{ditemid} >> 8;
    }

    # If specified by slug, look it up in the database.
    # FIXME: This should be memcached in some efficient method. By slug?
    if ( defined $self->{slug} ) {
        my $jitemid =
            $self->{u}
            ->selectrow_array( q{SELECT jitemid FROM logslugs WHERE journalid = ? AND slug = ?},
            undef, $self->{u}->id, $self->{slug} );
        croak $self->{u}->errstr if $self->{u}->err;

        return undef unless $jitemid;
        return LJ::Entry->new( $self->{u}, jitemid => $jitemid );
    }

    # do we have a singleton for this entry?
    {
        my $journalid = $self->{u}->{userid};
        my $jitemid   = $self->{jitemid};

        $singletons{$journalid} ||= {};
        return $singletons{$journalid}->{$jitemid}
            if $singletons{$journalid}->{$jitemid};

        # save the singleton if it doesn't exist
        $singletons{$journalid}->{$jitemid} = $self;
    }

    return $self;
}

# sometimes item hashes don't have a journalid arg.
# in those cases call as ($u, $item) and the $u will
# be used
sub new_from_item_hash {
    my ( $class, $arg1, $item ) = @_;

    if ( LJ::isu($arg1) ) {
        $item->{journalid} ||= $arg1->id;
    }
    else {
        $item = $arg1;
    }

    # some item hashes have 'jitemid', others have 'itemid'
    $item->{jitemid} ||= $item->{itemid};

    croak "invalid item hash"
        unless $item && ref $item;
    croak "no journalid in item hash"
        unless $item->{journalid};
    croak "no entry information in item hash"
        unless $item->{ditemid} || ( $item->{jitemid} && defined( $item->{anum} ) );

    my $entry;

    # have a ditemid only?  no problem.
    if ( $item->{ditemid} ) {
        $entry = LJ::Entry->new( $item->{journalid}, ditemid => $item->{ditemid} );

        # jitemid/anum is okay too
    }
    elsif ( $item->{jitemid} && defined( $item->{anum} ) ) {
        $entry = LJ::Entry->new(
            $item->{journalid},
            jitemid => $item->{jitemid},
            anum    => $item->{anum}
        );
    }

    return $entry;
}

sub new_from_url {
    my ( $class, $url ) = @_;

    if ( $url =~ m!^(.+)/(\d+)\.html$! ) {
        my $u = LJ::User->new_from_url($1) or return undef;
        return LJ::Entry->new( $u, ditemid => $2 );
    }
    elsif ( $url =~ m!^(.+)/(\d\d\d\d/\d\d/\d\d)/([a-z0-9_-]+)\.html$! ) {
        my $u = LJ::User->new_from_url($1) or return undef;

        # This hack validates that the YYYY/MM/DD given to us is correct.
        my $date    = $2;
        my $ljentry = LJ::Entry->new( $u, slug => $3 );
        if ( defined $ljentry ) {
            my $dt = join( '/', split( '-', substr( $ljentry->eventtime_mysql, 0, 10 ) ) );
            return undef unless $dt eq $date;
            return $ljentry;
        }
    }

    return undef;
}

sub new_from_url_or_ditemid {
    my ( $class, $input, $u ) = @_;

    my $e = LJ::Entry->new_from_url($input);

    # couldn't be parsed as a URL, try as a ditemid
    $e ||= LJ::Entry->new( $u, ditemid => $input )
        if $input =~ /^(?:\d+)$/;

    return $e && $e->valid ? $e : undef;
}

sub new_from_row {
    my ( $class, %row ) = @_;

    my $journalu = LJ::load_userid( $row{journalid} );
    my $self     = $class->new( $journalu, jitemid => $row{jitemid} );
    $self->absorb_row(%row);

    return $self;
}

=head1 INSTANCE METHODS

=cut

# returns true if entry currently exists.  (it's possible for a given
# $u, to make a fake jitemid and that'd be a valid skeleton LJ::Entry
# object, even though that jitemid hasn't been created yet, or was
# previously deleted)
sub valid {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{_loaded_row};
}

sub jitemid {
    my $self = $_[0];
    return $self->{jitemid};
}

sub ditemid {
    my $self = $_[0];
    return $self->{ditemid} ||= ( ( $self->{jitemid} << 8 ) + $self->anum );
}

sub reply_url {
    my $self = $_[0];
    return $self->url( mode => 'reply' );
}

# returns permalink url
sub url {
    my ( $self, %opts ) = @_;
    my %style_opts = %{ delete $opts{style_opts} || {} };

    my %args = %opts;    # used later
    @args{ keys %style_opts } = values %style_opts;

    my $u      = $self->{u};
    my $view   = delete $opts{view};
    my $anchor = delete $opts{anchor};
    my $mode   = delete $opts{mode};

    croak "Unknown args passed to url: " . join( ",", keys %opts )
        if %opts;

    my $override = LJ::Hooks::run_hook( "entry_permalink_override", $self, %opts );
    return $override if $override;

    my $base_url = $self->ditemid;

    if ( my $slug = $self->slug ) {
        my $ymd = join( '/', split( '-', substr( $self->eventtime_mysql, 0, 10 ) ) );
        $base_url = $ymd . "/" . $slug;
    }

    my $url = $u->journal_base . "/" . $base_url . ".html";
    delete $args{anchor};
    if (%args) {
        $url .= "?";
        $url .= LJ::encode_url_string( \%args );
    }
    $url .= "#$anchor" if $anchor;
    return $url;
}

# returns a url that will display the number of comments on the entry
# as an image
sub comment_image_url {
    my $self = $_[0];
    my $u    = $self->{u};

    return
          "$LJ::SITEROOT/tools/commentcount?user="
        . $self->journal->user
        . "&ditemid="
        . $self->ditemid;
}

# returns a pre-generated comment img tag using the comment_image_url
sub comment_imgtag {
    my $self = $_[0];

    my $alttext = LJ::Lang::ml('setting.xpost.option.footer.vars.comment_image.alt');

    return
          '<img src="'
        . $self->comment_image_url
        . '" width="30" height="12" alt="'
        . $alttext
        . '" style="vertical-align: middle;"/>';
}

sub anum {
    my $self = $_[0];
    return $self->{anum} if defined $self->{anum};
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{anum} if defined $self->{anum};
    croak("couldn't retrieve anum for entry");
}

# method:
#   $entry->correct_anum
#   $entry->correct_anum($given_anum)
# if no given anum, gets it from the provided ditemid to constructor
# Note: an anum parsed from the ditemid cannot be trusted which is what we're verifying here
sub correct_anum {
    my ( $self, $given ) = @_;

    $given =
          defined $given   ? int($given)
        : $self->{ditemid} ? $self->{_untrusted_anum}
        :                    $self->{anum};

    return 0 unless $self->valid;
    return 0 unless defined $self->{anum} && defined $given;
    return $self->{anum} == $given;
}

# returns LJ::User object for the poster of this entry
sub poster {
    my $self = $_[0];
    return LJ::load_userid( $self->posterid );
}

sub posterid {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{posterid};
}

sub journalid {
    my $self = $_[0];
    return $self->{u}{userid};
}

sub journal {
    my $self = $_[0];
    return $self->{u};
}

sub eventtime_mysql {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{eventtime};
}

sub logtime_mysql {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{logtime};
}

sub logtime_unix {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return LJ::mysqldate_to_time( $self->{logtime}, 1 );
}

sub modtime_unix {
    my $self = $_[0];
    return $self->prop("revtime") || $self->logtime_unix;
}

sub security {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{security};
}

sub allowmask {
    my $self = $_[0];
    __PACKAGE__->preload_rows( [$self] ) unless $self->{_loaded_row};
    return $self->{allowmask};
}

sub preload {
    my ( $class, $entlist ) = @_;
    $class->preload_rows($entlist);
    $class->preload_props($entlist);

    # TODO: $class->preload_text($entlist);
}

# class method:
sub preload_rows {
    my ( $class, $entlist ) = @_;
    foreach my $en (@$entlist) {
        next if $en->{_loaded_row};

        my $lg = LJ::get_log2_row( $en->{u}, $en->{jitemid} );
        next unless $lg;

        # absorb row into given LJ::Entry object
        $en->absorb_row(%$lg);
    }
}

sub absorb_row {
    my ( $self, %row ) = @_;

    $self->{$_} = $row{$_} foreach (qw(allowmask posterid eventtime logtime security anum));
    $self->{_loaded_row} = 1;
}

# class method:
sub preload_props {
    my ( $class, $entlist ) = @_;
    foreach my $en (@$entlist) {
        next if $en->{_loaded_props};
        $en->_load_props;
    }
}

# method for preloading props into all outstanding singletons that haven't already
# loaded properties.
sub preload_props_all {
    foreach my $uid ( keys %singletons ) {
        my $hr = $singletons{$uid};

        my @load;
        foreach my $jid ( keys %$hr ) {
            next if $hr->{$jid}->{_loaded_props};
            push @load, $jid;
        }

        my $props = {};
        LJ::load_log_props2( $uid, \@load, $props );
        foreach my $jid ( keys %$props ) {
            $hr->{$jid}->{props}         = $props->{$jid};
            $hr->{$jid}->{_loaded_props} = 1;
        }
    }
}

# returns array of tags for this post
sub tags {
    my $self = $_[0];

    my $taginfo = LJ::Tags::get_logtags( $self->journal, $self->jitemid );
    return () unless $taginfo;

    my $entry_taginfo = $taginfo->{ $self->jitemid };
    return () unless $entry_taginfo;

    return values %$entry_taginfo;
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = $_[0];
    return 1 if $self->{_loaded_text};

    my $ret = LJ::get_logtext2( $self->{'u'}, $self->{'jitemid'} );
    my $lt  = $ret->{ $self->{jitemid} };
    return 0 unless $lt;

    $self->{subject} = $lt->[0];
    $self->{event}   = $lt->[1];

    if ( $self->prop("unknown8bit") ) {

        # save the old ones away, so we can get back at them if we really need to
        $self->{subject_orig} = $self->{subject};
        $self->{event_orig}   = $self->{event};

        # FIXME: really convert all the props?  what if we binary-pack some in the future?
        LJ::item_toutf8( $self->{u}, \$self->{'subject'}, \$self->{'event'}, $self->{props} );
    }

    $self->{_loaded_text} = 1;
    return 1;
}

sub slug {
    my $self = $_[0];
    my $u    = $self->{u};
    my $jid  = $u->id;

    # Get the slug from ourself, memcache, or the database. Populate both if
    # we do get the data.
    if ( scalar @_ == 1 ) {
        return $self->{slug}
            if $self->{_loaded_slug};
        $self->{_loaded_slug} = 1;

        my $mc = LJ::MemCache::get( [ $jid, "logslug:$jid:$self->{jitemid}" ] );
        return $self->{slug} = $mc
            if defined $mc;

        my $db =
            $u->selectrow_array( q{SELECT slug FROM logslugs WHERE journalid = ? AND jitemid = ?},
            undef, $jid, $self->{jitemid} )
            || '';
        croak $u->errstr if $u->err;

        LJ::MemCache::set( [ $jid, "logslug:$jid:$self->{jitemid}" ], $db );
        return $self->{slug} = $db;
    }

    # If deletion...
    if ( !defined $_[1] ) {
        $u->do( 'DELETE FROM logslugs WHERE journalid = ? AND jitemid = ?',
            undef, $jid, $self->{jitemid} );
        croak $u->errstr if $u->err;

        LJ::MemCache::set( [ $jid, "logslug:$jid:$self->{jitemid}" ], '' );

        $self->{_loaded_slug} = 1;
        return $self->{slug} = undef;
    }

    # Set it...
    my $slug = LJ::canonicalize_slug( $_[1] );
    croak 'Invalid slug'
        unless defined $slug && length $slug > 0;
    return $self->{slug}
        if defined $self->{slug} && $self->{slug} eq $slug;

    # Ensure this slug isn't already used...
    my $et = LJ::Entry->new( $u, slug => $slug );
    croak 'Slug already in use'
        if defined $et;

    # Looks good, now update our slug database (REPLACE since we're updating)
    $u->do( 'REPLACE INTO logslugs (journalid, jitemid, slug) VALUES (?, ?, ?)',
        undef, $jid, $self->{jitemid}, $slug );
    croak $u->errstr if $u->err;

    LJ::MemCache::set( [ $jid, "logslug:$jid:$self->{jitemid}" ], $slug );

    $self->{_loaded_slug} = 1;
    return $self->{slug} = $slug;
}

sub prop {
    my ( $self, $prop ) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props}{$prop};
}

sub props {
    my ( $self, $prop ) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props} || {};
}

sub _load_props {
    my $self = $_[0];
    return 1 if $self->{_loaded_props};

    my $props = {};
    LJ::load_log_props2( $self->{u}, [ $self->{jitemid} ], $props );
    $self->{props} = $props->{ $self->{jitemid} };

    $self->{_loaded_props} = 1;
    return 1;
}

sub set_prop {
    my ( $self, $prop, $val ) = @_;

    LJ::set_logprop( $self->journal, $self->jitemid, { $prop => $val } );
    $self->{props}{$prop} = $val;
    return 1;
}

# called automatically on $event->comments
# returns the same data as LJ::get_talk_data, with the addition
# of 'subject' and 'event' keys.
sub _load_comments {
    my $self = $_[0];
    return 1 if $self->{_loaded_comments};

    # need to load using talklib API
    my $comment_ref =
          $self->{_loaded_talkdata}
        ? $self->{talkdata}
        : LJ::Talk::get_talk_data( $self->journal, 'L', $self->jitemid );

    die "unable to load comment data for entry"
        unless ref $comment_ref;

    my @comment_list;

    my $u      = $self->journal;
    my $nodeid = $self->jitemid;

    # instantiate LJ::Comment singletons and set them on our $self
    foreach my $jtalkid ( keys %$comment_ref ) {
        my $row = $comment_ref->{$jtalkid};

        # at this point we have data for this comment loaded in memory
        # -- instantiate an LJ::Comment object as a singleton and absorb
        #    that data into the object
        my $comment = LJ::Comment->new( $u, jtalkid => $jtalkid );

        # add important info to row
        $row->{nodetype} = "L";
        $row->{nodeid}   = $nodeid;
        $comment->absorb_row(%$row);

        push @comment_list, $comment;
    }
    $self->set_comment_list(@comment_list);

    return $self;
}

sub comment_list {
    my $self = $_[0];
    $self->_load_comments unless $self->{_loaded_comments};
    return @{ $self->{comments} || [] };
}

sub set_comment_list {
    my ( $self, @args ) = @_;

    $self->{comments}         = \@args;
    $self->{_loaded_comments} = 1;

    return 1;
}

sub set_talkdata {
    my ( $self, $talkdata ) = @_;

    $self->{talkdata}         = $talkdata;
    $self->{_loaded_talkdata} = 1;

    return 1;
}

sub reply_count {
    my ( $self, %opts ) = @_;

    unless ( $opts{force_lookup} ) {
        my $rc = $self->prop('replycount');
        return $rc if defined $rc;
    }

    return LJ::Talk::get_replycount( $self->journal, $self->jitemid );
}

# returns "Leave a comment", "1 comment", "2 comments" etc
sub comment_text {
    my $self = $_[0];
    my $comments;

    my $comment_count = $self->reply_count;
    if ($comment_count) {
        $comments = $comment_count == 1 ? "1 Comment" : "$comment_count Comments";
    }
    else {
        $comments = "Leave a comment";
    }

    return $comments;
}

# returns data hashref suitable for use in S2 CommentInfo function
sub comment_info {
    my ( $self, %opts ) = @_;
    return unless %opts;
    return unless exists $opts{u};
    return unless exists $opts{remote};
    return unless exists $opts{style_args};

    my $u          = $opts{u};            # the journal being viewed
    my $remote     = $opts{remote};       # the person viewing the page
    my $style_args = $opts{style_args};
    my $viewall    = $opts{viewall};

    my $journal = exists $opts{journal} ? $opts{journal} : $u;    # journal entry was posted in
         # may be different from $u on a read page

    my $permalink = $self->url;
    my $comments_enabled =
        ( $viewall || ( $journal->{opt_showtalklinks} eq "Y" && !$self->comments_disabled ) )
        ? 1
        : 0;
    my $has_screened =
        ( $self->props->{hasscreened} && $remote && $journal && $remote->can_manage($journal) )
        ? 1
        : 0;
    my $screenedcount = $has_screened ? LJ::Talk::get_screenedcount( $journal, $self->jitemid ) : 0;
    my $replycount = $comments_enabled ? $self->reply_count : 0;
    my $nc         = "";
    $nc .= "nc=$replycount" if $replycount && $remote && $remote->{opt_nctalklinks};

    return {
        read_url      => LJ::Talk::talkargs( $permalink, $nc,          $style_args ),
        post_url      => LJ::Talk::talkargs( $permalink, "mode=reply", $style_args ),
        permalink_url => LJ::Talk::talkargs( $permalink, $style_args ),
        count         => $replycount,
        maxcomments                  => ( $replycount >= $u->count_maxcomments ) ? 1 : 0,
        enabled                      => $comments_enabled,
        comments_disabled_maintainer => $self->comments_disabled_maintainer,
        screened                     => $has_screened,
        screened_count               => $screenedcount,
        show_readlink                => $comments_enabled && ( $replycount || $has_screened ),
        show_readlink_hidden         => $comments_enabled,
        show_postlink                => $comments_enabled,
    };
}

# used in comment notification email headers
sub email_messageid {
    my $self = $_[0];
    return "<" . join( "-", "entry", $self->journal->id, $self->ditemid ) . "\@$LJ::DOMAIN>";
}

sub atom_id {
    my $self = $_[0];

    my $u       = $self->{u};
    my $ditemid = $self->ditemid;

    return $u->atomid . ":$ditemid";
}

# returns an XML::Atom::Entry object for a feed
# opts: synlevel ("full"), apilinks (bool)
sub atom_entry {
    my ( $self, %opts ) = @_;

    my $atom_entry = XML::Atom::Entry->new( Version => 1 );

    my $u = $self->{u};

    my $make_link = sub {
        my ( $rel, $href, $type, $title ) = @_;
        my $link = XML::Atom::Link->new( Version => 1 );
        $link->rel($rel);
        $link->href($href);
        $link->title($title) if $title;
        $link->type($type)   if $type;
        return $link;
    };

    $atom_entry->id( $self->atom_id );
    $atom_entry->title( $self->subject_text );

    $atom_entry->published( LJ::time_to_w3c( $self->logtime_unix, "Z" ) );
    $atom_entry->updated( LJ::time_to_w3c( $self->modtime_unix, 'Z' ) );

    my $author = XML::Atom::Person->new( Version => 1 );
    $author->name( $self->poster->name_orig );
    $atom_entry->author($author);

    $atom_entry->add_link( $make_link->( "alternate", $self->url, "text/html" ) );
    $atom_entry->add_link(
        $make_link->( "edit", $self->atom_url, "application/atom+xml", "Edit this post" ) )
        if $opts{apilinks};

    foreach my $tag ( $self->tags ) {
        my $category = XML::Atom::Category->new( Version => 1 );
        $category->term($tag);
        $atom_entry->add_category($category);
    }

    my $syn_level = $opts{synlevel} || $u->prop("opt_synlevel") || "full";

    # if syndicating the complete entry
    #   -print a content tag
    # elsif syndicating summaries
    #   -print a summary tag
    # else (code omitted), we're syndicating title only
    #   -print neither (the title has already been printed)
    #   note: the $event was also emptied earlier, in make_feed
    #
    # a lack of a content element is allowed,  as long
    # as we maintain a proper 'alternate' link (above)
    if ( $syn_level eq 'full' || $syn_level eq 'cut' ) {
        $atom_entry->content( $self->event_raw );
    }
    elsif ( $syn_level eq 'summary' ) {
        $atom_entry->summary( $self->event_summary );
    }

    return $atom_entry;
}

sub atom_url {
    my $self = $_[0];
    return "" unless $self->journal;
    return $self->journal->atom_base . "/entries/" . $self->jitemid;
}

# returns the entry as an XML Atom string, without the XML prologue
sub as_atom {
    my $self  = $_[0];
    my $entry = $self->atom_entry;
    my $xml   = $entry->as_xml;
    $xml =~ s!^<\?xml.+?>\s*!!s;
    return $xml;
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
sub event_raw {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub event_orig {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event_orig} || $self->{event};
}

sub subject_html {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    my $subject = $self->{subject};
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    return $subject;
}

sub subject_text {
    my $self = $_[0];
    $self->_load_text unless $self->{_loaded_text};
    my $subject = $self->{subject};
    LJ::CleanHTML::clean_subject_all( \$subject ) if $subject;
    return $subject;
}

# instance method.  returns HTML-cleaned/formatted version of the event
# optional $opt may be:
#    undef:   loads the opt_preformatted key and uses that for formatting options
#    1:       treats entry as preformatted (no breaks applied)
#    0:       treats entry as normal (newlines convert to HTML breaks)
#    hashref: passed to LJ::CleanHTML::clean_event verbatim
sub event_html {
    my ( $self, $opts ) = @_;

    if ( !defined $opts ) {
        $self->_load_props unless $self->{_loaded_props};
        $opts = { preformatted => $self->{props}{opt_preformatted} };
    }
    elsif ( !ref $opts ) {
        $opts = { preformatted => $opts };
    }

    my $remote      = LJ::get_remote();
    my $suspend_msg = $self->should_show_suspend_msg_to($remote) ? 1 : 0;
    $opts->{suspend_msg}         = $suspend_msg;
    $opts->{unsuspend_supportid} = $suspend_msg ? $self->prop("unsuspend_supportid") : 0;
    $opts->{journal}             = $self->{u}->user;
    $opts->{ditemid}             = $self->{ditemid};

    $self->_load_text unless $self->{_loaded_text};
    my $event = $self->{event};
    LJ::CleanHTML::clean_event( \$event, $opts );

    LJ::expand_embedded( $self->{u}, $self->ditemid, LJ::User->remote, \$event,
        sandbox => $opts->{sandbox}, );
    return $event;
}

# like event_html, but trimmed to $char_max
sub event_html_summary {
    my ( $self, $char_max, $opts, $trunc_ref ) = @_;
    return LJ::html_trim( $self->event_html($opts), $char_max, $trunc_ref );
}

sub event_text {
    my $self  = $_[0];
    my $event = $self->event_raw;
    LJ::CleanHTML::clean_event( \$event, { textonly => 1 } ) if $event;
    return $event;
}

# like event_html, but truncated for summary mode in rss/atom
sub event_summary {
    my $self = $_[0];

    my $url      = $self->url;
    my $readmore = "<b>(<a href=\"$url\">Read more ...</a>)</b>";

    return LJ::Entry->summarize( $self->event_html, $readmore );
}

# class method for truncation
sub summarize {
    my ( $class, $event, $readmore ) = @_;
    return '' unless defined $event;

    # assume the first paragraph is terminated by two <br> or a </p>
    # valid XML tags should be handled, even though it makes an uglier regex
    if ( $event =~ m!(.*?(?:(?:<br\s*/?>(?:</br\s*>)?\s*){2}|</p\s*>))!i ) {

        # everything before the matched tag + the tag itself
        # + a link to read more
        $event = $1 . $readmore;
    }
    return $event;
}

sub comments_manageable_by {
    my ( $self, $remote ) = @_;
    return 0 unless $self->valid;
    return 0 unless $remote;
    my $u = $self->{u};
    return $remote->userid == $self->posterid || $remote->can_manage($u);
}

# instance method: returns bool, if remote user can edit this entry
# use this to determine whether to, e.g., show edit buttons or an edit form
# but don't use this when saving stuff to the database -- those need to pass through the protocol
# does not care about readonly status, just about permissions
sub editable_by {
    my ( $self, $remote ) = @_;
    return 0 unless LJ::isu($remote);
    return 0 unless $self->visible_to($remote);

    # remote is editing their own entry
    return 1 if $self->posterid == $remote->userid;

    # editing an entry that's not your personal journal
    return 1 if $self->journalid != $self->posterid && $remote->can_manage( $self->journal );

    return 0;
}

# instance method:  returns bool, if remote user can view this entry
sub visible_to {
    my ( $self, $remote, $canview ) = @_;
    return 0 unless $self->valid;

    my ( $viewall, $viewsome ) = ( 0, 0 );
    if ( LJ::isu($remote) && $canview ) {
        $viewall  = $remote->has_priv( 'canview', '*' );
        $viewsome = $viewall || $remote->has_priv( 'canview', 'suspended' );
    }

    # can see anything with viewall
    return 1 if $viewall;

    # can't see anything unless the journal is visible
    # unless you have viewsome. then, other restrictions apply
    unless ($viewsome) {
        return 0 if $self->journal->is_inactive;

        # can't see anything by suspended users
        return 0 if $self->poster->is_suspended;

        # can't see suspended entries
        return 0 if $self->is_suspended_for($remote);
    }

    # public is okay
    return 1 if $self->security eq "public";

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid   = int( $self->{u}{userid} );
    my $remoteid = int( $remote->{userid} );

    # owners can always see their own.
    return 1 if $userid == $remoteid;

    # should be 'usemask' or 'private' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless $self->security eq "usemask" || $self->security eq "private";

    return 0 unless $remote->is_individual;

    if ( $self->security eq "private" ) {

        # other people can't read private on personal journals
        return 0 if $self->journal->is_individual;

        # but community administrators can read private entries on communities
        return 1 if $self->journal->is_community && $remote->can_manage( $self->journal );

        # private entry on a community; we're not allowed to see this
        return 0;
    }

    if ( $self->security eq "usemask" ) {

        # check if it's a community and they're a member
        return 1
            if $self->journal->is_community
            && $remote->member_of( $self->journal );

        my $gmask   = $self->journal->trustmask($remote);
        my $allowed = ( int($gmask) & int( $self->{'allowmask'} ) );
        return $allowed ? 1 : 0;    # no need to return matching mask
    }

    return 0;
}

# returns hashref of (kwid => tag) for tags on the entry
sub tag_map {
    my $self = $_[0];
    my $tags = LJ::Tags::get_logtags( $self->{u}, $self->jitemid );
    return {} unless $tags;
    return $tags->{ $self->jitemid } || {};
}

=head2 C<< $entry->admin_post >>

Returns true if this post is an official administrator post.

=cut

sub admin_post {
    my $self = $_[0];

    return 0 unless $self->journal->is_community;
    return 0
        unless $self->poster && $self->poster->can_manage( $self->journal );

    if ( exists $_[1] ) {
        return $_[0]->set_prop( 'admin_post', $_[1] ? 1 : 0 );
    }
    else {
        return $_[0]->prop('admin_post') ? 1 : 0;
    }
}

=head2 C<< $entry->userpic >>

Returns a LJ::Userpic object for this post, or undef.

If called in a list context, returns ( LJ::Userpic object, keyword )

See userpic_kw.

=cut

# FIXME: add a context option for friends page, and perhaps
# respect $remote's userpic viewing preferences (community shows poster
# vs community's picture)
sub userpic {
    my $up  = $_[0]->poster;
    my $kw  = $_[0]->userpic_kw;
    my $pic = LJ::Userpic->new_from_keyword( $up, $kw ) || $up->userpic;

    return wantarray ? ( $pic, $kw ) : $pic;
}

=head2 C<< $entry->userpic_kw >>

Returns the keyword to use for the entry.

If a keyword is specified, it uses that.

=cut

sub userpic_kw {
    my $self = $_[0];

    my $up = $self->poster;

    my $key;

    # try their entry-defined userpic keyword
    if ( $up->userpic_have_mapid ) {
        my $mapid = $self->prop('picture_mapid');

        $key = $up->get_keyword_from_mapid($mapid) if $mapid;
    }
    else {
        $key = $self->prop('picture_keyword');
    }

    return $key;
}

# returns true if the user is allowed to share an entry via Tell a Friend
# $u is the logged-in user
# $item is a hash containing Entry info
sub can_tellafriend {
    my ( $entry, $u ) = @_;

    # this is undefined in preview
    my $seclevel = $entry->security // '';

    return 1 if $seclevel eq 'public';
    return 0 if $seclevel eq 'private';

    # friends only
    return 0 unless $entry->journal->is_person;
    return 0 unless $u && $u->equals( $entry->poster );
    return 1;
}

# defined by the entry poster
sub adult_content {
    my $self = $_[0];

    return $self->prop('adult_content');
}

# defined by a community maintainer
sub adult_content_maintainer {
    my $self = $_[0];

    my $userLevel  = $self->adult_content;
    my $maintLevel = $self->prop('adult_content_maintainer');

    return undef unless $maintLevel;
    return $maintLevel if $userLevel eq $maintLevel;
    return $maintLevel if !$userLevel || $userLevel eq "none";
    return $maintLevel if $userLevel eq "concepts" && $maintLevel eq "explicit";
    return undef;
}

# defined by a community maintainer
sub adult_content_maintainer_reason {
    my $self = $_[0];

    return $self->prop('adult_content_maintainer_reason');
}

# defined by the entry poster
sub adult_content_reason {
    my $self = $_[0];

    return $self->prop('adult_content_reason');
}

# uses both poster- and maintainer-defined props to figure out the adult content level
sub adult_content_calculated {
    my $self = $_[0];

    return $self->adult_content_maintainer if $self->adult_content_maintainer;
    return $self->adult_content;
}

# returns who marked the entry as the 'adult_content_calculated' adult content level
sub adult_content_marker {
    my $self = $_[0];

    return "community" if $self->adult_content_maintainer;
    return "poster"    if $self->adult_content;
    return $self->journal->adult_content_marker;
}

# return whether this entry has comment emails enabled or not
sub comment_email_disabled {
    my $self = $_[0];

    my $entry_no_email = $self->prop('opt_noemail');
    return $entry_no_email if $entry_no_email;

    #my $journal_no_email = $self->
    return 0;
}

# return whether this entry has comments disabled, either by the poster or by the maintainer
sub comments_disabled {
    my $self = $_[0];

    return $self->prop('opt_nocomments') || $self->prop('opt_nocomments_maintainer');
}

# return whether comments were disabled by the entry poster
sub comments_disabled_poster {
    return $_[0]->prop('opt_nocomments');
}

# return whether this post had its comments disabled by a community maintainer (not by the poster, who can override the community moderator)
sub comments_disabled_maintainer {
    my $self = $_[0];

    return $self->prop('opt_nocomments_maintainer') && !$self->comments_disabled_poster;
}

sub should_block_robots {
    my $self = $_[0];

    return 1 if $self->journal->prop('opt_blockrobots');

    return 0 unless LJ::is_enabled('adult_content');

    my $adult_content = $self->adult_content_calculated;

    return 1
        if $adult_content
        && $LJ::CONTENT_FLAGS{$adult_content}
        && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 0;
}

sub syn_link {
    my $self = $_[0];

    return $self->prop('syn_link');
}

# group names to be displayed with this entry
# returns nothing if remote is not the poster of the entry
# returns names as links to the /security/ URLs if the user can use those URLs
# returns names as plaintext otherwise
sub group_names {
    my $self = $_[0];

    my $remote = LJ::get_remote();
    my $poster = $self->poster;
    return "" unless $remote && $poster && $poster->equals($remote);

    return $poster->security_group_display( $self->allowmask );
}

sub statusvis {
    my $self = $_[0];
    my $vis  = $self->prop("statusvis") || '';
    return $vis eq "S" ? "S" : "V";
}

sub is_backdated {
    my $self = $_[0];

    return $self->prop('opt_backdated') ? 1 : 0;
}

sub is_visible {
    my $self = $_[0];

    return $self->statusvis eq "V" ? 1 : 0;
}

sub is_suspended {
    my $self = $_[0];

    return $self->statusvis eq "S" ? 1 : 0;
}

# same as is_suspended, except that it returns 0 if the given user can see the suspended entry
sub is_suspended_for {
    my ( $self, $u ) = @_;

    return 0 unless $self->is_suspended;
    return 1 unless LJ::isu($u);

    # see if $u has access
    return 0 if $u->has_priv( 'canview', 'suspended' );
    return 0 if $u->equals( $self->poster );
    return 1;
}

sub should_show_suspend_msg_to {
    my ( $self, $u ) = @_;

    return $self->is_suspended && !$self->is_suspended_for($u) ? 1 : 0;
}

# some entry props must keep all their history
sub put_logprop_in_history {
    my ( $self, $prop, $old_value, $new_value, $note ) = @_;

    my $p = LJ::get_prop( "log", $prop );
    return undef unless $p;

    my $propid = $p->{id};

    my $u = $self->journal;
    $u->do(
"INSERT INTO logprop_history (journalid, jitemid, propid, change_time, old_value, new_value, note) VALUES (?, ?, ?, unix_timestamp(), ?, ?, ?)",
        undef, $self->journalid, $self->jitemid, $propid, $old_value, $new_value, $note
    );
    return undef if $u->err;
    return 1;
}

package LJ;

use Carp qw(confess);
use LJ::Poll;
use LJ::EmbedModule;
use DW::External::Account;

# <LJFUNC>
# name: LJ::get_posts_raw
# des: Gets raw post data (text and props) efficiently from clusters.
# info: Fetches posts from clusters, trying memcache and slaves first if available.
# returns: hashref with keys 'text', 'prop', or 'replycount', and values being
#          hashrefs with keys "jid:jitemid".  values of that are as follows:
#          text: [ $subject, $body ], props: { ... }, and replycount: scalar
# args: opts?, id
# des-opts: An optional hashref of options:
#            - memcache_only:  Don't fall back on the database.
#            - text_only:  Retrieve only text, no props (used to support old API).
#            - prop_only:  Retrieve only props, no text (used to support old API).
# des-id: An arrayref of [ clusterid, ownerid, itemid ].
# </LJFUNC>
sub get_posts_raw {
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $ret  = {};
    my $sth;

    LJ::load_props('log') unless $opts->{text_only};

    # throughout this function, the concept of an "id"
    # is the key to identify a single post.
    # it is of the form "$jid:$jitemid".

    # build up a list for each cluster of what we want to get,
    # as well as a list of all the keys we want from memcache.
    my %cids;        # cid => 1
    my $needtext;    # text needed:  $cid => $id => 1
    my $needprop;    # props needed: $cid => $id => 1
    my $needrc;      # replycounts needed: $cid => $id => 1
    my @mem_keys;

    # if we're loading entries for a friends page,
    # silently failing to load a cluster is acceptable.
    # but for a single user, we want to die loudly so they don't think
    # we just lost their journal.
    my $single_user;

    # because the memcache keys for logprop don't contain
    # which cluster they're in, we also need a map to get the
    # cid back from the jid so we can insert into the needfoo hashes.
    # the alternative is to not key the needfoo hashes on cluster,
    # but that means we need to grep out each cluster's jids when
    # we do per-cluster queries on the databases.
    my %cidsbyjid;
    foreach my $post (@_) {
        my ( $cid, $jid, $jitemid ) = @{$post};
        my $id = "$jid:$jitemid";
        if ( not defined $single_user ) {
            $single_user = $jid;
        }
        elsif ( $single_user and $jid != $single_user ) {

            # multiple users
            $single_user = 0;
        }
        $cids{$cid}      = 1;
        $cidsbyjid{$jid} = $cid;
        unless ( $opts->{prop_only} ) {
            $needtext->{$cid}{$id} = 1;
            push @mem_keys, [ $jid, "logtext:$cid:$id" ];
        }
        unless ( $opts->{text_only} ) {
            $needprop->{$cid}{$id} = 1;
            push @mem_keys, [ $jid, "logprop:$id" ];
            $needrc->{$cid}{$id} = 1;
            push @mem_keys, [ $jid, "rp:$id" ];
        }
    }

    # first, check memcache.
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
    while ( my ( $k, $v ) = each %$mem ) {
        next unless defined $v;
        next unless $k =~ /(\w+):(?:\d+:)?(\d+):(\d+)/;
        my ( $type, $jid, $jitemid ) = ( $1, $2, $3 );
        my $cid = $cidsbyjid{$jid};
        my $id  = "$jid:$jitemid";
        if ( $type eq "logtext" ) {
            delete $needtext->{$cid}{$id};
            $ret->{text}{$id} = $v;
        }
        elsif ( $type eq "logprop" && ref $v eq "HASH" ) {
            delete $needprop->{$cid}{$id};
            $ret->{prop}{$id} = $v;
        }
        elsif ( $type eq "rp" ) {
            delete $needrc->{$cid}{$id};
            $ret->{replycount}{$id} = int($v);    # remove possible spaces
        }
    }

    # we may be done already.
    return $ret if $opts->{memcache_only};
    return $ret
        unless values %$needtext
        or values %$needprop
        or values %$needrc;

    # otherwise, hit the database.
    foreach my $cid ( keys %cids ) {

        # for each cluster, get the text/props we need from it.
        my $cneedtext = $needtext->{$cid} || {};
        my $cneedprop = $needprop->{$cid} || {};
        my $cneedrc   = $needrc->{$cid}   || {};

        next unless %$cneedtext or %$cneedprop or %$cneedrc;

        my $make_in = sub {
            my @in;
            foreach my $id (@_) {
                my ( $jid, $jitemid ) = map { $_ + 0 } split( /:/, $id );
                push @in, "(journalid=$jid AND jitemid=$jitemid)";
            }
            return join( " OR ", @in );
        };

        # now load from each cluster.
        my $fetchtext = sub {
            my $db = $_[0];
            return unless %$cneedtext;
            my $in = $make_in->( keys %$cneedtext );
            $sth = $db->prepare(
                "SELECT journalid, jitemid, subject, event " . "FROM logtext2 WHERE $in" );
            $sth->execute;
            while ( my ( $jid, $jitemid, $subject, $event ) = $sth->fetchrow_array ) {
                LJ::text_uncompress( \$event );
                my $id  = "$jid:$jitemid";
                my $val = [ $subject, $event ];
                $ret->{text}{$id} = $val;
                LJ::MemCache::add( [ $jid, "logtext:$cid:$id" ], $val );
                delete $cneedtext->{$id};
            }
        };

        my $fetchprop = sub {
            my $db = $_[0];
            return unless %$cneedprop;
            my $in = $make_in->( keys %$cneedprop );
            $sth = $db->prepare(
                "SELECT journalid, jitemid, propid, value " . "FROM logprop2 WHERE $in" );
            $sth->execute;
            my %gotid;
            while ( my ( $jid, $jitemid, $propid, $value ) = $sth->fetchrow_array ) {
                my $id       = "$jid:$jitemid";
                my $propname = $LJ::CACHE_PROPID{'log'}->{$propid}{name};
                $ret->{prop}{$id}{$propname} = $value;
                $gotid{$id} = 1;
            }
            foreach my $id ( keys %gotid ) {
                my ( $jid, $jitemid ) = map { $_ + 0 } split( /:/, $id );
                LJ::MemCache::add( [ $jid, "logprop:$id" ], $ret->{prop}{$id} );
                delete $cneedprop->{$id};
            }
        };

        my $fetchrc = sub {
            my $db = $_[0];
            return unless %$cneedrc;
            my $in = $make_in->( keys %$cneedrc );
            $sth = $db->prepare("SELECT journalid, jitemid, replycount FROM log2 WHERE $in");
            $sth->execute;
            while ( my ( $jid, $jitemid, $rc ) = $sth->fetchrow_array ) {
                my $id = "$jid:$jitemid";
                $ret->{replycount}{$id} = $rc;
                LJ::MemCache::add( [ $jid, "rp:$id" ], $rc );
                delete $cneedrc->{$id};
            }
        };

        my $dberr = sub {
            die "Couldn't connect to database" if $single_user;
            next;
        };

        # run the fetch functions on the proper databases, with fallbacks if necessary.
        my ( $dbcm, $dbcr );
        if ( @LJ::MEMCACHE_SERVERS or $opts->{use_master} ) {
            $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
            $fetchtext->($dbcm) if %$cneedtext;
            $fetchprop->($dbcm) if %$cneedprop;
            $fetchrc->($dbcm)   if %$cneedrc;
        }
        else {
            $dbcr ||= LJ::get_cluster_reader($cid);
            if ($dbcr) {
                $fetchtext->($dbcr) if %$cneedtext;
                $fetchprop->($dbcr) if %$cneedprop;
                $fetchrc->($dbcr)   if %$cneedrc;
            }

            # if we still need some data, switch to the master.
            if ( %$cneedtext or %$cneedprop ) {
                $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
                $fetchtext->($dbcm);
                $fetchprop->($dbcm);
                $fetchrc->($dbcm);
            }
        }

        # and finally, if there were no errors,
        # insert into memcache the absence of props
        # for all posts that didn't have any props.
        foreach my $id ( keys %$cneedprop ) {
            my ( $jid, $jitemid ) = map { $_ + 0 } split( /:/, $id );
            LJ::MemCache::set( [ $jid, "logprop:$id" ], {} );
        }
    }
    return $ret;
}

sub get_posts {
    my $opts     = ref $_[0] eq "HASH" ? shift : {};
    my $rawposts = get_posts_raw( $opts, @_ );

    # fix up posts as needed for display, following directions given in opts.

    # XXX this function is incomplete.  it should also HTML clean, etc.
    # XXX we need to load users when we have unknown8bit data, but that
    # XXX means we have to load users.

    while ( my ( $id, $rp ) = each %$rawposts ) {
        if ( $rp->{props}{unknown8bit} ) {

            #LJ::item_toutf8($u, \$rp->{text}[0], \$rp->{text}[1], $rp->{props});
        }
    }

    return $rawposts;
}

#
# returns a row from log2, trying memcache
# accepts $u + $jitemid
# returns hash with: posterid, eventtime, logtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_row {
    my ( $u, $jitemid ) = @_;
    my $jid = $u->{'userid'};

    my $memkey = [ $jid, "log2:$jid:$jitemid" ];
    my ( $row, $item );

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{ 'posterid', 'eventtime', 'logtime', 'allowmask', 'ditemid' } =
            unpack( $LJ::LOGMEMCFMT, $row );
        $item->{'security'} = (
            $item->{'allowmask'} == 0
            ? 'private'
            : ( $item->{'allowmask'} == $LJ::PUBLICBIT ? 'public' : 'usemask' )
        );
        $item->{'journalid'} = $jid;
        @$item{ 'jitemid', 'anum' } = ( $item->{'ditemid'} >> 8, $item->{'ditemid'} % 256 );
        $item->{'eventtime'} = LJ::mysql_time( $item->{'eventtime'}, 1 );
        $item->{'logtime'}   = LJ::mysql_time( $item->{'logtime'},   1 );

        return $item;
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sql = "SELECT posterid, eventtime, logtime, security, allowmask, "
        . "anum FROM log2 WHERE journalid=? AND jitemid=?";

    $item = $db->selectrow_hashref( $sql, undef, $jid, $jitemid );
    return undef unless $item;
    $item->{'journalid'} = $jid;
    $item->{'jitemid'}   = $jitemid;
    $item->{'ditemid'}   = $jitemid * 256 + $item->{'anum'};

    my ( $sec, $eventtime, $logtime );
    $sec       = $item->{'allowmask'};
    $sec       = 0 if $item->{'security'} eq 'private';
    $sec       = $LJ::PUBLICBIT if $item->{'security'} eq 'public';
    $eventtime = LJ::mysqldate_to_time( $item->{'eventtime'}, 1 );
    $logtime   = LJ::mysqldate_to_time( $item->{'logtime'}, 1 );

# note: this cannot distinguish between security == private and security == usemask with allowmask == 0 (no groups)
# both should have the same display behavior, but we don't store the security value in memcache
    $row = pack( $LJ::LOGMEMCFMT, $item->{'posterid'}, $eventtime, $logtime, $sec,
        $item->{'ditemid'} );
    LJ::MemCache::set( $memkey, $row );

    return $item;
}

# get 2 weeks worth of recent items, in rlogtime order,
# using memcache
# accepts $u or ($jid, $clusterid) + $notafter - max value for rlogtime
# $update is the timeupdate for this user, as far as the caller knows,
# in UNIX time.
# returns hash keyed by $jitemid, fields:
# posterid, eventtime, rlogtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_recent_log {
    my ( $u, $cid, $update, $notafter, $events_date ) = @_;
    my $jid = LJ::want_userid($u);
    $cid ||= $u->{'clusterid'} if ref $u;

    my $DATAVER = "4";    # 1 char

    my $use_cache = 1;

    # timestamp
    $events_date = ( !defined $events_date || $events_date eq "" ) ? 0 : int $events_date;
    $use_cache = 0 if $events_date;    # do not use memcache for dayly friends log

    my $memkey  = [ $jid, "log2lt:$jid" ];
    my $lockkey = $memkey->[1];
    my ( $rows, $ret );

    $rows = LJ::MemCache::get($memkey) if $use_cache;
    $ret  = [];

    my $construct_singleton = sub {
        foreach my $row (@$ret) {
            $row->{journalid} = $jid;

            # FIX:
            # logtime param should be datetime, not unixtimestamp.
            #
            $row->{logtime} = LJ::mysql_time( $LJ::EndOfTime - $row->{rlogtime}, 1 );

            # construct singleton for later
            LJ::Entry->new_from_row(%$row);
        }

        return $ret;
    };

    my $rows_decode = sub {
        return 0
            unless $rows && substr( $rows, 0, 1 ) eq $DATAVER;
        my $tu = unpack( "N", substr( $rows, 1, 4 ) );

        # if update time we got from upstream is newer than recorded
        # here, this data is unreliable
        return 0 if $update > $tu;

        my $n = ( length($rows) - 5 ) / 24;
        for ( my $i = 0 ; $i < $n ; $i++ ) {
            my ( $posterid, $eventtime, $rlogtime, $allowmask, $ditemid ) =
                unpack( $LJ::LOGMEMCFMT, substr( $rows, $i * 24 + 5, 24 ) );
            next if $notafter and $rlogtime > $notafter;
            $eventtime = LJ::mysql_time( $eventtime, 1 );
            my $security =
                $allowmask == 0
                ? 'private'
                : ( $allowmask == $LJ::PUBLICBIT ? 'public' : 'usemask' );
            my ( $jitemid, $anum ) = ( $ditemid >> 8, $ditemid % 256 );
            my $item = {};
            @$item{
                'posterid', 'eventtime', 'rlogtime', 'allowmask', 'ditemid',
                'security', 'journalid', 'jitemid',  'anum'
                }
                = (
                $posterid, $eventtime, $rlogtime, $allowmask, $ditemid,
                $security, $jid,       $jitemid,  $anum
                );
            $item->{'ownerid'} = $jid;
            $item->{'itemid'}  = $jitemid;
            push @$ret, $item;
        }
        return 1;
    };

    return $construct_singleton->()
        if $rows_decode->();
    $rows = "";

    my $db = LJ::get_cluster_def_reader($cid);

    # if we use slave or didn't get some data, don't store in memcache
    my $dont_store = 0;
    unless ($db) {
        $db         = LJ::get_cluster_reader($cid);
        $dont_store = 1;
        return undef unless $db;
    }

    #
    my $lock = $db->selectrow_array( "SELECT GET_LOCK(?,10)", undef, $lockkey );
    return undef unless $lock;

    if ($use_cache) {

        # try to get cached data in exclusive context
        $rows = LJ::MemCache::get($memkey);
        if ( $rows_decode->() ) {
            $db->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );
            return $construct_singleton->();
        }
    }

    # ok. fetch data directly from DB.
    $rows = "";

    # get reliable update time from the db
    # TODO: check userprop first
    my $tu;
    my $dbh = LJ::get_db_writer();
    if ($dbh) {
        $tu = $dbh->selectrow_array(
            "SELECT UNIX_TIMESTAMP(timeupdate) " . "FROM userusage WHERE userid=?",
            undef, $jid );

        # if no mistake, treat absence of row as tu==0 (new user)
        $tu = 0 unless $tu || $dbh->err;

        LJ::MemCache::set( [ $jid, "tu:$jid" ], pack( "N", $tu ), 30 * 60 )
            if defined $tu;

        # TODO: update userprop if necessary
    }

    # if we didn't get tu, don't bother to memcache
    $dont_store = 1 unless defined $tu;

    # get reliable log2lt data from the db
    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600 * 24 * 14;    # 2 weeks default
    my $sql     = "
        SELECT
            jitemid, posterid, eventtime, rlogtime,
            security, allowmask, anum, replycount
         FROM log2
         USE INDEX (rlogtime)
         WHERE
                journalid=?
         " . (
        $events_date
        ? "AND rlogtime <= ($LJ::EndOfTime - $events_date)
               AND rlogtime >= ($LJ::EndOfTime - " . ( $events_date + 24 * 3600 ) . ")"
        : "AND rlogtime <= ($LJ::EndOfTime - UNIX_TIMESTAMP()) + $max_age"
    );

    my $sth = $db->prepare($sql);
    $sth->execute($jid);
    my @row = ();
    push @row, $_ while $_ = $sth->fetchrow_hashref;
    @row = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @row;
    my $itemnum = 0;

    foreach my $item (@row) {
        $item->{'ownerid'} = $item->{'journalid'} = $jid;
        $item->{'itemid'}  = $item->{'jitemid'};
        push @$ret, $item;

        my ( $sec, $ditemid, $eventtime, $logtime );
        $sec       = $item->{'allowmask'};
        $sec       = 0 if $item->{'security'} eq 'private';
        $sec       = $LJ::PUBLICBIT if $item->{'security'} eq 'public';
        $ditemid   = $item->{'jitemid'} * 256 + $item->{'anum'};
        $eventtime = LJ::mysqldate_to_time( $item->{'eventtime'}, 1 );

        $rows .= pack( $LJ::LOGMEMCFMT,
            $item->{'posterid'}, $eventtime, $item->{'rlogtime'}, $sec, $ditemid );

        if ( $use_cache && $itemnum++ < 50 ) {
            LJ::MemCache::add( [ $jid, "rp:$jid:$item->{'jitemid'}" ], $item->{'replycount'} );
        }
    }

    $rows = $DATAVER . pack( "N", $tu ) . $rows;

    # store journal log in cache
    LJ::MemCache::set( $memkey, $rows )
        if $use_cache and not $dont_store;

    $db->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );
    return $construct_singleton->();
}

# get recent entries for a user
sub get_log2_recent_user {
    my $opts = $_[0];
    my $ret  = [];

    my $log = LJ::get_log2_recent_log(
        $opts->{'userid'},   $opts->{'clusterid'}, $opts->{'update'},
        $opts->{'notafter'}, $opts->{events_date}
    );

    my $left     = $opts->{'itemshow'};
    my $notafter = $opts->{'notafter'};
    my $remote   = $opts->{'remote'};
    my $filter   = $opts->{filter};

    my %mask_for_remote = ();    # jid => mask for $remote
    foreach my $item (@$log) {
        last unless $left;
        last if $notafter and $item->{'rlogtime'} > $notafter;
        next unless $remote || $item->{'security'} eq 'public';

        next
            if defined( $opts->{security} )
            && !(
            (
                   $opts->{security} eq 'access'
                && $item->{security} eq 'usemask'
                && $item->{allowmask} + 0 != 0
            )
            || (   $opts->{security} eq 'private'
                && $item->{security} eq 'usemask'
                && $item->{allowmask} + 0 == 0 )
            || ( $opts->{security} eq $item->{security} )
            );

        if ( $item->{security} eq 'private' and $item->{journalid} != $remote->{userid} ) {
            my $ju = LJ::load_userid( $item->{journalid} );
            next unless $remote->can_manage($ju);
        }

        if ( $item->{'security'} eq 'usemask' ) {
            next unless $remote->is_individual;
            my $permit = ( $item->{journalid} == $remote->userid );
            unless ($permit) {

              # $mask for $item{journalid} should always be the same since get_log2_recent_log
              # selects based on the $u we pass in; $u->id == $item->{journalid} from what I can see
              # -- we'll store in a per-journalid hash to be safe, but still avoid
              #    extra memcache calls
                my $mask = $mask_for_remote{ $item->{journalid} };
                unless ( defined $mask ) {
                    my $ju = LJ::load_userid( $item->{journalid} );
                    if ( $ju->is_community ) {

                        # communities don't have masks towards users, so fake it
                        $mask = $remote->member_of($ju) ? 1 : 0;
                    }
                    else {
                        $mask = $ju->trustmask($remote);
                    }
                    $mask_for_remote{ $item->{journalid} } = $mask;
                }
                $permit = $item->{'allowmask'} + 0 & $mask + 0;
            }
            next unless $permit;
        }

        # date conversion
        if ( !$opts->{'dateformat'} || $opts->{'dateformat'} eq "S2" ) {
            $item->{'alldatepart'} = LJ::alldatepart_s2( $item->{'eventtime'} );

            # conversion to get the system time of this entry
            my $logtime = LJ::mysql_time( $LJ::EndOfTime - $item->{rlogtime}, 1 );
            $item->{'system_alldatepart'} = LJ::alldatepart_s2($logtime);
        }
        else {
            confess "We removed S1 support, sorry.";
        }

        # now see if this item matches the filter
        next if $filter && !$filter->show_entry($item);

        push @$ret, $item;
    }

    return @$ret;
}

##
## see subs 'get_itemid_after2' and 'get_itemid_before2'
##
sub get_itemid_near2 {
    my ( $u, $jitemid, $tagnav, $after_before ) = @_;

    $jitemid += 0;

    my ( $order, $cmp1, $cmp3, $cmp4 );
    if ( $after_before eq "after" ) {
        ( $order, $cmp1, $cmp3, $cmp4 ) =
            ( "DESC", "<=", sub { $a->[0] <=> $b->[0] }, sub { $b->[2] <=> $a->[2] } );
    }
    elsif ( $after_before eq "before" ) {
        ( $order, $cmp1, $cmp3, $cmp4 ) =
            ( "ASC", ">=", sub { $b->[0] <=> $a->[0] }, sub { $a->[2] <=> $b->[2] } );
    }
    else {
        return 0;
    }

    my $dbr   = LJ::get_cluster_reader($u) or return 0;
    my $jid   = $u->{'userid'} + 0;
    my $field = $u->is_person ? "revttime" : "rlogtime";

    my $stime = $dbr->selectrow_array(
        "SELECT $field FROM log2 WHERE " . "journalid=$jid AND jitemid=$jitemid" );
    return 0 unless $stime;

    my $secwhere = "AND security='public'";
    my $remote   = LJ::get_remote();

    if ($remote) {
        if ( $remote->equals($u) || ( $u->is_community && $remote->can_manage($u) ) ) {
            $secwhere = "";    # see everything
        }
        elsif ( $remote->is_individual ) {
            my $gmask = $u->is_community ? $remote->member_of($u) : $u->trustmask($remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    ##
    ## We need a next/prev record in journal before/after a given time
    ## Since several records may have the same time (time is rounded to 1 minute),
    ## we're ordering them by jitemid. So, the SQL we need is
    ##      SELECT * FROM log2
    ##      WHERE journalid=? AND rlogtime>? AND jitmemid<?
    ##      ORDER BY rlogtime, jitemid DESC
    ##      LIMIT 1
    ## Alas, MySQL tries to do filesort for the query.
    ## So, we sort by rlogtime only and fetch all (2, 10, 50) records
    ## with the same rlogtime (we skip records if rlogtime is different from the first one).
    ## If rlogtime of all fetched records is the same, increase the LIMIT and retry.
    ## Then we sort them in Perl by jitemid and takes just one.
    ##
    my $result_ref;
    foreach my $limit ( 2, 10, 50, 100 ) {
        if ($tagnav) {
            $result_ref = $dbr->selectall_arrayref(
"SELECT log2.jitemid, anum, $field FROM log2 use index (rlogtime,revttime), logtagsrecent "
                    . "WHERE log2.journalid=? AND $field $cmp1 ? AND log2.jitemid <> ? "
                    . "AND log2.journalid=logtagsrecent.journalid AND log2.jitemid=logtagsrecent.jitemid AND logtagsrecent.kwid=$tagnav "
                    . $secwhere . " "
                    . "ORDER BY $field $order LIMIT $limit",
                undef, $jid, $stime, $jitemid
            );
        }
        else {
            $result_ref = $dbr->selectall_arrayref(
                "SELECT jitemid, anum, $field FROM log2 use index (rlogtime,revttime) "
                    . "WHERE journalid=? AND $field $cmp1 ? AND jitemid <> ? "
                    . $secwhere . " "
                    . "ORDER BY $field $order LIMIT $limit",
                undef, $jid, $stime, $jitemid
            );
        }

        my %hash_times = ();
        map { $hash_times{ $_->[2] } = 1 } @$result_ref;

        # If we has one the only 'time' in $limit fetched rows,
        # may be $limit cuts off our record. Increase the limit and repeat.
        if ( ( ( scalar keys %hash_times ) > 1 ) || ( scalar @$result_ref ) < $limit ) {
            my @result;

            # Remove results with the same time but the jitemid is too high or low
            if ( $after_before eq "after" ) {
                @result = grep { $_->[2] != $stime || $_->[0] > $jitemid } @$result_ref;
            }
            elsif ( $after_before eq "before" ) {
                @result = grep { $_->[2] != $stime || $_->[0] < $jitemid } @$result_ref;
            }

            # Sort result by jitemid and get our id from a top.
            @result = sort $cmp3 @result;

            # Sort result by revttime
            @result = sort $cmp4 @result;

            my ( $id, $anum ) = ( $result[0]->[0], $result[0]->[1] );
            return 0 unless $id;
            return wantarray() ? ( $id, $anum ) : ( $id * 256 + $anum );
        }
    }
    return 0;
}

##
## Returns ID (a pair <jitemid, anum> in list context, ditmeid in scalar context)
## of a journal record that follows/preceeds the given record.
## Input: $u, $jitemid
##
sub get_itemid_after2  { return get_itemid_near2( @_, "after" ); }
sub get_itemid_before2 { return get_itemid_near2( @_, "before" ); }

sub set_logprop {
    my ( $u, $jitemid, $hashref, $logprops ) = @_;    # hashref to set, hashref of what was done

    $jitemid += 0;
    my $uid      = $u->{'userid'} + 0;
    my $kill_mem = 0;
    my $del_ids;
    my $ins_values;
    while ( my ( $k, $v ) = each %{ $hashref || {} } ) {
        my $prop = LJ::get_prop( "log", $k );
        next unless $prop;
        $kill_mem = 1 unless $prop eq "commentalter";
        if ($v) {
            $ins_values .= "," if $ins_values;
            $ins_values .= "($uid, $jitemid, $prop->{'id'}, " . $u->quote($v) . ")";
            $logprops->{$k} = $v;
        }
        else {
            $del_ids .= "," if $del_ids;
            $del_ids .= $prop->{'id'};
        }
    }

    $u->do( "REPLACE INTO logprop2 (journalid, jitemid, propid, value) " . "VALUES $ins_values" )
        if $ins_values;
    $u->do( "DELETE FROM logprop2 WHERE journalid=? AND jitemid=? " . "AND propid IN ($del_ids)",
        undef, $u->userid, $jitemid )
        if $del_ids;

    LJ::MemCache::delete( [ $uid, "logprop:$uid:$jitemid" ] ) if $kill_mem;
}

# <LJFUNC>
# name: LJ::load_log_props2
# class:
# des:
# info:
# args: db?, uuserid, listref, hashref
# des-:
# returns:
# </LJFUNC>
sub load_log_props2 {
    my $db = LJ::DB::isdb( $_[0] ) ? shift @_ : undef;

    my ( $uuserid, $listref, $hashref ) = @_;
    my $userid = want_userid($uuserid);
    return unless ref $hashref eq "HASH";

    my %needprops;
    my %needrc;
    my %rc;
    my @memkeys;
    foreach (@$listref) {
        my $id = $_ + 0;
        $needprops{$id} = 1;
        $needrc{$id}    = 1;
        push @memkeys, [ $userid, "logprop:$userid:$id" ];
        push @memkeys, [ $userid, "rp:$userid:$id" ];
    }
    return unless %needprops || %needrc;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};
    while ( my ( $k, $v ) = each %$mem ) {
        next unless $k =~ /(\w+):(\d+):(\d+)/;
        if ( $1 eq 'logprop' ) {
            next unless ref $v eq "HASH";
            delete $needprops{$3};
            $hashref->{$3} = $v;
        }
        if ( $1 eq 'rp' ) {
            delete $needrc{$3};
            $rc{$3} = int($v);    # change possible "0   " (true) to "0" (false)
        }
    }

    foreach ( keys %rc ) {
        $hashref->{$_}{'replycount'} = $rc{$_};
    }

    return unless %needprops || %needrc;

    unless ($db) {
        my $u = LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
        return unless $db;
    }

    if (%needprops) {
        LJ::load_props("log");
        my $in  = join( ",", keys %needprops );
        my $sth = $db->prepare( "SELECT jitemid, propid, value FROM logprop2 "
                . "WHERE journalid=? AND jitemid IN ($in)" );
        $sth->execute($userid);
        while ( my ( $jitemid, $propid, $value ) = $sth->fetchrow_array ) {
            $hashref->{$jitemid}->{ $LJ::CACHE_PROPID{'log'}->{$propid}->{'name'} } = $value;
        }
        foreach my $id ( keys %needprops ) {
            LJ::MemCache::set( [ $userid, "logprop:$userid:$id" ], $hashref->{$id} || {} );
        }
    }

    if (%needrc) {
        my $in  = join( ",", keys %needrc );
        my $sth = $db->prepare(
            "SELECT jitemid, replycount FROM log2 WHERE journalid=? AND jitemid IN ($in)");
        $sth->execute($userid);
        while ( my ( $jitemid, $rc ) = $sth->fetchrow_array ) {
            $hashref->{$jitemid}->{'replycount'} = $rc;
            LJ::MemCache::add( [ $userid, "rp:$userid:$jitemid" ], $rc );
        }
    }

}

# <LJFUNC>
# name: LJ::load_talk_props2
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_talk_props2 {
    my $db = LJ::DB::isdb( $_[0] ) ? shift @_ : undef;
    my ( $uuserid, $listref, $hashref ) = @_;

    my $userid = want_userid($uuserid);
    my $u      = ref $uuserid ? $uuserid : undef;

    $hashref = {} unless ref $hashref eq "HASH";

    my %need;
    my @memkeys;
    foreach (@$listref) {
        my $id = $_ + 0;
        $need{$id} = 1;
        push @memkeys, [ $userid, "talkprop:$userid:$id" ];
    }
    return $hashref unless %need;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    # allow hooks to count memcaches in this function for testing
    if ($LJ::_T_GET_TALK_PROPS2_MEMCACHE) {
        $LJ::_T_GET_TALK_PROPS2_MEMCACHE->();
    }

    while ( my ( $k, $v ) = each %$mem ) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        delete $need{$2};
        $hashref->{$2}->{ $_[0] } = $_[1] while @_ = each %$v;
    }
    return $hashref unless %need;

    if ( !$db || @LJ::MEMCACHE_SERVERS ) {
        $u ||= LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
        return $hashref unless $db;
    }

    LJ::load_props("talk");
    my $in  = join( ',', keys %need );
    my $sth = $db->prepare( "SELECT jtalkid, tpropid, value FROM talkprop2 "
            . "WHERE journalid=? AND jtalkid IN ($in)" );
    $sth->execute($userid);
    while ( my ( $jtalkid, $propid, $value ) = $sth->fetchrow_array ) {
        my $p = $LJ::CACHE_PROPID{'talk'}->{$propid};
        next unless $p;
        $hashref->{$jtalkid}->{ $p->{'name'} } = $value;
    }
    foreach my $id ( keys %need ) {
        LJ::MemCache::set( [ $userid, "talkprop:$userid:$id" ], $hashref->{$id} || {} );
    }
    return $hashref;
}

# <LJFUNC>
# name: LJ::delete_all_comments
# des: deletes all comments from a post, permanently, for when a post is deleted
# info: The tables [dbtable[talk2]], [dbtable[talkprop2]], [dbtable[talktext2]],
#       are deleted from, immediately.
# args: u, nodetype, nodeid
# des-nodetype: The thread nodetype (probably 'L' for log items).
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#             from the [dbtable[log2]] row).
# returns: boolean; success value
# </LJFUNC>
sub delete_all_comments {
    my ( $u, $nodetype, $nodeid ) = @_;

    my $dbcm = LJ::get_cluster_master($u);
    return 0 unless $dbcm && $u->writer;

    # delete comments
    my ( $t, $loop ) = ( undef, 1 );
    my $chunk_size = 200;
    while (
        $loop
        && (
            $t = $dbcm->selectcol_arrayref(
                "SELECT jtalkid FROM talk2 WHERE "
                    . "nodetype=? AND journalid=? "
                    . "AND nodeid=? LIMIT $chunk_size",
                undef,
                $nodetype,
                $u->userid,
                $nodeid
            )
        )
        && $t
        && @$t
        )
    {
        my $in = join( ',', map { $_ + 0 } @$t );
        return 1 unless $in;
        foreach my $table (qw(talkprop2 talktext2 talk2)) {
            $u->do( "DELETE FROM $table WHERE journalid=? AND jtalkid IN ($in)",
                undef, $u->userid );
        }

        my $ct = scalar @$t;
        DW::Stats::increment( 'dw.action.comment.delete', $ct,
            [ "journal_type:" . $u->journaltype_readable, 'method:delete_all_comments' ] );

        # decrement memcache
        LJ::MemCache::decr( [ $u->userid, "talk2ct:" . $u->userid ], $ct );
        $loop = 0 unless $ct == $chunk_size;
    }
    return 1;

}

# <LJFUNC>
# name: LJ::delete_comments
# des: deletes comments, but not the relational information, so threading doesn't break
# info: The tables [dbtable[talkprop2]] and [dbtable[talktext2]] are deleted from.  [dbtable[talk2]]
#       just has its state column modified, to 'D'.
# args: u, nodetype, nodeid, talkids
# des-nodetype: The thread nodetype (probably 'L' for log items)
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#              from the [dbtable[log2]] row).
# des-talkids: List array of talkids to delete.
# returns: scalar integer; number of items deleted.
# </LJFUNC>
sub delete_comments {
    my ( $u, $nodetype, $nodeid, @talkids ) = @_;

    return 0 unless $u->writer;

    my $jid = $u->id + 0;
    my $in  = join ',', map { $_ + 0 } @talkids;

    # invalidate talk2row memcache
    LJ::Talk::invalidate_talk2row_memcache( $jid, @talkids );

    return 1 unless $in;
    my $where = "WHERE journalid=$jid AND jtalkid IN ($in)";

    my $num = $u->talk2_do( $nodetype, $nodeid, undef, "UPDATE talk2 SET state='D' $where" );
    return 0 unless $num;
    $num = 0 if $num == -1;

    if ( $num > 0 ) {
        DW::Stats::increment( 'dw.action.comment.delete', $num,
            [ "journal_type:" . $u->journaltype_readable, 'method:delete_comments' ] );

        $u->do("UPDATE talktext2 SET subject=NULL, body=NULL $where");
        $u->do("DELETE FROM talkprop2 $where");
    }

    foreach my $talkid (@talkids) {
        LJ::Hooks::run_hooks( 'delete_comment', $jid, $nodeid, $talkid );    # jitemid, jtalkid
    }

    $u->memc_delete('activeentries');
    LJ::MemCache::delete( [ $jid, "screenedcount:$jid:$nodeid" ] );

    return $num;
}

# <LJFUNC>
# name: LJ::delete_entry
# des: Deletes a user's journal entry
# args: uuserid, jitemid, quick?, anum?
# des-uuserid: Journal itemid or $u object of journal to delete entry from
# des-jitemid: Journal itemid of item to delete.
# des-quick: Optional boolean.  If set, only [dbtable[log2]] table
#            is deleted from and the rest of the content is deleted
#            later via TheSchwartz.
# des-anum: The log item's anum, which'll be needed to delete lazily
#           some data in tables which includes the anum, but the
#           log row will already be gone so we'll need to store it for later.
# returns: boolean; 1 on success, 0 on failure.
# </LJFUNC>
sub delete_entry {
    my ( $uuserid, $jitemid, $quick, $anum ) = @_;
    my $jid = LJ::want_userid($uuserid);
    my $u   = ref $uuserid ? $uuserid : LJ::load_userid($jid);
    $jitemid += 0;

    my $and;
    if ( defined $anum ) { $and = "AND anum=" . ( $anum + 0 ); }

    # delete tags
    LJ::Tags::delete_logtags( $u, $jitemid );

    my $dc =
        $u->log2_do( undef, "DELETE FROM log2 WHERE journalid=$jid AND jitemid=$jitemid $and" );
    LJ::MemCache::delete( [ $jid, "log2:$jid:$jitemid" ] );
    LJ::MemCache::delete( [ $jid, "activeentries:$jid" ] );
    LJ::MemCache::decr(   [ $jid, "log2ct:$jid" ] ) if $dc > 0;
    LJ::memcache_kill( $jid, "dayct2" );
    LJ::Hooks::run_hooks( "deletepost", $jid, $jitemid, $anum );

    # if this is running the second time (started by the cmd buffer),
    # the log2 row will already be gone and we shouldn't check for it.
    my $sclient = $quick ? LJ::theschwartz() : undef;
    if ( $quick && $sclient ) {
        return 1 if $dc < 1;    # already deleted?
        return 1
            if $sclient->insert(
            "LJ::Worker::DeleteEntry",
            {
                uid     => $jid,
                jitemid => $jitemid,
                anum    => $anum,
            }
            );
        return 0;
    }

    DW::Stats::increment( 'dw.action.entry.delete', 1,
        [ "journal_type:" . $u->journaltype_readable ] );

    # delete from clusters
    foreach my $t (qw(logtext2 logprop2 logsec2 logslugs)) {
        $u->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$jitemid");
    }
    $u->dudata_set( 'L', $jitemid, 0 );

    # delete all comments
    LJ::delete_all_comments( $u, 'L', $jitemid );

    # fired to delete the post from the Sphinx search database
    if ( @LJ::SPHINX_SEARCHD && ( my $sclient = LJ::theschwartz() ) ) {
        $sclient->insert_jobs(
            TheSchwartz::Job->new_from_array(
                'DW::Worker::Sphinx::Copier',
                { userid => $u->id, jitemid => $jitemid, source => "entrydel" }
            )
        );
    }

    return 1;
}

# <LJFUNC>
# name: LJ::mark_entry_as_spam
# class: web
# des: Copies an entry in a community into the global [dbtable[spamreports]] table.
# args: journalu_uid, jitemid
# des-journalu_uid: User object of journal (community) entry was posted in, or the userid of it.
# des-jitemid: ID of this entry.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub mark_entry_as_spam {
    my ( $journalu, $jitemid ) = @_;
    $journalu = LJ::want_user($journalu);
    $jitemid += 0;
    return 0 unless $journalu && $jitemid;
    return 0 if LJ::sysban_check( 'spamreport', $journalu->user );

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh  = LJ::get_db_writer();
    return 0 unless $dbcr && $dbh;

    my $item = LJ::get_log2_row( $journalu, $jitemid );
    return 0 unless $item;

    # step 1: get info we need
    my $logtext = LJ::get_logtext2( $journalu, $jitemid );
    my ( $subject, $body, $posterid ) =
        ( $logtext->{$jitemid}[0], $logtext->{$jitemid}[1], $item->{posterid} );
    return 0 unless $body;

    # step 2: insert into spamreports
    $dbh->do(
'INSERT INTO spamreports (reporttime, posttime, journalid, posterid, subject, body, report_type) '
            . 'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, \'entry\')',
        undef, $item->{logtime}, $journalu->{userid}, $posterid, $subject, $body
    );

    return 0 if $dbh->err;
    return 1;
}

# Same as previous, but mark as spam moderated event selected by modid.
sub reject_entry_as_spam {
    my ( $journalu, $modid ) = @_;
    $journalu = LJ::want_user($journalu);
    $modid += 0;
    return 0 unless $journalu && $modid;
    return 0 if LJ::sysban_check( 'spamreport', $journalu->user );

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh  = LJ::get_db_writer();
    return 0 unless $dbcr && $dbh;

    # step 1: get info we need
    my ( $posterid, $logtime ) = $dbcr->selectrow_array(
        "SELECT posterid, logtime FROM modlog WHERE journalid=? AND modid=?",
        undef, $journalu->userid, $modid );

    my $frozen =
        $dbcr->selectrow_array( "SELECT request_stor FROM modblob WHERE journalid=? AND modid=?",
        undef, $journalu->userid, $modid );

    use Storable;
    my $req = $frozen ? Storable::thaw($frozen) : undef;

    my ( $subject, $body ) = ( $req->{subject}, $req->{event} );
    return 0 unless $body;

    # step 2: insert into spamreports
    $dbh->do(
'INSERT INTO spamreports (reporttime, posttime, journalid, posterid, subject, body, report_type) '
            . 'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, \'entry\')',
        undef, $logtime, $journalu->{userid}, $posterid, $subject, $body
    );

    return 0 if $dbh->err;
    return 1;
}

# replycount_do
# input: $u, $jitemid, $action, $value
# action is one of: "init", "incr", "decr"
# $value is amount to incr/decr, 1 by default

sub replycount_do {
    my ( $u, $jitemid, $action, $value ) = @_;
    $value = 1 unless defined $value;
    my $uid    = $u->{'userid'};
    my $memkey = [ $uid, "rp:$uid:$jitemid" ];

    # "init" is easiest and needs no lock (called before the entry is live)
    if ( $action eq 'init' ) {
        LJ::MemCache::set( $memkey, "0   " );
        return 1;
    }

    return 0 unless $u->writer;

    my $lockkey = $memkey->[1];
    $u->selectrow_array( "SELECT GET_LOCK(?,10)", undef, $lockkey );

    my $ret;

    if ( $action eq 'decr' ) {
        $ret = LJ::MemCache::decr( $memkey, $value );
        $u->do(
            "UPDATE log2 SET replycount=replycount-$value WHERE journalid=$uid AND jitemid=$jitemid"
        );
    }

    if ( $action eq 'incr' ) {
        $ret = LJ::MemCache::incr( $memkey, $value );
        $u->do(
            "UPDATE log2 SET replycount=replycount+$value WHERE journalid=$uid AND jitemid=$jitemid"
        );
    }

    if ( @LJ::MEMCACHE_SERVERS && !defined $ret ) {
        my $rc = $u->selectrow_array(
            "SELECT replycount FROM log2 WHERE journalid=$uid AND jitemid=$jitemid");
        if ( defined $rc ) {
            $rc = sprintf( "%-4d", $rc );
            LJ::MemCache::set( $memkey, $rc );
        }
    }

    $u->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );

    return 1;
}

# <LJFUNC>
# name: LJ::get_logtext2
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext2]].
# args: u, opts?, jitemid*
# returns: hashref with keys being jitemids, values being [ $subject, $body ]
# des-opts: Optional hashref of special options.  NOW IGNORED (2005-09-14)
# des-jitemid: List of jitemids to retrieve the subject & text for.
# </LJFUNC>
sub get_logtext2 {
    my $u         = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'} + 0;

    my $opts = ref $_[0] ? shift : {};    # this is now ignored

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach (@_) {
        my $id = $_ + 0;
        $need{$id} = 1;
        push @mem_keys, [ $journalid, "logtext:$clusterid:$journalid:$id" ];
    }

    # pass 1: memcache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
    while ( my ( $k, $v ) = each %$mem ) {
        next unless $v;
        $k =~ /:(\d+):(\d+):(\d+)/;
        delete $need{$3};
        $lt->{$3} = $v;
    }

    return $lt unless %need;

    # pass 2: databases
    my $db = LJ::get_cluster_def_reader($clusterid);
    die "Can't get database handle loading entry text" unless $db;

    my $jitemid_in = join( ", ", keys %need );
    my $sth        = $db->prepare( "SELECT jitemid, subject, event FROM logtext2 "
            . "WHERE journalid=$journalid AND jitemid IN ($jitemid_in)" );
    $sth->execute;
    while ( my ( $id, $subject, $event ) = $sth->fetchrow_array ) {
        LJ::text_uncompress( \$event );
        my $val = [ $subject, $event ];
        $lt->{$id} = $val;
        LJ::MemCache::add( [ $journalid, "logtext:$clusterid:$journalid:$id" ], $val );
        delete $need{$id};
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_talktext2
# des: Retrieves comment text. Tries slave servers first, then master.
# info: Efficiently retrieves batches of comment text. Will try alternate
#       servers first. See also [func[LJ::get_logtext2]].
# returns: Hashref with the talkids as keys, values being [ $subject, $event ].
# args: u, opts?, jtalkids
# des-opts: A hashref of options. 'onlysubjects' will only retrieve subjects.
# des-jtalkids: A list of talkids to get text for.
# </LJFUNC>
sub get_talktext2 {
    my $u         = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'} + 0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach (@_) {
        my $id = $_ + 0;
        $need{$id} = 1;
        push @mem_keys, [ $journalid, "talksubject:$clusterid:$journalid:$id" ];
        unless ( $opts->{'onlysubjects'} ) {
            push @mem_keys, [ $journalid, "talkbody:$clusterid:$journalid:$id" ];
        }
    }

    # try the memory cache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

    if ($LJ::_T_GET_TALK_TEXT2_MEMCACHE) {
        $LJ::_T_GET_TALK_TEXT2_MEMCACHE->();
    }

    while ( my ( $k, $v ) = each %$mem ) {
        $k =~ /^talk(.*):(\d+):(\d+):(\d+)/;
        if ( $opts->{'onlysubjects'} && $1 eq "subject" ) {
            delete $need{$4};
            $lt->{$4} = [$v];
        }
        if (  !$opts->{'onlysubjects'}
            && $1 eq "body"
            && exists $mem->{"talksubject:$2:$3:$4"} )
        {
            delete $need{$4};
            $lt->{$4} = [ $mem->{"talksubject:$2:$3:$4"}, $v ];
        }
    }
    return $lt unless %need;

    my $bodycol = $opts->{'onlysubjects'} ? "" : ", body";

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass ( 1, 2 ) {
        next unless %need;
        my $db =
            $pass == 1
            ? LJ::get_cluster_reader($clusterid)
            : LJ::get_cluster_def_reader($clusterid);

        unless ($db) {
            next if $pass == 1;
            die "Could not get db handle";
        }

        my $in  = join( ",", keys %need );
        my $sth = $db->prepare( "SELECT jtalkid, subject $bodycol FROM talktext2 "
                . "WHERE journalid=$journalid AND jtalkid IN ($in)" );
        $sth->execute;
        while ( my ( $id, $subject, $body ) = $sth->fetchrow_array ) {
            $subject = "" unless defined $subject;
            $body    = "" unless defined $body;
            LJ::text_uncompress( \$body );
            $lt->{$id} = [ $subject, $body ];
            LJ::MemCache::add( [ $journalid, "talkbody:$clusterid:$journalid:$id" ], $body )
                unless $opts->{'onlysubjects'};
            LJ::MemCache::add( [ $journalid, "talksubject:$clusterid:$journalid:$id" ], $subject );
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::item_link
# class: component
# des: Returns URL to view an individual journal item.
# info: The returned URL may have an ampersand in it.  In an HTML/XML attribute,
#       these must first be escaped by, say, [func[LJ::ehtml]].  This
#       function doesn't return it pre-escaped because the caller may
#       use it in, say, a plain-text e-mail message.
# args: u, itemid, anum?
# des-itemid: Itemid of entry to link to.
# des-anum: If present, $u is assumed to be on a cluster and itemid is assumed
#           to not be a $ditemid already, and the $itemid will be turned into one
#           by multiplying by 256 and adding $anum.
# returns: scalar; unescaped URL string
# </LJFUNC>
sub item_link {
    my ( $u, $itemid, $anum, $args ) = @_;
    my $ditemid = $itemid * 256 + $anum;
    $u = LJ::load_user($u) unless LJ::isu($u);

    $args = $args ? "?$args" : "";
    return $u->journal_base . "/$ditemid.html$args";
}

# <LJFUNC>
# name: LJ::expand_embedded
# class:
# des: Used for expanding embedded content like polls, for entries.
# info: The u-object of the journal in question transmits to the function
#       and its hooks.
# args: u, ditemid, remote, eventref, opts?
# des-eventref:
# des-opts:
# returns:
# </LJFUNC>

sub expand_embedded {
    my ( $u, $ditemid, $remote, $eventref, %opts ) = @_;
    LJ::Poll->expand_entry( $eventref, %opts ) unless $opts{preview};
    LJ::EmbedModule->expand_entry( $u, $eventref, %opts );
    LJ::Hooks::run_hooks( "expand_embedded", $u, $ditemid, $remote, $eventref, %opts );
}

# <LJFUNC>
# name: LJ::item_toutf8
# des: convert one item's subject, text and props to UTF-8.
#      item can be an entry or a comment (in which cases props can be
#      left empty, since there are no 8bit talkprops).
# args: u, subject, text, props
# des-u: user hashref of the journal's owner
# des-subject: ref to the item's subject
# des-text: ref to the item's text
# des-props: hashref of the item's props
# returns: nothing.
# </LJFUNC>
sub item_toutf8 {
    my ( $u, $subject, $text, $props ) = @_;
    $props ||= {};

    my $convert = sub {
        my $rtext = $_[0];
        my $error = 0;
        return unless defined $$rtext;

        my $res = LJ::text_convert( $$rtext, $u, \$error );
        if ($error) {
            LJ::text_out($rtext);
        }
        else {
            $$rtext = $res;
        }
        return;
    };

    $convert->($subject);
    $convert->($text);

    # FIXME: Have some logprop flag for what props are binary
    foreach ( keys %$props ) {
        next if $_ eq 'xpost' || $_ eq 'xpostdetail';
        $convert->( \$props->{$_} );
    }
    return;
}

# function to fill in hash for basic currents
sub currents {
    my ( $props, $u, $opts ) = @_;
    return unless ref $props eq 'HASH';
    my %current;

    my ( $key, $entry, $s2imgref ) = ( "", undef, undef );
    if ( $opts && ref $opts ) {
        $key      = $opts->{key} || '';
        $entry    = $opts->{entry};
        $s2imgref = $opts->{s2imgref};
    }

    # Mood
    if ( $props->{"${key}current_mood"} || $props->{"${key}current_moodid"} ) {
        my $moodid = $props->{"${key}current_moodid"};
        my $mood   = $props->{"${key}current_mood"};
        my ( $moodname, $moodpic ) = ( '', '' );

        # favor custom mood over system mood
        if ( my $val = $mood ) {
            LJ::CleanHTML::clean_subject( \$val );
            $moodname = $val;
        }

        if ( my $val = $moodid ) {
            $moodname ||= DW::Mood->mood_name($val);
            if ( defined $u ) {
                my $themeid = LJ::isu($u) ? $u->moodtheme : undef;

                # $u might be a hashref instead of a user object?
                $themeid ||= ref $u ? $u->{moodthemeid} : undef;
                my $theme = DW::Mood->new($themeid);
                my %pic;
                if ( $theme && $theme->get_picture( $val, \%pic ) ) {
                    if ( $s2imgref && ref $s2imgref ) {

                        # return argument array for S2::Image
                        $$s2imgref = [ $pic{pic}, $pic{w}, $pic{h} ];
                    }
                    else {
                        $moodpic =
                              "<img class='moodpic' src=\"$pic{pic}\" "
                            . "width='$pic{w}' height='$pic{h}' "
                            . "align='absmiddle' vspace='1' alt='' /> ";
                    }
                }
            }
        }

        $current{Mood} = "$moodpic$moodname";
    }

    # Music
    if ( $props->{"${key}current_music"} ) {
        $current{Music} = $props->{"${key}current_music"};
        LJ::CleanHTML::clean_subject( \$current{Music} );
    }

    # Location
    if ( $props->{"${key}current_location"} || $props->{"${key}current_coords"} ) {
        my $loc = eval {
            LJ::Location->new(
                coords   => $props->{"${key}current_coords"},
                location => $props->{"${key}current_location"}
            );
        };
        $current{Location} = $loc->as_current if $loc;
        LJ::CleanHTML::clean_subject( \$current{Location} );
    }

    # Crossposts
    if ( my $xpost = $props->{"${key}xpostdetail"} ) {
        my $xposthash  = DW::External::Account->xpost_string_to_hash($xpost);
        my $xpostlinks = "";
        foreach my $xpostvalue ( values %$xposthash ) {
            if ( $xpostvalue->{url} ) {
                my $xpost_url = LJ::no_utf8_flag( $xpostvalue->{url} );
                $xpostlinks .= " " if $xpostlinks;
                $xpostlinks .= "<a href='$xpost_url'>$xpost_url</a>";
            }
        }
        $current{Xpost} = $xpostlinks if $xpostlinks;
    }

    if ($entry) {

        # Groups
        my $group_names = $entry->group_names;
        $current{Groups} = $group_names if $group_names;

        # Tags
        my $u       = $entry->journal;
        my $base    = $u->journal_base;
        my $itemid  = $entry->jitemid;
        my $logtags = LJ::Tags::get_logtags( $u, $itemid );
        if ( $logtags->{$itemid} ) {
            my @tags = map { "<a href='$base/tag/" . LJ::eurl($_) . "'>" . LJ::ehtml($_) . "</a>" }
                sort values %{ $logtags->{$itemid} };
            $current{Tags} = join( ', ', @tags ) if @tags;
        }
    }

    return %current;
}

# function to format table for currents display
sub currents_table {
    my (%current) = @_;
    my $ret = '';
    return $ret unless %current;

    $ret .= "<table summary='' class='currents' border=0>\n";
    foreach ( sort keys %current ) {
        next unless $current{$_};

        my $curkey  = "talk.curname_" . $_;
        my $curname = LJ::Lang::ml($curkey);
        $curname = "<b>Current $_:</b>" unless $curname;

        $ret .= "<tr><td align='right'>$curname</td>";
        $ret .= "<td>$current{$_}</td></tr>\n";
    }
    $ret .= "</table>\n";

    return $ret;
}

1;
