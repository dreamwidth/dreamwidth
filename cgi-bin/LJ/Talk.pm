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

package LJ::Talk;
use strict;

use MIME::Words;
use MIME::Lite;
use Carp qw(croak);

use LJ::Global::Constants;
use LJ::Event::JournalNewComment;
use LJ::Event::JournalNewComment::Edited;
use LJ::Comment;
use LJ::OpenID;
use LJ::S2;
use DW::Captcha;
use LJ::JSON;

use DW::EmailPost::Comment;

# dataversion for rate limit logging
our $RATE_DATAVER = "1";

my %subjecticons;

# Returns a hashref of the following form:
# {
#     types => ['sm', 'md'],
#     lists => {
#         sm => [
#             { img => "sm01_smiley.gif", id => "sm01", w => 15, h => 15, alt => "Smiley" },
#             ...
#         ],
#         md => [
#             { img => "md01_alien.gif", id => "md01", w => 32, h => 32, alt => "Smiling Alien" },
#             ...
#         ]
#     },
#     pic => { # flat index for convenience
#         sm01 => { img => "sm01_smiley.gif", id => "sm01", w => 15, h => 15, alt => "Smiley" },
#         ...
#     }
# }
sub get_subjecticons {
    unless ( keys %subjecticons ) {
        $subjecticons{'types'} = [ 'sm', 'md' ];
        $subjecticons{'lists'}->{'md'} = [
            { img => "md01_alien.gif",       w => 32, h => 32, alt => "Smiling Alien" },
            { img => "md02_skull.gif",       w => 32, h => 32, alt => "Skull and Crossbones" },
            { img => "md05_sick.gif",        w => 25, h => 25, alt => "Sick Face" },
            { img => "md06_radioactive.gif", w => 20, h => 20, alt => "Radioactive Symbol" },
            { img => "md07_cool.gif",        w => 20, h => 20, alt => "Cool Smiley" },
            { img => "md08_bulb.gif",        w => 17, h => 23, alt => "Lightbulb" },
            { img => "md09_thumbdown.gif",   w => 25, h => 19, alt => "Red Thumbs Down" },
            { img => "md10_thumbup.gif",     w => 25, h => 19, alt => "Green Thumbs Up" }
        ];
        $subjecticons{'lists'}->{'sm'} = [
            { img => "sm01_smiley.gif", w => 15, h => 15, alt => "Smiley" },
            { img => "sm02_wink.gif",   w => 15, h => 15, alt => "Winking Smiley" },
            { img => "sm03_blush.gif",  w => 15, h => 15, alt => "Blushing Smiley" },
            { img => "sm04_shock.gif",  w => 15, h => 15, alt => "Shocked Smiley" },
            { img => "sm05_sad.gif",    w => 15, h => 15, alt => "Sad Smiley" },
            { img => "sm06_angry.gif",  w => 15, h => 15, alt => "Angry Smiley" },
            { img => "sm07_check.gif",  w => 15, h => 15, alt => "Checkmark" },
            { img => "sm08_star.gif",   w => 20, h => 18, alt => "Gold Star" },
            { img => "sm09_mail.gif",   w => 14, h => 10, alt => "Envelope" },
            { img => "sm10_eyes.gif",   w => 24, h => 12, alt => "Shifty Eyes" }
        ];

        # assemble ->{'id'} portion of hash.  the part of the imagename before the _
        foreach ( keys %{ $subjecticons{'lists'} } ) {
            foreach my $pic ( @{ $subjecticons{'lists'}->{$_} } ) {
                next unless ( $pic->{'img'} =~ /^(\D{2}\d{2})\_.+$/ );
                $subjecticons{'pic'}->{$1} = $pic;
                $pic->{'id'} = $1;
            }
        }
        $subjecticons{'pic'}->{'none'} = {
            img => "none.gif",
            id  => "none",
            w   => 15,
            h   => 15,
            alt => "No Subject Icon Selected"
        };
    }

    return \%subjecticons;
}

# Returns talkurl with GET args added (don't pass #anchors to this :-)
sub talkargs {
    my $talkurl = shift;
    my $args    = join( "&", grep { $_ } @_ );
    my $sep     = '';
    $sep = ( $talkurl =~ /\?/ ? "&" : "?" ) if $args;
    return "$talkurl$sep$args";
}

# LJ::Talk::get_subjecticon_by_id(id)
# Args: A subjecticon ID string (like 'none' or 'sm09').
# Returns: A subjecticon hashref suitable for LJ::Talk::print_subjecticon, or
#          undef if the ID is empty/invalid.
sub get_subjecticon_by_id {
    my $id           = shift;
    my $subjecticons = LJ::Talk::get_subjecticons();
    return $subjecticons->{'pic'}->{$id};
}

# LJ::Talk::print_subjecticon(subjecticon_hashref)
# Args: A hashref that represents a subjecticon, and optionally a string of
#       extra HTML attributes.
# Returns: An image tag for the requested subjecticon, or an empty string if the
#          subjecticon hashref missing.
# Subjecticon hashrefs usually come from get_subjecticons.
sub print_subjecticon {    # expects a subjecticon ref
    my ( $p, $extra ) = @_;
    return '' unless ref $p eq 'HASH';
    return
qq{<img src="$LJ::IMGPREFIX/talk/$p->{img}" border="0" width="$p->{w}" height="$p->{h}" alt="$p->{alt}" valign="middle" $extra />};
}

# LJ::Talk::print_subjecticon_by_id(id)
# Args: A subjecticon ID string (like 'none' or 'sm09'), and optionally a string
#       of extra HTML attributes.
# Returns: An image tag for the requested subjecticon, or an empty string if the
#          ID is empty or invalid.
sub print_subjecticon_by_id {
    my ( $id, $extra ) = @_;
    return print_subjecticon( get_subjecticon_by_id($id), $extra );
}

sub link_bar {
    my $opts = shift;
    my ( $u, $up, $remote, $headref, $itemid ) =
        map { $opts->{$_} } qw(u up remote headref itemid);

    # we want user objects, so make sure they are
    ( $u, $up, $remote ) = map { LJ::want_user($_) } ( $u, $up, $remote );

    my $mlink = sub {
        my ( $url, $piccode ) = @_;
        return (
            "<a href=\"$url\">" . LJ::img( $piccode, "", { 'align' => 'absmiddle' } ) . "</a>" );
    };

    my $jarg    = "journal=$u->{'user'}&";
    my $jargent = "journal=$u->{'user'}&amp;";

    my $entry = LJ::Entry->new( $u, ditemid => $itemid );

    # << Previous
    my @linkele;
    my $prevlink = LJ::create_url(
        "/go",
        host          => $LJ::DOMAIN_WEB,
        viewing_style => 1,
        args          => {
            journal => $u->user,
            itemid  => $itemid,
            dir     => "prev",
        }
    );
    push @linkele, $mlink->( $prevlink, "prev_entry" );
    $$headref .= "<link href='$prevlink' rel='Previous' />\n";

    # memories
    if ( LJ::is_enabled('memories') ) {
        push @linkele, $mlink->( "$LJ::SITEROOT/tools/memadd?${jargent}itemid=$itemid", "memadd" );
    }

    # edit entry - if we have a remote, and that person can manage
    # the account in question, OR, they posted the entry, and have
    # access to the community in question
    if (
        defined $remote
        && ( $remote->can_manage($u)
            || ( $remote->equals($up) && $up->can_post_to($u) ) )
        )
    {
        push @linkele,
            $mlink->( "$LJ::SITEROOT/editjournal?${jargent}itemid=$itemid", "editentry" );
    }

    # edit tags
    if ( LJ::is_enabled('tags') ) {
        if ( defined $remote && LJ::Tags::can_add_entry_tags( $remote, $entry ) ) {
            push @linkele,
                $mlink->( "$LJ::SITEROOT/edittags?${jargent}itemid=$itemid", "edittags" );
        }
    }

    if ( LJ::is_enabled('tellafriend') ) {
        push @linkele,
            $mlink->( "$LJ::SITEROOT/tools/tellafriend?${jargent}itemid=$itemid", "tellfriend" )
            if ( $entry->can_tellafriend($remote) );
    }

    if ( $remote && $remote->can_use_esn ) {
        my $img_key = $remote->has_subscription(
            journal        => $u,
            event          => "JournalNewComment",
            arg1           => $itemid,
            require_active => 1
        ) ? "track_active" : "track";
        push @linkele,
            $mlink->( "$LJ::SITEROOT/manage/tracking/entry?${jargent}itemid=$itemid", $img_key );
    }

    ## >>> Next
    my $nextlink = LJ::create_url(
        "/go",
        host          => $LJ::DOMAIN_WEB,
        viewing_style => 1,
        args          => {
            journal => $u->user,
            itemid  => $itemid,
            dir     => "next",
        }
    );
    push @linkele, $mlink->( "$nextlink", "next_entry" );
    $$headref .= "<link href='$nextlink' rel='Next' />\n";

    my $ret;
    if (@linkele) {
        $ret =
              qq{<div class="action-box"><ul class="nostyle inner"><li>}
            . join( "</li><li>", @linkele )
            . "</li></ul></div><div class='clear-floats'></div>";
    }
    return $ret;
}

sub init {
    my ($form) = @_;
    my $init = {};    # structure to return

    my $journal = $form->{'journal'};
    my $ju      = undef;
    my $item    = undef;                # hashref; journal item conversation is in

    # defaults, to be changed later:
    $init->{'itemid'}    = ( $form->{'itemid'} || 0 ) + 0;
    $init->{'ditemid'}   = $init->{'itemid'};
    $init->{'thread'}    = ( $form->{'thread'} || 0 ) + 0;
    $init->{'dthread'}   = $init->{'thread'};
    $init->{'clustered'} = 0;
    $init->{'replyto'}   = ( $form->{'replyto'} || 0 ) + 0;
    $init->{'style'}     = $form->{'style'}
        if $form->{style} && $form->{style} =~ /^(?:mine|light)$/;

    if ($journal) {

        # they specified a journal argument, which indicates new style.
        $ju = LJ::load_user($journal);
        return { 'error' => BML::ml('talk.error.nosuchjournal') } unless $ju;
        return { 'error' => BML::ml('talk.error.purged') } if $ju->is_expunged;

        LJ::assert_is( $ju->{user}, lc $journal );
        $ju->selfassert;

        $init->{'clustered'} = 1;
        foreach (qw(itemid replyto)) {
            next unless $init->{$_};
            $init->{'anum'} = $init->{$_} % 256;
            $init->{$_} = int( $init->{$_} / 256 );
            last;
        }
        $init->{'thread'} = int( $init->{'thread'} / 256 )
            if $init->{'thread'};
    }
    else {
        return { 'error' => BML::ml('talk.error.noentry') };
    }

    $init->{'journalu'} = $ju;
    return $init;
}

# $u, $itemid
sub get_journal_item {
    my ( $u, $itemid ) = @_;
    return unless $u && $itemid;

    my $uid = $u->{'userid'} + 0;
    $itemid += 0;

    my $item = LJ::get_log2_row( $u, $itemid );
    return undef unless $item;

    $item->{'alldatepart'} = LJ::alldatepart_s2( $item->{'eventtime'} );

    $item->{'itemid'}  = $item->{'jitemid'};      # support old & new keys
    $item->{'ownerid'} = $item->{'journalid'};    # support old & news keys

    my $lt = LJ::get_logtext2( $u, $itemid );
    my $v  = $lt->{$itemid};
    $item->{'subject'} = $v->[0];
    $item->{'event'}   = $v->[1];

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2( $u->{'userid'}, [$itemid], \%logprops );
    $item->{'props'} = $logprops{$itemid} || {};

    if ( $logprops{$itemid}->{'unknown8bit'} ) {
        LJ::item_toutf8( $u, \$item->{'subject'}, \$item->{'event'},
            $item->{'logprops'}->{$itemid} );
    }
    return $item;
}

sub check_viewable {
    my ( $remote, $item, $form, $errref ) = @_;

    # note $form no longer used

    my $err = sub {
        $$errref = "<?h1 <?_ml Error _ml?> h1?><?p $_[0] p?>";
        return 0;
    };

    my $ent = LJ::Entry->new_from_item_hash($item)
        or die "Unable to construct entry object.\n";
    return 1 if $ent->visible_to($remote);

    my $apache_r = BML::get_request();

    # this checks to see why the logged-in user is not allowed to see
    # the given content.
    if ( defined $remote ) {
        my $journal     = LJ::load_userid( $item->{ownerid} );
        my $journalname = $journal->username;

        if (   $journal->is_community
            && !$journal->is_closed_membership
            && $remote
            && $item->{security} ne "private" )
        {
            $apache_r->notes->{error_key}   = ".comm.open";
            $apache_r->notes->{journalname} = $journalname;
        }
        elsif ( $journal->is_community && $journal->is_closed_membership ) {
            $apache_r->notes->{error_key}   = ".comm.closed";
            $apache_r->notes->{journalname} = $journalname;
        }
    }

    $apache_r->notes->{internal_redir} = "/protected";
    $apache_r->notes->{returnto}       = LJ::create_url( undef, keep_args => 1 );
    return 0;

}

# <LJFUNC>
# name: LJ::Talk::can_delete
# des: Determines if a user can delete a comment or entry: You can
#       delete anything you've posted.  You can delete anything posted in something
#       you own (i.e. a comment in your journal, a comment to an entry you made in
#       a community).  You can also delete any item in an account you have the
#       "A"dministration edge for.
# args: remote, u, up, userpost
# des-remote: User object we're checking access of.  From [func[LJ::get_remote]].
# des-u: Username or object of the account the thing is located in.
# des-up: Username or object of person who owns the parent of the thing.  (I.e. the poster
#           of the entry a comment is in.)
# des-userpost: Username (<strong>not</strong> object) of person who posted the item.
# returns: Boolean indicating whether remote is allowed to delete the thing
#           specified by the other options.
# </LJFUNC>
sub can_delete {
    my ( $remote, $u, $up, $userpost ) = @_;    # remote, journal, posting user, commenting user
    $userpost ||= "";

    return 0 unless LJ::isu($remote);
    return 1
        if $remote->user eq $userpost
        || $remote->user eq ( ref $u ? $u->user : $u )
        || LJ::Talk::can_screen(@_);
    return 0;
}

sub can_screen {
    my ( $remote, $u, $up, $userpost ) = @_;    # remote, journal, posting user, commenting user
    return 0 unless LJ::isu($remote);
    return 1
        if $remote->user eq ( ref $up  ? $up->user : $up )
        || $remote->can_manage( ref $u ? $u        : LJ::load_user($u) );
    return 0;
}

sub can_unscreen {
    return LJ::Talk::can_screen(@_);
}

sub can_freeze {
    return LJ::Talk::can_screen(@_);
}

sub can_unfreeze {
    return LJ::Talk::can_unscreen(@_);
}

# <LJFUNC>
# name: LJ::Talk::screening_level
# des: Determines the screening level of a particular post given the relevant information.
# args: journalu, jitemid
# des-journalu: User object of the journal the post is in.
# des-jitemid: Itemid of the post.
# returns: Single character that indicates the screening level.  Undef means don't screen
#          anything, 'A' means screen All, 'R' means screen Anonymous (no-remotes), 'F' means
#          screen non-friends.
# </LJFUNC>
sub screening_level {
    my ( $journalu, $jitemid ) = @_;
    die 'LJ::screening_level needs a user object.' unless ref $journalu;
    $jitemid += 0;
    die 'LJ::screening_level passed invalid jitemid.' unless $jitemid;

    # load the logprops for this entry
    my %props;
    LJ::load_log_props2( $journalu->{userid}, [$jitemid], \%props );

    # determine if userprop was overriden
    my $val = $props{$jitemid}{opt_screening} || '';
    return if $val eq 'N';    # N means None, so return undef
    return $val if $val;

    # now return userprop, as it's our last chance
    my $userprop = $journalu->prop('opt_whoscreened');
    return $userprop && $userprop eq 'N' ? undef : $userprop;
}

sub update_commentalter {
    my ( $u, $itemid ) = @_;
    LJ::set_logprop( $u, $itemid, { 'commentalter' => time() } );
}

# <LJFUNC>
# name: LJ::Talk::get_comments_in_thread
# class: web
# des: Gets a list of comment ids that are contained within a thread, including the
#      comment at the top of the thread.  You can also limit this to only return comments
#      of a certain state.
# args: u, jitemid, jtalkid, onlystate, screenedref
# des-u: user object of user to get comments from
# des-jitemid: journal itemid to get comments from
# des-jtalkid: journal talkid of comment to use as top of tree
# des-onlystate: if specified, return only comments of this state (e.g. A, F, S...)
# des-screenedref: if provided and an array reference, will push on a list of comment
#                   ids that are being returned and are screened (mostly for use in deletion so you can
#                   unscreen the comments)
# returns: undef on error, array reference of jtalkids on success
# </LJFUNC>
sub get_comments_in_thread {
    my ( $u, $jitemid, $jtalkid, $onlystate, $screened_ref ) = @_;
    $u = LJ::want_user($u);
    $jitemid += 0;
    $jtalkid += 0;
    $onlystate = uc $onlystate;
    return undef
        unless $u
        && $jitemid
        && $jtalkid
        && ( !$onlystate || $onlystate =~ /^\w$/ );

    # get all comments to post
    my $comments = LJ::Talk::get_talk_data( $u, 'L', $jitemid ) || {};

    # see if our comment exists
    return undef unless $comments->{$jtalkid};

    # create relationship hashref and count screened comments in post
    my %parentids;
    $parentids{$_} = $comments->{$_}{parenttalkid} foreach keys %$comments;

    # now walk and find what to update
    my %to_act;
    foreach my $id ( keys %$comments ) {
        my $act  = ( $id == $jtalkid );
        my $walk = $id;
        while ( $parentids{$walk} ) {
            if ( $parentids{$walk} == $jtalkid ) {

                # we hit the one we want to act on
                $act = 1;
                last;
            }
            last if $parentids{$walk} == $walk;

            # no match, so move up a level
            $walk = $parentids{$walk};
        }

        # set it as being acted on
        $to_act{$id} = 1 if $act && ( !$onlystate || $comments->{$id}{state} eq $onlystate );

        # push it onto the list of screened comments? (if the caller is doing a delete, they need
        # a list of screened comments in order to unscreen them)
        push @$screened_ref, $id if ref $screened_ref &&    # if they gave us a ref
            $to_act{$id} &&                                 # and we're acting on this comment
            $comments->{$id}{state} eq 'S';                 # and this is a screened comment
    }

    # return list from %to_act
    return [ keys %to_act ];
}

# <LJFUNC>
# name: LJ::Talk::delete_thread
# class: web
# des: Deletes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to delete thread from.
# des-jitemid: Journal itemid of item to delete comments from.
# des-jtalkid: Journal talkid of comment at top of thread to delete.
# returns: 1 on success; undef on error
# </LJFUNC>
sub delete_thread {
    my ( $u, $jitemid, $jtalkid ) = @_;

    # get comments and delete 'em
    my @screened;
    my $ids = LJ::Talk::get_comments_in_thread( $u, $jitemid, $jtalkid, undef, \@screened );
    LJ::Talk::unscreen_comment( $u, $jitemid, @screened ) if @screened;    # if needed only!
    my $num = LJ::delete_comments( $u, "L", $jitemid, @$ids );
    LJ::replycount_do( $u, $jitemid, "decr", $num );
    LJ::Talk::update_commentalter( $u, $jitemid );
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::delete_comment
# class: web
# des: Deletes a single comment.
# args: u, jitemid, jtalkid, state?
# des-u: Userid or user object to delete comment from.
# des-jitemid: Journal itemid of item to delete comment from.
# des-jtalkid: Journal talkid of the comment to delete.
# des-state: Optional. If you know it, provide the state
#            of the comment being deleted, else we load it.
# returns: 1 on success; undef on error
# </LJFUNC>
sub delete_comment {
    my ( $u, $jitemid, $jtalkid, $state ) = @_;
    return undef unless $u && $jitemid && $jtalkid;

    unless ($state) {
        my $td = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
        return undef unless $td;

        $state = $td->{$jtalkid}->{state};
    }
    return undef unless $state;

    # if it's screened, unscreen it first to properly adjust logprops
    LJ::Talk::unscreen_comment( $u, $jitemid, $jtalkid )
        if $state eq 'S';

    # now do the deletion
    my $num = LJ::delete_comments( $u, "L", $jitemid, $jtalkid );
    LJ::replycount_do( $u, $jitemid, "decr", $num );
    LJ::Talk::update_commentalter( $u, $jitemid );

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::freeze_thread
# class: web
# des: Freezes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to freeze thread from.
# des-jitemid: Journal itemid of item to freeze comments from.
# des-jtalkid: Journal talkid of comment at top of thread to freeze.
# returns: 1 on success; undef on error
# </LJFUNC>
sub freeze_thread {
    my ( $u, $jitemid, $jtalkid ) = @_;

    # now we need to update the states
    my $ids = LJ::Talk::get_comments_in_thread( $u, $jitemid, $jtalkid, 'A' );
    LJ::Talk::freeze_comments( $u, "L", $jitemid, 0, $ids );
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::unfreeze_thread
# class: web
# des: unfreezes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to unfreeze thread from.
# des-jitemid: Journal itemid of item to unfreeze comments from.
# des-jtalkid: Journal talkid of comment at top of thread to unfreeze.
# returns: 1 on success; undef on error
# </LJFUNC>
sub unfreeze_thread {
    my ( $u, $jitemid, $jtalkid ) = @_;

    # now we need to update the states
    my $ids = LJ::Talk::get_comments_in_thread( $u, $jitemid, $jtalkid, 'F' );
    LJ::Talk::freeze_comments( $u, "L", $jitemid, 1, $ids );
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::freeze_comments
# class: web
# des: Freezes comments.  This is the internal helper function called by
#      freeze_thread/unfreeze_thread.  Use those if you wish to freeze or
#      unfreeze a thread.  This function just freezes specific comments.
# args: u, nodetype, nodeid, unfreeze, ids
# des-u: Userid or object of user to manipulate comments in.
# des-nodetype: Nodetype of the thing containing the specified ids.  Typically "L".
# des-nodeid: Id of the node to manipulate comments from.
# des-unfreeze: If 1, unfreeze instead of freeze.
# des-ids: Array reference containing jtalkids to manipulate.
# returns: 1 on success; undef on error
# </LJFUNC>
sub freeze_comments {
    my ( $u, $nodetype, $nodeid, $unfreeze, $ids ) = @_;
    $u = LJ::want_user($u);
    $nodeid += 0;
    $unfreeze = $unfreeze ? 1 : 0;
    return undef unless LJ::isu($u) && $nodetype =~ /^\w$/ && $nodeid && @$ids;

    # get database and quote things
    return undef unless $u->writer;
    my $quserid   = $u->{userid} + 0;
    my $qnodetype = $u->quote($nodetype);
    my $qnodeid   = $nodeid + 0;

    # now perform action
    my $in       = join( ',', map { $_ + 0 } @$ids );
    my $newstate = $unfreeze ? 'A' : 'F';
    my $res      = $u->talk2_do( $nodetype, $nodeid, undef,
              "UPDATE talk2 SET state = '$newstate' "
            . "WHERE journalid = $quserid AND nodetype = $qnodetype "
            . "AND nodeid = $qnodeid AND jtalkid IN ($in)" );

    # invalidate talk2row memcache props
    LJ::Talk::invalidate_talk2row_memcache( $u->id, @$ids );

    return undef unless $res;
    return 1;
}

sub screen_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid   = shift(@_) + 0;
    my @jtalkids = @_;

    my $in = join( ',', map { $_ + 0 } @jtalkids );
    return unless $in;

    my $userid = $u->{'userid'} + 0;

    my $updated = $u->talk2_do( "L", $itemid, undef,
              "UPDATE talk2 SET state='S' "
            . "WHERE journalid=$userid AND jtalkid IN ($in) "
            . "AND nodetype='L' AND nodeid=$itemid "
            . "AND state NOT IN ('S','D')" );
    return undef unless $updated;

    # invalidate talk2row memcache props
    LJ::Talk::invalidate_talk2row_memcache( $u->id, @jtalkids );
    LJ::MemCache::delete( [ $userid, "activeentries:$userid" ] );

    if ( $updated > 0 ) {
        LJ::replycount_do( $u, $itemid, "decr", $updated );
        LJ::set_logprop( $u, $itemid, { 'hasscreened' => 1 } );
    }

    LJ::MemCache::delete( [ $userid, "screenedcount:$userid:$itemid" ] );

    LJ::Talk::update_commentalter( $u, $itemid );
    return;
}

sub unscreen_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid   = shift(@_) + 0;
    my @jtalkids = @_;

    my $in = join( ',', map { $_ + 0 } @jtalkids );
    return unless $in;

    my $userid = $u->{'userid'} + 0;
    my $prop   = LJ::get_prop( "log", "hasscreened" );

    my $updated = $u->talk2_do( "L", $itemid, undef,
              "UPDATE talk2 SET state='A' "
            . "WHERE journalid=$userid AND jtalkid IN ($in) "
            . "AND nodetype='L' AND nodeid=$itemid "
            . "AND state='S'" );
    return undef unless $updated;

    LJ::Talk::invalidate_talk2row_memcache( $u->id, @jtalkids );
    LJ::MemCache::delete( [ $userid, "activeentries:$userid" ] );

    if ( $updated > 0 ) {
        LJ::replycount_do( $u, $itemid, "incr", $updated );
        my $dbcm        = LJ::get_cluster_master($u);
        my $hasscreened = $dbcm->selectrow_array( "SELECT COUNT(*) FROM talk2 "
                . "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='S'" );
        LJ::set_logprop( $u, $itemid, { 'hasscreened' => 0 } ) unless $hasscreened;
    }

    LJ::MemCache::delete( [ $userid, "screenedcount:$userid:$itemid" ] );

    LJ::Talk::update_commentalter( $u, $itemid );
    return;
}

# retrieves data from the talk2 table (but preferably memcache)
# returns a hashref (key -> { 'talkid', 'posterid', 'datepost', 'datepost_unix',
#                             'parenttalkid', 'state' } , or undef on failure
sub get_talk_data {
    my ( $u, $nodetype, $nodeid ) = @_;
    return undef unless LJ::isu($u);
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;

    my $ret = {};

    # check for data in memcache
    my $DATAVER     = "3";        # single character
    my $PACK_FORMAT = "NNNNC";    ## $talkid, $parenttalkid, $poster, $time, $state
    my $RECORD_SIZE = 17;

    my $memkey  = [ $u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid" ];
    my $lockkey = $memkey->[1];
    my $packed  = LJ::MemCache::get($memkey);

    # we check the replycount in memcache, the value we count, and then fix it up
    # if it seems necessary.
    my $rp_memkey = $nodetype eq "L" ? [ $u->{'userid'}, "rp:$u->{'userid'}:$nodeid" ] : undef;
    my $rp_count = $rp_memkey ? LJ::MemCache::get($rp_memkey) : 0;
    $rp_count ||=
        0;   # avoid warnings, FIXME how can LJ::MemCache::get return undef or sg that is not undef?

    # hook for tests to count memcache gets
    if ($LJ::_T_GET_TALK_DATA_MEMCACHE) {
        $LJ::_T_GET_TALK_DATA_MEMCACHE->();
    }

    my $rp_ourcount = 0;
    my $fixup_rp    = sub {
        return unless $nodetype eq "L";
        return if $rp_count == $rp_ourcount;
        return unless @LJ::MEMCACHE_SERVERS;
        return unless $u->writer;

        my $gc = LJ::gearman_client();
        if ( $gc && LJ::conf_test( $LJ::FIXUP_USING_GEARMAN, $u ) ) {
            $gc->dispatch_background(
                "fixup_logitem_replycount",
                Storable::nfreeze( [ $u->id, $nodeid ] ),
                {
                    uniq => "-",
                }
            );
        }
        else {
            LJ::Talk::fixup_logitem_replycount( $u, $nodeid );
        }
    };

    # Save the talkdata on the entry for later
    my $set_entry_cache = sub {
        return 1 unless $nodetype eq 'L';

        my $entry = LJ::Entry->new( $u, jitemid => $nodeid );
        $entry->set_talkdata($ret);
    };

    my $memcache_good = sub {
        return
               $packed
            && substr( $packed, 0, 1 ) eq $DATAVER
            && length($packed) % $RECORD_SIZE == 1;
    };

    my $memcache_decode = sub {
        my $n = ( length($packed) - 1 ) / $RECORD_SIZE;
        for ( my $i = 0 ; $i < $n ; $i++ ) {
            my ( $talkid, $par, $poster, $time, $state ) =
                unpack( $PACK_FORMAT, substr( $packed, $i * $RECORD_SIZE + 1, $RECORD_SIZE ) );
            $state = chr($state);
            $ret->{$talkid} = {
                talkid        => $talkid,
                state         => $state,
                posterid      => $poster,
                datepost_unix => $time,
                datepost      => LJ::mysql_time($time),    # timezone surely fucked.  deprecated.
                parenttalkid  => $par,
            };

            # comments are counted if they're 'A'pproved or 'F'rozen
            $rp_ourcount++ if $state eq "A" || $state eq "F";
        }
        $fixup_rp->();

        # set cache in LJ::Entry object for this set of comments
        $set_entry_cache->();

        return $ret;
    };

    return $memcache_decode->() if $memcache_good->();

    my $dbcr = LJ::get_cluster_def_reader($u);
    return undef unless $dbcr;

    my $lock = $dbcr->selectrow_array( "SELECT GET_LOCK(?,10)", undef, $lockkey );
    return undef unless $lock;

    # it's quite likely (for a popular post) that the memcache was
    # already populated while we were waiting for the lock
    $packed = LJ::MemCache::get($memkey);
    if ( $memcache_good->() ) {
        $dbcr->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );
        $memcache_decode->();
        return $ret;
    }

    my $memval = $DATAVER;
    my $sth =
        $dbcr->prepare( "SELECT t.jtalkid AS 'talkid', t.posterid, "
            . "t.datepost, UNIX_TIMESTAMP(t.datepost) as 'datepost_unix', "
            . "t.parenttalkid, t.state "
            . "FROM talk2 t "
            . "WHERE t.journalid=? AND t.nodetype=? AND t.nodeid=?" );
    $sth->execute( $u->{'userid'}, $nodetype, $nodeid );
    die $dbcr->errstr if $dbcr->err;
    while ( my $r = $sth->fetchrow_hashref ) {
        $ret->{ $r->{'talkid'} } = $r;

        {
            # make a new $r-type hash which also contains nodetype and nodeid
            # -- they're not in $r because they were known and specified in the query
            my %row_arg = %$r;
            $row_arg{nodeid}   = $nodeid;
            $row_arg{nodetype} = $nodetype;

            # set talk2row memcache key for this bit of data
            LJ::Talk::add_talk2row_memcache( $u->id, $r->{talkid}, \%row_arg );
        }

        $memval .= pack( $PACK_FORMAT,
            $r->{'talkid'},        $r->{'parenttalkid'}, $r->{'posterid'},
            $r->{'datepost_unix'}, ord( $r->{'state'} ) );

        $rp_ourcount++ if $r->{'state'} eq "A";
    }
    LJ::MemCache::set( $memkey, $memval );
    $dbcr->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );

    $fixup_rp->();

    # set cache in LJ::Entry object for this set of comments
    $set_entry_cache->();

    return $ret;
}

sub fixup_logitem_replycount {
    my ( $u, $jitemid ) = @_;

    # attempt to get a database lock to make sure that nobody else is in this section
    # at the same time we are
    my $nodetype = "L";    # this is only for logitem comment counts

    my $rp_memkey = [ $u->{'userid'}, "rp:$u->{'userid'}:$jitemid" ];
    my $rp_count  = LJ::MemCache::get($rp_memkey) || 0;
    my $fix_key   = "rp_fixed:$u->{userid}:$nodetype:$jitemid:$rp_count";

    my $db_key   = "rp:fix:$u->{userid}:$nodetype:$jitemid";
    my $got_lock = $u->selectrow_array( "SELECT GET_LOCK(?, 1)", undef, $db_key );
    return unless $got_lock;

    # setup an unlock handler
    my $unlock = sub {
        $u->do( "SELECT RELEASE_LOCK(?)", undef, $db_key );
        return undef;
    };

    # check memcache to see if someone has previously fixed this entry in this journal
    # with this reply count
    my $was_fixed = LJ::MemCache::get($fix_key);
    return $unlock->() if $was_fixed;

    # if we're doing innodb, begin a transaction, else lock tables
    my $sharedmode = "";
    if ( $u->is_innodb ) {
        $sharedmode = "LOCK IN SHARE MODE";
        $u->begin_work;
    }
    else {
        $u->do("LOCK TABLES log2 WRITE, talk2 READ");
    }

    # get count and then update.  this should be totally safe because we've either
    # locked the tables or we're in a transaction.
    my $ct = $u->selectrow_array(
        "SELECT COUNT(*) FROM talk2 FORCE INDEX (nodetype) WHERE "
            . "journalid=? AND nodetype='L' AND nodeid=? "
            . "AND state IN ('A','F') $sharedmode",
        undef, $u->{'userid'}, $jitemid
    );
    $u->do( "UPDATE log2 SET replycount=? WHERE journalid=? AND jitemid=?",
        undef, int($ct), $u->{'userid'}, $jitemid );
    print STDERR "Fixing replycount for $u->{'userid'}/$jitemid from $rp_count to $ct\n"
        if $LJ::DEBUG{'replycount_fix'};

    # now, commit or unlock as appropriate
    if ( $u->is_innodb ) {
        $u->commit;
    }
    else {
        $u->do("UNLOCK TABLES");
    }

    # mark it as fixed in memcache, so we don't do this again
    LJ::MemCache::add( $fix_key, 1, 60 );
    $unlock->();
    LJ::MemCache::set( $rp_memkey, int($ct) );
}

# LJ::Talk::load_comments($u, $remote, $nodetype, $nodeid, $opts)
#
# nodetype: "L" (for log) ... nothing else has been used
# noteid: the jitemid for log.
# opts keys:
#   thread -- jtalkid to thread from ($init->{'thread'} or $GET{'thread'} >> 8)
#   page -- $GET{'page'}
#   view -- $GET{'view'} (picks page containing view's ditemid)
#   flat -- boolean:  if set, threading isn't done, and it's just a flat chrono view
#   up -- [optional] hashref of user object who posted the thing being replied to
#         only used to make things visible which would otherwise be screened?
#   filter -- [optional] value of comments getarg (screened|frozen|visible)
#         used to hide comments not matching the specified type
#   out_error -- set by us if there's an error code:
#        nodb:  database unavailable
#        noposts:  no posts to load
#   out_pages:  number of pages
#   out_page:  page number being viewed
#   out_itemfirst:  first comment number on page (1-based, not db numbers)
#   out_itemlast:  last comment number on page (1-based, not db numbers)
#   out_pagesize:  size of each page
#   out_items:  number of total top level items
#   out_has_collpased:  set by us; 0 if no collapsed messages, 1 if there are
#
#   userpicref -- hashref to load userpics into, or undef to
#                 not load them.
#   userref -- hashref to load users into, keyed by userid
#   top-only -- boolean; if set, only load the top-level comments
#
# returns:
#   array of hashrefs containing keys:
#      - talkid (jtalkid)
#      - posterid (or zero for anon)
#      - userpost (string, or blank if anon)
#      - upost    ($u object, or undef if anon)
#      - datepost (mysql format)
#      - parenttalkid (or zero for top-level)
#      - parenttalkid_actual (set when the $flat mode is set, in which case parenttalkid is always faked to be 0)
#      - state ("A"=approved, "S"=screened, "D"=deleted stub)
#      - userpic number
#      - picid   (if userpicref AND userref were given)
#      - subject
#      - body
#      - props => { propname => value, ... }
#      - children => [ hashrefs like these ]
#      - _loaded => 1 (if fully loaded, subject & body)
#        unknown items will never be _loaded
#      - _show => {0|1}, if item is to be ideally shown (0 if deleted, screened, or filtered)
#      - showable_children - count of showable children for this comment
#      - hidden_child => {0|1}, if this comment is hidden by default
#      - hide_children => {0|1}, if this comment has its children hidden
#      - echi (explicit comment hierarchy indicator)
sub load_comments {
    my ( $u, $remote, $nodetype, $nodeid, $opts ) = @_;

    my $n       = $u->{'clusterid'};
    my $viewall = $opts->{viewall};

    my $posts = get_talk_data( $u, $nodetype, $nodeid );    # hashref, talkid -> talk2 row, or undef
    unless ($posts) {
        $opts->{'out_error'} = "nodb";
        return;
    }
    my %users_to_load;                                      # userid -> 1
    my @posts_to_load;                                      # talkid scalars
    my %children;                                           # talkid -> [ childenids+ ]

    my $uposterid = $opts->{'up'} ? $opts->{'up'}->{'userid'} : 0;

    my $post_count = 0;
    {
        my %showable_children;                              # $id -> $count

        foreach my $post ( sort { $b->{'talkid'} <=> $a->{'talkid'} } values %$posts ) {

            # kill the threading in flat mode
            if ( $opts->{'flat'} ) {
                $post->{'parenttalkid_actual'} = $post->{'parenttalkid'};
                $post->{'parenttalkid'}        = 0;
            }

            # see if we should ideally show it or not.  even if it's
            # zero, we'll still show it if it has any children (but we won't show content)
            my $state        = $post->{state} || '';
            my $should_show  = $state eq 'D' ? 0 : 1;    # no deleted comments
            my $parenttalkid = $post->{parenttalkid};
            unless ($viewall) {

                # first check to see if a filter has been requested
                my $poster    = LJ::load_userid( $post->{posterid} );
                my %filtermap = (
                    screened => sub { return $state eq 'S' },
                    frozen   => sub { return $state eq 'F' },
                    visible  => sub {
                        return 0 if $state eq 'S';
                        return 0 if $poster && $poster->is_suspended;

                        # no need to check if deleted, because $should_show does that for us

                        return 1;
                    },
                );
                if ( $should_show && $opts->{filter} && exists $filtermap{ $opts->{filter} } ) {
                    $should_show = $filtermap{ $opts->{filter} }->();
                }

                # then check for comment owner/journal owner
                $should_show = 0
                    if $should_show &&    # short circuit, and check the following conditions
                                          # only if we wanted to show in the first place
                        # can view if not screened, or if screened and some conditions apply
                    $state eq "S"
                    && !(
                    $remote
                    && (
                        $remote->userid == $uposterid        ||   # made in remote's journal
                        $remote->userid == $post->{posterid} ||   # made by remote
                        $remote->can_manage($u)              ||   # made in a journal remote manages
                        (
                            # remote authored the parent, and this comment is by an admin
                            exists $posts->{$parenttalkid}
                            && $posts->{$parenttalkid}->{posterid}
                            && $posts->{$parenttalkid}->{posterid} == $remote->userid
                            && $poster
                            && $poster->can_manage($u)
                        )
                    )
                    );
            }
            $post->{'_show'} = $should_show;
            $post_count += $should_show;

            # make any post top-level if it says it has a parent but it isn't
            # loaded yet which means either a) row in database is gone, or b)
            # somebody maliciously/accidentally made their parent be a future
            # post, which could result in an infinite loop, which we don't want.
            $post->{'parenttalkid'} = 0
                if $post->{'parenttalkid'} && !$posts->{ $post->{'parenttalkid'} };

            $post->{'children'} =
                [ map { $posts->{$_} } @{ $children{ $post->{'talkid'} } || [] } ];

            # increment the parent post's number of showable children,
            # which is our showability plus all those of our children
            # which were already computed, since we're working new to old
            # and children are always newer.
            # then, if we or our children are showable, add us to the child list
            my $sum = $should_show + ( $showable_children{ $post->{talkid} } || 0 );
            if ($sum) {
                $showable_children{ $post->{'parenttalkid'} } += $sum;
                unshift @{ $children{ $post->{'parenttalkid'} } }, $post->{'talkid'};

                # record the # of showable children for each comment (though
                # not for the post itself (0))
                if ( $post->{parenttalkid} ) {
                    $posts->{ $post->{parenttalkid} }->{'showable_children'} =
                        $showable_children{ $post->{'parenttalkid'} };
                }
            }

        }

        # explicit comment hierarchy indicator generation
        my $echi_display = '';
        $echi_display = $remote->prop("opt_echi_display") || '' if $remote;
        if ( !$opts->{flat} && $echi_display eq "Y" ) {

            my @alpha = ( "a" .. "z" );

            # all echi values are initially stored as numeric values; this
            # translates from the number to a..z, a[a..z]..z[a..z], etc.
            my $to_alpha = sub {
                my $num = shift;

                # this is 0-based, while the count is 1-based.
                $num--;
                my $retval = "";

                # prepend a third letter only if we have more than 702
                # comments (26^2 = 676, plus the initial 26 which don't
                # have a second letter = 702)
                if ( $num >= 702 ) {
                    $retval .= $alpha[ ( $num - 702 ) / 676 ];
                }
                if ( $num >= 26 ) {
                    $retval .= $alpha[ ( ( $num - 26 ) / 26 ) % 26 ];
                }
                $retval .= $alpha[ $num % 26 ];
                return $retval;
            };

            my $top_counter = 1;

            foreach my $post ( sort { $a->{'talkid'} <=> $b->{'talkid'} } values %$posts ) {
                next unless $post->{_show} || $post->{showable_children};

                # set the echi for this comment
                my $parentid = $post->{'parenttalkid'} || $post->{'parenttalkid_actual'} || 0;
                if ( $parentid && $posts->{$parentid} ) {
                    my $parent = $posts->{$parentid};
                    $post->{'echi_count'} = 0;
                    if ( !$parent->{'echi_count'} ) {
                        $parent->{'echi_count'} = 1;
                    }
                    else {
                        $parent->{'echi_count'} = $parent->{'echi_count'} + 1;
                    }
                    if ( !$parent->{'echi_type'} ) {
                        $parent->{'echi_type'} = 'N';
                    }
                    if ( $parent->{'echi_type'} eq 'N' ) {
                        $post->{'echi_type'} = 'A';
                        $post->{echi} = $parent->{echi} . $to_alpha->( $parent->{'echi_count'} );
                    }
                    else {
                        $post->{'echi_type'} = 'N';
                        $post->{echi}        = $parent->{echi} . $parent->{'echi_count'};
                    }
                }
                else {
                    $post->{echi}         = $top_counter++;
                    $post->{'echi_count'} = 0;
                    $post->{'echi_type'}  = 'N';
                }

                # Count number of non-whitespace characters in echi
                my $char_count = $post->{echi} =~ tr/a-zA-Z0-9//;

                # Add a whitespace every ten non-whitespace characters
                $post->{echi} = $post->{echi} . ' ' if ( $char_count % 10 == 0 );
            }
        }
    }

    # with a wrong thread number, silently default to the whole page
    my $thread = $opts->{'thread'} + 0;
    $thread = 0 unless $posts->{$thread};

    unless ( $thread || $children{$thread} ) {
        $opts->{'out_error'} = "noposts";
        return;
    }

    my $page_size       = $LJ::TALK_PAGE_SIZE    || 25;
    my $max_subjects    = $LJ::TALK_MAX_SUBJECTS || 200;
    my $threading_point = $LJ::TALK_THREAD_POINT || 50;

    # we let the page size initially get bigger than normal for awhile,
    # but if it passes threading_point, then everything's in page_size
    # chunks:
    $page_size = $threading_point if $post_count < $threading_point;

    my $top_replies = $thread ? 1 : scalar( @{ $children{$thread} } );
    my $pages       = int( $top_replies / $page_size );
    if ( $top_replies % $page_size ) { $pages++; }

    my @top_replies    = $thread ? ($thread) : @{ $children{$thread} };
    my $page_from_view = 0;
    if ( $opts->{'view'} && !$opts->{'page'} ) {

        # find top-level comment that this comment is under
        my $viewid = $opts->{'view'} >> 8;
        while ( $posts->{$viewid} && $posts->{$viewid}->{'parenttalkid'} ) {
            $viewid = $posts->{$viewid}->{'parenttalkid'};
        }
        for ( my $ti = 0 ; $ti < @top_replies ; ++$ti ) {
            if ( $posts->{ $top_replies[$ti] }->{'talkid'} == $viewid ) {
                $page_from_view = int( $ti / $page_size ) + 1;
                last;
            }
        }
    }
    my $page = int( $opts->{page} || 0 ) || $page_from_view || 1;
    $page = $page < 1 ? 1 : $page > $pages ? $pages : $page;

    my $itemfirst = $page_size * ( $page - 1 ) + 1;
    my $itemlast  = $page == $pages ? $top_replies : ( $page_size * $page );

    @top_replies = @top_replies[ $itemfirst - 1 .. $itemlast - 1 ];

    push @posts_to_load, @top_replies;

    # mark child posts of the top-level to load, deeper
    # and deeper until we've hit the page size.  if too many loaded,
    # just mark that we'll load the subjects;
    my @check_for_children = @posts_to_load;

    ## expand first reply to top-level comments
    ## %expand_children - list of comments, children of which are to expand
    my %expand_children;
    unless ( $opts->{'top-only'} ) {
        ## expand first reply to top-level comments
        ## %expand_children - list of comments, children of which are to expand
        %expand_children = map { $_ => 1 } @top_replies;
    }

    my ( @subjects_to_load, @subjects_ignored );

    # track if there are any collapsed messages being displayed
    my $has_collapsed = 0;

    while (@check_for_children) {
        my $cfc = shift @check_for_children;

        next unless defined $children{$cfc};
        foreach my $child ( @{ $children{$cfc} } ) {
            if ( !$opts->{'top-only'}
                && ( @posts_to_load < $page_size || $expand_children{$cfc} || $opts->{expand_all} )
                )
            {
                push @posts_to_load, $child;
                ## expand only the first child, then clear the flag
                delete $expand_children{$cfc};
            }
            else {
                $has_collapsed = 1;
                if ( $opts->{'top-only'} ) {
                    $posts->{$child}->{'hidden_child'} = 1;
                }
                if ( @subjects_to_load < $max_subjects ) {
                    push @subjects_to_load, $child;
                }
                else {
                    push @subjects_ignored, $child;
                }
            }
            push @check_for_children, $child;
        }
    }

    $opts->{'out_pages'}         = $pages;
    $opts->{'out_page'}          = $page;
    $opts->{'out_itemfirst'}     = $itemfirst;
    $opts->{'out_itemlast'}      = $itemlast;
    $opts->{'out_pagesize'}      = $page_size;
    $opts->{'out_items'}         = $top_replies;
    $opts->{'out_has_collapsed'} = $has_collapsed;

    # load text of posts
    my ( $posts_loaded, $subjects_loaded );
    $posts_loaded = LJ::get_talktext2( $u, @posts_to_load );
    $subjects_loaded = LJ::get_talktext2( $u, { 'onlysubjects' => 1 }, @subjects_to_load )
        if @subjects_to_load;

    # preload props
    my @ids_to_preload = @posts_to_load;
    push @ids_to_preload, @subjects_to_load;
    my @to_preload = ();
    foreach my $jtalkid (@ids_to_preload) {
        push @to_preload, LJ::Comment->new( $u, jtalkid => $jtalkid );
    }
    LJ::Comment->preload_props( $u, @to_preload );

    foreach my $talkid (@posts_to_load) {
        if ( $opts->{'top-only'} ) {
            $posts->{$talkid}->{'hide_children'} = 1;
        }
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'_loaded'}                    = 1;
        $posts->{$talkid}->{'subject'}                    = $posts_loaded->{$talkid}->[0];
        $posts->{$talkid}->{'body'}                       = $posts_loaded->{$talkid}->[1];
        $users_to_load{ $posts->{$talkid}->{'posterid'} } = 1;
        if ( $opts->{'top-only'} ) {
            $posts->{$talkid}->{'hide_children'} = 1;
        }
    }
    foreach my $talkid (@subjects_to_load) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'subject'} = $subjects_loaded->{$talkid}->[0];
        $users_to_load{ $posts->{$talkid}->{'posterid'} } ||= 0.5;    # only care about username
    }
    foreach my $talkid (@subjects_ignored) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'subject'} = "...";
        $users_to_load{ $posts->{$talkid}->{'posterid'} } ||= 0.5;    # only care about username
    }

    # load meta-data
    {
        my %props;
        LJ::load_talk_props2( $u->{'userid'}, \@posts_to_load, \%props );
        foreach ( keys %props ) {
            next unless $posts->{$_}->{'_show'};
            $posts->{$_}->{'props'} = $props{$_};
        }
    }

    foreach (@posts_to_load) {
        if ( $posts->{$_}->{'props'}->{'unknown8bit'} ) {
            LJ::item_toutf8( $u, \$posts->{$_}->{'subject'}, \$posts->{$_}->{'body'}, {} );
        }
    }

    # load users who posted
    delete $users_to_load{0};
    my %up = ();
    if (%users_to_load) {
        LJ::load_userids_multiple( [ map { $_, \$up{$_} } keys %users_to_load ] );

        # fill in the 'userpost' member on each post being shown
        while ( my ( $id, $post ) = each %$posts ) {
            my $up = $up{ $post->{'posterid'} };
            next unless $up;
            $post->{'upost'}    = $up;
            $post->{'userpost'} = $up->{'user'};
        }
    }

    # optionally give them back user refs
    if ( ref( $opts->{userref} ) eq "HASH" ) {
        my %userpics = ();

        # copy into their ref the users we've already loaded above.
        while ( my ( $k, $v ) = each %up ) {
            $opts->{userref}->{$k} = $v;
        }

        # optionally load userpics
        if ( ref( $opts->{userpicref} ) eq "HASH" ) {
            my @load_pic;
            foreach my $talkid (@posts_to_load) {
                my $post = $posts->{$talkid};
                my $pu   = $opts->{userref}->{ $post->{posterid} };
                my ( $id, $kw );
                if ( $pu && $pu->userpic_have_mapid ) {
                    my $mapid;
                    if ( $post->{props} && $post->{props}->{picture_mapid} ) {
                        $mapid = $post->{props}->{picture_mapid};
                    }
                    $kw = $pu ? $pu->get_keyword_from_mapid($mapid) : undef;
                    $id = $pu ? $pu->get_picid_from_mapid($mapid)   : undef;
                }
                else {
                    if ( $post->{props} && $post->{props}->{picture_keyword} ) {
                        $kw = $post->{props}->{picture_keyword};
                    }
                    $id = $pu ? $pu->get_picid_from_keyword($kw) : undef;
                }
                $post->{picid} = $id;
                $post->{pickw} = $kw;
                push @load_pic, [ $pu, $id ]
                    if defined $id;
            }
            load_userpics( $opts->{userpicref}, \@load_pic );
        }
    }

    # make singletons for the returned comments
    my $make_comment_singleton = sub {
        my ( $self, $jtalkid, $row ) = @_;
        return 1 unless $nodetype eq 'L';

        # at this point we have data for this comment loaded in memory
        # -- instantiate an LJ::Comment object as a singleton and absorb
        #    that data into the object
        my $comment = LJ::Comment->new( $u, jtalkid => $jtalkid );

        # add important info to row
        $row->{nodetype} = $nodetype;
        $row->{nodeid}   = $nodeid;
        $comment->absorb_row(%$row);

        $comment->{childids}         = $row->{children};
        $comment->{_loaded_childids} = 1;

        if ( $row->{children} && scalar @{ $row->{children} } ) {
            foreach my $child ( @{ $row->{children} } ) {
                $self->( $self, $child, $posts->{$child} );
            }
        }
        return 1;
    };

    foreach my $talkid (@top_replies) {
        $make_comment_singleton->( $make_comment_singleton, $talkid, $posts->{$talkid} );
    }

    return map { $posts->{$_} } @top_replies;
}

# <LJFUNC>
# name: LJ::Talk::load_userpics
# des: Loads a bunch of userpics at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids.
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
# </LJFUNC>
sub load_userpics {
    my ( $upics, $idlist ) = @_;

    return undef unless ref $idlist eq 'ARRAY' && $idlist->[0];

    # $idlist needs to be an arrayref of arrayrefs,
    # HOWEVER, there's a special case where it can be
    # an arrayref of 2 items:  $u (which is really an arrayref)
    # as well due to 'fields' and picid which is an integer.
    #
    # [$u, $picid] needs to map to [[$u, $picid]] while allowing
    # [[$u1, $picid1], [$u2, $picid2], [etc...]] to work.
    if ( scalar @$idlist == 2 && !ref $idlist->[1] ) {
        $idlist = [$idlist];
    }

    my @load_list;
    foreach my $row ( @{$idlist} ) {
        my ( $u, $id ) = @$row;
        next unless ref $u && defined $id;

        if ( $LJ::CACHE_USERPIC{$id} ) {
            $upics->{$id} = $LJ::CACHE_USERPIC{$id};
        }
        elsif ( $id + 0 ) {
            push @load_list, [ $u, $id + 0 ];
        }
    }
    return unless @load_list;

    if (@LJ::MEMCACHE_SERVERS) {
        my @mem_keys = map { [ $_->[1], "userpic.$_->[1]" ] } @load_list;
        my $mem      = LJ::MemCache::get_multi(@mem_keys) || {};
        while ( my ( $k, $v ) = each %$mem ) {
            next unless $v && $k =~ /(\d+)/;
            my $id = $1;
            $upics->{$id} = LJ::MemCache::array_to_hash( "userpic", $v );
        }
        @load_list = grep { !$upics->{ $_->[1] } } @load_list;
        return unless @load_list;
    }

    my %db_load;
    foreach my $row (@load_list) {

        # ignore users on clusterid 0
        next unless $row->[0]->{clusterid};

        push @{ $db_load{ $row->[0]->{clusterid} } }, $row;
    }

    foreach my $cid ( keys %db_load ) {
        my $dbcr = LJ::get_cluster_def_reader($cid);
        unless ($dbcr) {
            print STDERR "Error: LJ::Talk::load_userpics unable to get handle; cid = $cid\n";
            next;
        }

        my ( @bindings, @data );
        foreach my $row ( @{ $db_load{$cid} } ) {
            push @bindings, "(userid=? AND picid=?)";
            push @data, ( $row->[0]->{userid}, $row->[1] );
        }
        next unless @data && @bindings;

        my $sth =
            $dbcr->prepare( "SELECT userid, picid, width, height, fmt, state, "
                . "       UNIX_TIMESTAMP(picdate) AS 'picdate', location, flags "
                . "FROM userpic2 WHERE "
                . join( ' OR ', @bindings ) );
        $sth->execute(@data);

        while ( my $ur = $sth->fetchrow_hashref ) {
            my $id = delete $ur->{'picid'};
            $upics->{$id} = $ur;

            # force into numeric context so they'll be smaller in memcache:
            foreach my $k (qw(userid width height flags picdate)) {
                $ur->{$k} += 0;
            }
            $ur->{location} = uc( substr( $ur->{location} || '', 0, 1 ) );

            $LJ::CACHE_USERPIC{$id} = $ur;
            LJ::MemCache::set( [ $id, "userpic.$id" ],
                LJ::MemCache::hash_to_array( "userpic", $ur ) );
        }
    }
}

# XXX these strings should be in talk, but moving them means we have
# to retranslate.  so for now we're just gonna put it off.
my $SC = '/talkpost_do.bml';

sub talkform {

    # Takes a hashref with the following keys / values:
    # remote:      optional remote u object
    # journalu:    prequired journal u object
    # parpost:     parent post object
    # replyto:     init->replyto
    # ditemid:     init->ditemid
    # form:        optional full form hashref. Empty if reply page was opened via
    #              direct link instead of partial form submission.
    # do_captcha:  optional toggle for creating a captcha challenge
    # errors:      optional error arrayref
    my $opts = shift;
    return "Invalid talkform values." unless ref $opts eq 'HASH';

    my ( $remote, $journalu, $parpost, $form ) =
        map { $opts->{$_} } qw(remote journalu parpost form);

    my $editid = $form->{edit} ? $form->{edit} : 0;
    my $comment;
    if ($editid) {
        $comment = LJ::Comment->new( $journalu, dtalkid => $editid );
        return "Cannot load comment information." unless $comment;
    }

    my $subjecticons    = LJ::Talk::get_subjecticons();
    my @subjecticon_ids = ('none');
    foreach my $sublist ( $subjecticons{lists}->{sm}, $subjecticons{lists}->{md} ) {
        push( @subjecticon_ids, map { $_->{id} } @$sublist );
    }

    my $entry    = LJ::Entry->new( $journalu, ditemid => $opts->{ditemid} );
    my @userpics = LJ::icons_for_remote($remote);

    my $basesubject = $form->{subject} || "";
    if ( !$editid && $opts->{replyto} && !$basesubject && $parpost->{'subject'} ) {
        $basesubject = $parpost->{'subject'};
        $basesubject =~ s/^Re:\s*//i;
        $basesubject = "Re: $basesubject";
    }

    my $screening = LJ::Talk::screening_level( $journalu, $opts->{ditemid} >> 8 ) // '';

    my $default_usertype = '';    # One of anonymous, openid, openid_cookie, cookieuser, user.
    if ( $form->{usertype} ) {

        # Partial form was submitted; pick up where we left off.
        $default_usertype = $form->{usertype};

        # EXCEPT: there's an annoying special behavior with the "cookieuser"
        # usertype. It can survive certain partial form submissions (like the
        # "More options" button), but as soon as it passes through
        # LJ::Talk::Post::init() (which is when we find out whether a captcha is
        # needed, for example), it gets munged into the "user" type and a few
        # other properties get added. So if it's "user", we have to check those
        # other properties to see whether it was actually meant to be
        # "cookieuser". (Why not just preserve "cookieuser" through init()?
        # Because an unknowable amount of things check for usertype eq user, and
        # I'm not ready to hunt them all down yet.)
        if (   $form->{usertype} eq 'user'
            && $form->{userpost}
            && $form->{cookieuser}
            && $form->{userpost} eq $form->{cookieuser} )
        {
            $default_usertype = 'cookieuser';
        }
    }
    elsif ($remote) {

        # If logged-in user isn't allowed to comment we end up with no default,
        # which seems correct.
        if ( $remote->openid_identity ) {
            $default_usertype = 'openid_cookie';
        }
        else {
            $default_usertype = 'cookieuser';
        }
    }
    elsif ( $journalu->{'opt_whocanreply'} eq "all" ) {
        $default_usertype = 'anonymous';
    }
    else {
        $default_usertype = 'user';
    }

    # Variables for talkform.tt
    my $template_args = {
        hidden_form_elements => '',
        form_url             => LJ::create_url( '/talkpost_do', host => $LJ::DOMAIN_WEB ),
        errors               => $opts->{errors},
        create_link          => '',
        subjecticon_ids      => \@subjecticon_ids,

        public_entry     => $entry->security eq 'public',
        default_usertype => $default_usertype,

        comment => {
            editid      => $editid,
            editreason  => $comment ? $comment->edit_reason : '',
            oidurl      => $form->{oidurl},
            oiddo_login => $form->{oiddo_login},
            user        => $form->{userpost}
                || $form->{cookieuser},
            body        => $form->{body},
            subject     => $basesubject,
            subjecticon => $form->{subjecticon}
                || 'none',    # a subjecticon ID
            preformatted    => $form->{prop_opt_preformatted},
            admin_post      => $form->{prop_admin_post},
            current_icon_kw => $form->{prop_picture_keyword},
            current_icon => LJ::Userpic->new_from_keyword( $remote, $form->{prop_picture_keyword} )
            ,                 # not yet used, but later...
        },

        captcha => $opts->{do_captcha}
        ? {
            type => $journalu->captcha_type,
            html => DW::Captcha->new( undef, want => $journalu->captcha_type )->print,
            }
        : 0,

        length_limit   => LJ::CMAX_COMMENT,
        can_checkspell => $LJ::SPELLER ? 1 : 0,

        remote => $remote
        ? {
            icons_url => $remote ? $remote->allpics_base : '',
            icons     => \@userpics,

            user            => $remote->user,
            display_name    => LJ::ehtml( $remote->display_name ),
            ljuser          => $remote->ljuser_display,
            openid_identity => $remote->openid_identity,

            allowed => !$journalu->has_banned($remote)
                && (
                   $journalu->{opt_whocanreply} eq 'all'
                || ( $journalu->{opt_whocanreply} eq 'reg' && !$remote->openid_identity )
                || (   $journalu->{opt_whocanreply} eq 'reg'
                    && $remote->openid_identity
                    && ( $remote->is_validated || $journalu->trusts($remote) ) )
                || ( $journalu->{opt_whocanreply} eq 'friends'
                    && !$journalu->does_not_allow_comments_from($remote) )
                ),
            banned   => $journalu->has_banned($remote),
            screened => (
                       $journalu->has_autoscreen($remote)
                    || $screening eq 'A'
                    || ( $screening eq 'R' && !$remote->is_validated )
                    || ( $screening eq 'F' && !$journalu->trusts($remote) )
            ),

            can_unscreen_parent => (
                       $parpost->{state}
                    && $parpost->{state} eq "S"
                    && LJ::Talk::can_unscreen( $remote, $journalu, $entry->poster )
            ),
            can_manage_community => $journalu->is_community
                && $remote
                && $remote->can_manage($journalu),

            can_use_iconbrowser    => $remote->can_use_userpic_select,
            iconbrowser_metatext   => $remote->iconbrowser_metatext ? "true" : "false",
            iconbrowser_smallicons => $remote->iconbrowser_smallicons ? "true" : "false",
            }
        : 0,
        journal => {
            user => $journalu->{user},

            is_iplogging => $journalu->opt_logcommentips eq 'A' ? 'all'
            : $journalu->opt_logcommentips eq 'S' ? 'anon'
            : 0,
            is_linkstripped => !$remote
                || ( $remote && $remote->is_identity && !$journalu->trusts_or_has_member($remote) ),
            is_community => $journalu->is_community,

            screens_anon       => $screening,
            screens_non_access => $screening eq 'F' || $screening eq 'A',
            screens_all        => $screening eq 'A',

            allows_anon       => $journalu->{opt_whocanreply} eq "all",
            allows_non_access => $journalu->{opt_whocanreply} eq "all"
                || $journalu->{opt_whocanreply} eq "reg",
        },

        help_icon               => sub { LJ::help_icon_html(@_) },
        ejs                     => sub { return LJ::ejs(@_) },
        print_subjecticon_by_id => sub { return LJ::Talk::print_subjecticon_by_id(@_) },
    };

    # make sure journal isn't locked
    return
        "Sorry, this journal is locked and comments cannot be posted to it or edited at this time."
        if $journalu->is_locked;

    # check max comments only if posting a new comment (not when editing)
    unless ($editid) {
        my $jitemid = $opts->{'ditemid'} >> 8;
        return "Sorry, this entry already has the maximum number of comments allowed."
            if LJ::Talk::Post::over_maxcomments( $journalu, $jitemid );
    }

    # Login challenge/response
    $template_args->{'hidden_form_elements'} .= LJ::html_hidden(

        # 15 minute auth token
        { 'name' => 'chal',     'id' => 'login_chal',     'value' => LJ::challenge_generate(900) },
        { 'name' => 'response', 'id' => 'login_response', 'value' => '' }
    );

    $opts->{styleopts} ||= LJ::viewing_style_opts(%$form);
    my $stylemineuri =
        %{ $opts->{styleopts} } ? LJ::viewing_style_args( %{ $opts->{styleopts} } ) . "&" : "";
    my $basepath = $entry->url . "?" . $stylemineuri;

    # hidden values
    $template_args->{'hidden_form_elements'} .= LJ::html_hidden(
        "replyto", $opts->{replyto},
        "parenttalkid", ( $opts->{replyto} + 0 ),
        "itemid",   $opts->{ditemid},
        "journal",  $journalu->{'user'},
        "basepath", $basepath,
        "dtid",     $opts->{dtid},
        "editid",   $editid,
        %{ $opts->{styleopts} },
    );

    # rate limiting challenge
    {
        my ( $time, $secret ) = LJ::get_secret();
        my $rchars = LJ::rand_chars(20);
        my $chal   = $opts->{ditemid} . "-$journalu->{userid}-$time-$rchars";
        my $res    = Digest::MD5::md5_hex( $secret . $chal );
        $template_args->{'hidden_form_elements'} .= LJ::html_hidden( "chrp1", "$chal-$res" );
    }

    # special link to create an account
    if ( !$remote || $remote->openid_identity ) {
        $template_args->{'create_link'} =
            LJ::Hooks::run_hook( "override_create_link_on_talkpost_form", $journalu ) || '';
    }

    return DW::Template->template_string( 'journal/talkform.tt', $template_args );
}

sub icon_dropdown {
    my ( $remote, $selected ) = @_;
    $selected ||= "";

    my %res;
    if ($remote) {
        LJ::do_request(
            {
                mode      => "login",
                ver       => $LJ::PROTOCOL_VER,
                user      => $remote->{'user'},
                getpickws => 1,
            },
            \%res,
            { "noauth" => 1, "userid" => $remote->{'userid'} }
        );
    }

    my $ret = "";
    if ( $res{pickw_count} ) {
        $ret .= BML::ml(
            '/talkpost.bml.label.picturetouse2',
            {
                aopts => "href='" . $remote->allpics_base . "'"
            }
        ) . " ";

        my @pics;
        foreach my $i ( 1 ... $res{pickw_count} ) {
            push @pics, $res{"pickw_$i"};
        }
        @pics = sort { lc($a) cmp lc($b) } @pics;
        $ret .= LJ::html_select(
            {
                name     => 'prop_picture_keyword',
                selected => $selected,
                id       => 'prop_picture_keyword'
            },
            ( "", $BML::ML{'/talkpost.bml.opt.defpic'}, map { ( $_, $_ ) } @pics )
        );

        # userpic browse button
        if ( $remote && $remote->can_use_userpic_select ) {
            my $metatext   = $remote->iconbrowser_metatext   ? "true" : "false";
            my $smallicons = $remote->iconbrowser_smallicons ? "true" : "false";
            $ret .=
qq{<input type="button" id="lj_userpicselect" value="Browse" data-iconbrowser-metatext="$metatext" data-iconbrowser-smallicons="$smallicons"/>};
        }

        # random icon button - hidden for non-JS
        $ret .= "<input type='button' class='ljhidden' id='randomicon' value='"
            . BML::ml('/talkpost.bml.userpic.random2') . "'/>";

        $ret .= LJ::help_icon_html( "userpics", " " );
    }

    return $ret;
}

# load the javascript libraries for the icon browser
# args: names of any additional files to load
# returns: full list of arguments to pass to LJ::need_res
sub init_iconbrowser_js {
    my ( $jquery, @additional ) = @_;

    my @list = $jquery
        ? (
        { group => 'jquery' },

        # base libraries
        'js/jquery/jquery.ui.core.js',
        'js/jquery/jquery.ui.widget.js',
        'stc/jquery/jquery.ui.core.css',

        # for the formatting of the icon selector popup
        'js/jquery/jquery.ui.dialog.js',
        'stc/jquery/jquery.ui.dialog.css',

        # logic for the icon selector
        'js/jquery.iconselector.js',
        'stc/jquery.iconselector.css',

        # additional files from arguments
        @additional,
        )
        : (
        # base libraries
        'js/6alib/core.js',
        'js/6alib/dom.js',
        'js/6alib/json.js',

        # for the formatting of the icon selector popup
        'js/6alib/template.js',
        'js/6alib/ippu.js',
        'js/lj_ippu.js',

        # logic for the icon selector
        'js/userpicselect.js',

        # fetching the userpic information
        'js/6alib/httpreq.js',
        'js/6alib/hourglass.js',

        # autocomplete
        'js/6alib/inputcomplete.js',
        'stc/ups.css',

        # selecting an icon by clicking on a row
        'js/6alib/datasource.js',
        'js/6alib/selectable_table.js',

        # additional files from arguments
        @additional,
        );

    return @list;
}

# convenience/deduplication function for QR, cut tag, & icon browser JS loading
# args: hash of opts to determine which JS files to load (iconbrowser, siteskin, lastn, noqr)
# returns: nothing, just calls need_res
sub init_s2journal_js {
    my %opts = @_;

    # load for everywhere you can reply (ReplyPage, lastn, AND entries)
    LJ::need_res(
        { group => "jquery" }, qw(
            js/jquery.quotebutton.js
            )
    );

    # load for quick reply (every view except ReplyPage)
    LJ::need_res(
        { group => "jquery" }, qw(
            js/jquery/jquery.ui.core.js
            stc/jquery/jquery.ui.core.css
            js/jquery/jquery.ui.widget.js
            js/jquery.quickreply.js
            js/jquery.threadexpander.js
            stc/css/components/quick-reply.css
            )
    ) unless $opts{noqr};

    # load for userpicselect
    LJ::need_res( init_iconbrowser_js(1) ) if $opts{iconbrowser};

    # if we're using the site skin, don't override the jquery-ui theme,
    # as that's already included
    LJ::need_res(
        { group => "jquery" }, qw(
            stc/jquery/jquery.ui.theme.smoothness.css
            )
    ) unless $opts{siteskin};

    # load for ajax cuttag - again, only needed on lastn-type pages
    LJ::need_res('js/cuttag-ajax.js') if $opts{lastn};
    LJ::need_res(
        { group => "jquery" }, qw(
            js/jquery/jquery.ui.widget.js
            js/jquery.cuttag-ajax.js
            )
    ) if $opts{lastn};
}

# convenience function for keyboard shortcuts
# args: $remote and $p for adding javascript to header
# returns: nothing, just calls need_res
sub init_s2journal_shortcut_js {
    my ( $remote, $p ) = @_;

    # skip everything if there's no remote user, or if neither opt_shortcuts
    # nor opt_shortcuts_touch is set.
    return
        unless $remote
        && ( $remote->prop("opt_shortcuts") || $remote->prop("opt_shortcuts_touch") );

    my $connect_string = "";

    LJ::need_res( { group => "jquery" }, "js/shortcuts.js" );
    LJ::need_res( { group => "jquery" }, "js/jquery.shortcuts.nextentry.js" );

    $p->{'head_content'} .= "  <script type='text/javascript'>\n  var dw_shortcuts = {\n";
    if ( $remote->prop("opt_shortcuts") ) {
        LJ::need_res( { group => "jquery" }, "js/mousetrap.js" );
        $p->{'head_content'} .= "    keyboard: {\n";

        my $nextKey = $remote->prop("opt_shortcuts_next");
        my $prevKey = $remote->prop("opt_shortcuts_prev");
        $p->{'head_content'} .=
            "      nextEntry: '$nextKey',\n      prevEntry: '$prevKey'\n    }\n";
        $connect_string = ",";
    }
    if ( $remote->prop("opt_shortcuts_touch") ) {
        LJ::need_res( { group => "jquery" }, "js/jquery.touchSwipe.js" );
        my $nextTouch = $remote->prop("opt_shortcuts_touch_next");
        my $prevTouch = $remote->prop("opt_shortcuts_touch_prev");
        $p->{'head_content'} .=
"$connect_string\n    touch: {\n      nextEntry: '$nextTouch',\n      prevEntry: '$prevTouch'\n    }\n";
    }
    $p->{'head_content'} .= "  };\n  </script>\n";
}

# <LJFUNC>
# name: LJ::record_anon_comment_ip
# class: web
# des: Records the IP address of an anonymous comment.
# args: journalu, jtalkid, ip
# des-journalu: User object of journal comment was posted in.
# des-jtalkid: ID of this comment.
# des-ip: IP address of the poster.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub record_anon_comment_ip {
    my ( $journalu, $jtalkid, $ip ) = @_;
    $journalu = LJ::want_user($journalu);
    $jtalkid += 0;
    return 0 unless LJ::isu($journalu) && $jtalkid && $ip;

    $journalu->do(
"INSERT INTO tempanonips (reporttime, journalid, jtalkid, ip) VALUES (UNIX_TIMESTAMP(),?,?,?)",
        undef, $journalu->{userid}, $jtalkid, $ip
    );
    return 0 if $journalu->err;
    return 1;
}

# <LJFUNC>
# name: LJ::mark_comment_as_spam
# class: web
# des: Copies a comment into the global [dbtable[spamreports]] table.
# args: journalu, jtalkid
# des-journalu: User object of journal comment was posted in.
# des-jtalkid: ID of this comment.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub mark_comment_as_spam {
    my ( $journalu, $jtalkid ) = @_;
    $journalu = LJ::want_user($journalu);
    $jtalkid += 0;
    return 0 unless $journalu && $jtalkid;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh  = LJ::get_db_writer();

    # step 1: get info we need
    my $row  = LJ::Talk::get_talk2_row( $dbcr, $journalu->{userid}, $jtalkid );
    my $temp = LJ::get_talktext2( $journalu, $jtalkid );
    my ( $subject, $body, $posterid ) =
        ( $temp->{$jtalkid}[0], $temp->{$jtalkid}[1], $row->{posterid} );
    return 0 unless ( $body && $body ne '' );

    # can't mark your own comments as spam.
    return 0 if $posterid && $posterid == $journalu->id;

    # can't mark comments as spam if sysbanned
    return 0 if LJ::sysban_check( 'spamreport', $journalu->user );

    # step 2a: if it's a suspended user, don't add, but pretend that we were successful
    if ($posterid) {
        my $posteru = LJ::want_user($posterid);
        return 1 if $posteru->is_suspended;
    }

 # step 2b: if it was an anonymous comment, attempt to get comment IP to make some use of the report
    my $ip;
    unless ($posterid) {
        $ip = $dbcr->selectrow_array( 'SELECT ip FROM tempanonips WHERE journalid=? AND jtalkid=?',
            undef, $journalu->{userid}, $jtalkid );
        return 0 if $dbcr->err;

        # we want to fail out if we have no IP address and this is anonymous, because otherwise
        # we have a completely useless spam report.  pretend we were successful, too.
        return 1 unless $ip;

        # we also want to log this attempt so that we can do some throttling
        my $rates = LJ::MemCache::get("spamreports:anon:$ip") || $RATE_DATAVER;
        $rates .= pack( "N", time );
        LJ::MemCache::set( "spamreports:anon:$ip", $rates );
    }

    my %props;
    LJ::load_talk_props2( $dbcr, $journalu->{userid}, [$jtalkid], \%props );

    # step 3: insert into spamreports
    $dbh->do(
'INSERT INTO spamreports (reporttime, posttime, ip, journalid, posterid, subject, body, client) '
            . 'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, ?, ?)',
        undef,
        $row->{datepost},
        $ip,
        $journalu->{userid},
        $posterid,
        $subject,
        $body,
        $props{$jtalkid}->{useragent}
    );
    return 0 if $dbh->err;
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::get_talk2_row
# class: web
# des: Gets a row of data from [dbtable[talk2]].
# args: dbcr, journalid, jtalkid
# des-dbcr: Database handle to read from.
# des-journalid: Journal id that comment is posted in.
# des-jtalkid: Journal talkid of comment.
# returns: Hashref of row data, or undef on error.
# </LJFUNC>
sub get_talk2_row {
    my ( $dbcr, $journalid, $jtalkid ) = @_;
    return $dbcr->selectrow_hashref(
        'SELECT journalid, jtalkid, nodetype, nodeid, parenttalkid, '
            . '       posterid, datepost, state '
            . 'FROM talk2 WHERE journalid = ? AND jtalkid = ?',
        undef,
        $journalid + 0,
        $jtalkid + 0
    );
}

# <LJFUNC>
# name: LJ::Talk::get_talk2_row_multi
# class: web
# des: Gets multiple rows of data from [dbtable[talk2]].
# args: items
# des-items: Array of arrayrefs; each arrayref: [ journalu, jtalkid ].
# returns: Array of hashrefs of row data, or undef on error.
# </LJFUNC>
sub get_talk2_row_multi {
    my (@items) = @_;    # [ journalu, jtalkid ], ...
    croak("invalid items for get_talk2_row_multi")
        if grep { !LJ::isu( $_->[0] ) || @$_ != 2 } @items;

    # what do we need to load per-journalid
    my %need    = ();    # journalid => { jtalkid => 1, ... }
    my %have    = ();    # journalid => { jtalkid => $row_ref, ... }
    my %cluster = ();    # cid => { jid => journalu, jid => journalu }

    # first, what is in memcache?
    my @keys = ();
    foreach my $it (@items) {
        my ( $journalu, $jtalkid ) = @$it;

        # can't load comments in purged users' journals
        next if $journalu->is_expunged;

        my $cid = $journalu->clusterid;
        my $jid = $journalu->id;

        # we need this for now
        $need{$jid}->{$jtalkid} = 1;

        # which cluster is this user on?
        $cluster{$cid}->{$jid} = $journalu;

        push @keys, LJ::Talk::make_talk2row_memkey( $jid, $jtalkid );
    }

    # return an array of rows preserving order in which they were requested
    my $ret = sub {
        my @ret = ();
        foreach my $it (@items) {
            my ( $journalu, $jtalkid ) = @$it;
            push @ret, $have{ $journalu->id }->{$jtalkid};
        }

        return @ret;
    };

    my $mem = LJ::MemCache::get_multi(@keys);
    if ($mem) {
        while ( my ( $key, $array ) = each %$mem ) {
            my ( undef, $jid, $jtalkid ) = split( ":", $key );
            my $row = LJ::MemCache::array_to_hash( "talk2row", $array );
            next unless $row;

            # add in implicit keys:
            $row->{journalid} = $jid;
            $row->{jtalkid}   = $jtalkid;

            # update our needs
            $have{$jid}->{$jtalkid} = $row;
            delete $need{$jid}->{$jtalkid};
            delete $need{$jid} unless %{ $need{$jid} };
        }

        # was everything in memcache?
        return $ret->() unless %need;
    }

    # uh oh, we have things to retrieve from the db!
CLUSTER:
    foreach my $cid ( keys %cluster ) {

        # build up a valid where clause for this cluster's select
        my @vals  = ();
        my @where = ();
        foreach my $journalu ( values %{ $cluster{$cid} } ) {
            my $jid      = $journalu->id;
            my @jtalkids = keys %{ $need{$jid} };
            next unless @jtalkids;

            my $bind = join( ",", map { "?" } @jtalkids );
            push @where, "(journalid=? AND jtalkid IN ($bind))";
            push @vals, $jid => @jtalkids;
        }

        # is there anything to actually query for this cluster?
        next CLUSTER unless @vals;

        my $dbcr = LJ::get_cluster_reader($cid)
            or die "unable to get cluster reader: $cid";

        my $where = join( " OR ", @where );
        my $sth =
            $dbcr->prepare( "SELECT journalid, jtalkid, nodetype, nodeid, parenttalkid, "
                . "       posterid, datepost, state "
                . "FROM talk2 WHERE $where" );
        $sth->execute(@vals);

        while ( my $row = $sth->fetchrow_hashref ) {
            my $jid     = $row->{journalid};
            my $jtalkid = $row->{jtalkid};

            # update our needs
            $have{$jid}->{$jtalkid} = $row;
            delete $need{$jid}->{$jtalkid};
            delete $need{$jid} unless %{ $need{$jid} };

            # update memcache
            LJ::Talk::add_talk2row_memcache( $jid, $jtalkid, $row );
        }
    }

    return $ret->();
}

sub make_talk2row_memkey {
    my ( $jid, $jtalkid ) = @_;
    return [ $jid, join( ":", "talk2row", $jid, $jtalkid ) ];
}

sub add_talk2row_memcache {
    my ( $jid, $jtalkid, $row ) = @_;

    my $memkey  = LJ::Talk::make_talk2row_memkey( $jid, $jtalkid );
    my $exptime = 60 * 30;
    my $array   = LJ::MemCache::hash_to_array( "talk2row", $row );

    return LJ::MemCache::add( $memkey, $array, $exptime );
}

sub invalidate_talk2row_memcache {
    my ( $jid, @jtalkids ) = @_;

    foreach my $jtalkid (@jtalkids) {
        my $memkey = [ $jid, "talk2row:$jid:$jtalkid" ];
        LJ::MemCache::delete($memkey);
    }

    return 1;
}

# get a comment count for a journal entry.
sub get_replycount {
    my ( $ju, $jitemid ) = @_;
    $jitemid += 0;
    return undef unless $ju && $jitemid;

    my $memkey = [ $ju->{'userid'}, "rp:$ju->{'userid'}:$jitemid" ];
    my $count  = LJ::MemCache::get($memkey);
    return $count if $count;

    my $dbcr = LJ::get_cluster_def_reader($ju);
    return unless $dbcr;

    $count =
        $dbcr->selectrow_array( "SELECT replycount FROM log2 WHERE " . "journalid=? AND jitemid=?",
        undef, $ju->{'userid'}, $jitemid );
    LJ::MemCache::add( $memkey, $count );
    return $count;
}

# get the total amount of screened comments on the given journal entry
sub get_screenedcount {
    my ( $ju, $jitemid ) = @_;
    $jitemid += 0;
    return undef unless $ju && $jitemid;

    my $memkey = [ $ju->{userid}, "screenedcount:$ju->{userid}:$jitemid", 60 * 30 ];
    my $count  = LJ::MemCache::get($memkey);
    return $count if $count;

    my $dbcr = LJ::get_cluster_def_reader($ju);
    return unless $dbcr;

    $count = $dbcr->selectrow_array(
        "SELECT COUNT(jtalkid) FROM talk2 WHERE " . "journalid=? AND nodeid=? AND state='S'",
        undef, $ju->{userid}, $jitemid );
    LJ::MemCache::add( $memkey, $count );
    return $count;
}

sub comment_htmlid {
    my $id = shift or return '';
    return "cmt$id";
}

sub comment_anchor {
    my $id = shift or return '';
    return "#cmt$id";
}

sub treat_as_anon {
    my ( $pu, $u ) = @_;
    return 1 unless LJ::isu($pu);        # anonymous is not OK
    return 0 unless $pu->is_identity;    # OK unless OpenID
                                         # if OpenID, not OK unless they're granted access
    return LJ::isu($u) ? !$u->trusts_or_has_member($pu) : 1;
}

sub format_eventtime {
    my ( $etime, $u ) = @_;
    $etime ||= '';
    $etime =~ s!(\d{4}-\d{2}-\d{2})!LJ::date_to_view_links( $u, $1 )!e;
    return "<br /><span class='time'>@ $etime</span>";
}

package LJ::Talk::Post;

use Text::Wrap;
use LJ::Entry;

sub indent {
    my $a        = shift;
    my $leadchar = shift || " ";
    $Text::Wrap::columns = 76;
    return Text::Wrap::wrap( "$leadchar ", "$leadchar ", $a );
}

sub blockquote {
    my $a = shift;
    return
"<blockquote style='border-left: #000040 2px solid; margin-left: 0px; margin-right: 0px; padding-left: 15px; padding-right: 0px'>$a</blockquote>";
}

sub enter_comment {
    my ( $journalu, $parent, $item, $comment, $errref ) = @_;

    my $partid = $parent->{talkid};
    my $itemid = $item->{itemid};

    my $err = sub {
        $$errref = join( ": ", @_ );
        return 0;
    };

    return $err->("Invalid user object passed.")
        unless LJ::isu($journalu);

    my $jtalkid = LJ::alloc_user_counter( $journalu, "T" );
    return $err->( "Database Error", "Could not generate a talkid necessary to post this comment." )
        unless $jtalkid;

    # insert the comment
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;

    my $errstr;
    $journalu->talk2_do(
        "L",
        $itemid,
        \$errstr,
        "INSERT INTO talk2 "
            . "(journalid, jtalkid, nodetype, nodeid, parenttalkid, posterid, datepost, state) "
            . "VALUES (?,?,'L',?,?,?,NOW(),?)",
        $journalu->{userid},
        $jtalkid,
        $itemid,
        $partid,
        $posterid,
        $comment->{state}
    );
    if ($errstr) {
        return $err->(
            "Database Error",
            "There was an error posting your comment to the database.  "
                . "Please report this.  The error is: <b>$errstr</b>"
        );
    }

    LJ::MemCache::incr( [ $journalu->{'userid'}, "talk2ct:$journalu->{'userid'}" ] );

    $comment->{talkid} = $jtalkid;

    # record IP if anonymous
    LJ::Talk::record_anon_comment_ip( $journalu, $comment->{talkid}, LJ::get_remote_ip() )
        unless $posterid;

    # add to poster's talkleft table, or the xfer place
    if ($posterid) {
        my $table;
        my $db = LJ::get_cluster_master( $comment->{u} );

        if ($db) {

            # remote's cluster is writable
            $table = "talkleft";
        }
        else {
            # log to global cluster, another job will move it later.
            $db    = LJ::get_db_writer();
            $table = "talkleft_xfp";
        }
        my $pub = $item->{'security'} eq "public" ? 1 : 0;
        if ($db) {
            $db->do(
                "INSERT INTO $table (userid, posttime, journalid, nodetype, "
                    . "nodeid, jtalkid, publicitem) VALUES (?, UNIX_TIMESTAMP(), "
                    . "?, 'L', ?, ?, ?)",
                undef, $posterid, $journalu->{userid}, $itemid, $jtalkid, $pub
            );

            LJ::MemCache::incr( [ $posterid, "talkleftct:$posterid" ] );
        }
        else {
            # both primary and backup talkleft hosts down.  can't do much now.
        }
    }

    $journalu->do(
        "INSERT INTO talktext2 (journalid, jtalkid, subject, body) " . "VALUES (?, ?, ?, ?)",
        undef,
        $journalu->{userid},
        $jtalkid,
        $comment->{subject},
        LJ::text_compress( $comment->{body} )
    );
    die $journalu->errstr if $journalu->err;

    my $memkey = "$journalu->{'clusterid'}:$journalu->{'userid'}:$jtalkid";
    LJ::MemCache::set( [ $journalu->{'userid'}, "talksubject:$memkey" ], $comment->{subject} );
    LJ::MemCache::set( [ $journalu->{'userid'}, "talkbody:$memkey" ],    $comment->{body} );

    LJ::MemCache::delete( [ $journalu->{userid}, "activeentries:" . $journalu->{userid} ] );
    LJ::MemCache::delete( [ $journalu->{userid}, "screenedcount:$journalu->{userid}:$itemid" ] )
        if $comment->{state} eq 'S';

    # dudata
    my $bytes = length( $comment->{subject} ) + length( $comment->{body} );

    # we used to do a LJ::dudata_set(..) on 'T' here, but decided
    # we could defer that.  to find size of a journal, summing
    # bytes in dudata is too slow (too many seeks)

    my %talkprop;    # propname -> value
                     # meta-data
    $talkprop{'unknown8bit'} = 1 if $comment->{unknown8bit};
    $talkprop{'subjecticon'} = $comment->{subjecticon};

    my $pu = $comment->{u};
    if ( $pu && $pu->userpic_have_mapid ) {
        $talkprop{picture_mapid} = $pu->get_mapid_from_keyword( $comment->{picture_keyword} );
    }
    else {
        $talkprop{picture_keyword} = $comment->{picture_keyword};
    }

    $talkprop{admin_post}         = $comment->{admin_post} ? 1 : 0;
    $talkprop{'opt_preformatted'} = $comment->{preformat}  ? 1 : 0;

    if ( $journalu->opt_logcommentips eq "A"
        || ( $journalu->opt_logcommentips eq "S" && $comment->{usertype} ne "user" ) )
    {
        if ( LJ::is_web_context() ) {
            my $ip        = BML::get_remote_ip();
            my $forwarded = BML::get_client_header('X-Forwarded-For');
            $ip = "$forwarded, via $ip" if $forwarded && $forwarded ne $ip;
            $talkprop{'poster_ip'} = $ip;
        }
    }

    # remove blank/0 values (defaults)
    foreach ( keys %talkprop ) { delete $talkprop{$_} unless $talkprop{$_}; }

    # update the talkprops
    LJ::load_props("talk");
    if (%talkprop) {
        my $values;
        my $hash = {};
        foreach ( keys %talkprop ) {
            my $p = LJ::get_prop( "talk", $_ );
            next unless $p;
            $hash->{$_} = $talkprop{$_};
            my $tpropid = $p->{'tpropid'};
            my $qv      = $journalu->quote( $talkprop{$_} );
            $values .= "($journalu->{'userid'}, $jtalkid, $tpropid, $qv),";
        }
        if ($values) {
            chop $values;
            $journalu->do(
                "INSERT INTO talkprop2 (journalid, jtalkid, tpropid, value) " . "VALUES $values" );
            die $journalu->errstr if $journalu->err;
        }
        LJ::MemCache::set( [ $journalu->{'userid'}, "talkprop:$journalu->{'userid'}:$jtalkid" ],
            $hash );
    }

    # update the "replycount" summary field of the log table
    if ( $comment->{state} eq 'A' ) {
        LJ::replycount_do( $journalu, $itemid, "incr" );
    }

    # update the "hasscreened" property of the log item if needed
    if ( $comment->{state} eq 'S' ) {
        LJ::set_logprop( $journalu, $itemid, { 'hasscreened' => 1 } );
    }

    # update the comment alter property
    LJ::Talk::update_commentalter( $journalu, $itemid );

    # fire events
    if ( my $sclient = LJ::theschwartz() ) {
        my @jobs;

        if ( LJ::is_enabled('esn') ) {
            my $cmtobj = LJ::Comment->new( $journalu, jtalkid => $jtalkid );
            push @jobs, LJ::Event::JournalNewComment->new($cmtobj)->fire_job;
        }

        if (@LJ::SPHINX_SEARCHD) {
            push @jobs,
                TheSchwartz::Job->new_from_array( 'DW::Worker::Sphinx::Copier',
                { userid => $journalu->id, jtalkid => $jtalkid, source => "commtnew" } );
        }

        $sclient->insert_jobs(@jobs);
    }

    return $jtalkid;
}

# this is used by the journal import code, but is kept here so as to be kept
# local to the rest of the comment code
sub enter_imported_comment {
    my ( $journalu, $parent, $item, $comment, $date, $errref ) = @_;

    my $partid   = $parent->{talkid};
    my $itemid   = $item->{itemid};
    my $posterid = $comment->{u} ? $comment->{u}->{userid} : 0;

    my $err = sub {
        $$errref = join( ": ", @_ );
        return 0;
    };

    return $err->("Invalid user object passed.")
        unless LJ::isu($journalu);

    # prealloc counter before insert
    my $jtalkid = LJ::alloc_user_counter( $journalu, "T" );
    return $err->( "Database Error", "Could not generate a talkid necessary to post this comment." )
        unless $jtalkid;
    $comment->{talkid} = $jtalkid;

    # insert the comment
    my $errstr;
    $journalu->talk2_do(
        "L", $itemid, \$errstr,
        q{
            INSERT INTO talk2 (journalid, jtalkid, nodetype, nodeid, parenttalkid, posterid, datepost, state)
            VALUES (?,?,'L',?,?,?,?,?)
        },
        $journalu->{userid}, $jtalkid, $itemid, $partid, $posterid, $date, $comment->{state}
    );

    return $err->(
        "Database Error",
        "There was an error posting your comment to the database.  "
            . "Please report this.  The error is: <b>$errstr</b>"
    ) if $errstr;

    LJ::MemCache::delete( [ $journalu->{userid}, "talk2ct:$journalu->{userid}" ] );

    # add to poster's talkleft table, or the xfer place
    if ($posterid) {
        my $table;
        my $db = LJ::get_cluster_master( $comment->{u} );

        if ($db) {

            # remote's cluster is writable
            $table = "talkleft";
        }
        else {
            # log to global cluster, another job will move it later.
            $db    = LJ::get_db_writer();
            $table = "talkleft_xfp";
        }

        my $pub = $item->{'security'} eq "public" ? 1 : 0;
        if ($db) {
            $db->do(
                qq{
                    INSERT INTO $table (userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem)
                    VALUES (?, UNIX_TIMESTAMP(?), ?, 'L', ?, ?, ?)
                }, undef, $posterid, $date, $journalu->{userid}, $itemid, $jtalkid, $pub
            );
            LJ::MemCache::delete( [ $posterid, "talkleftct:$posterid" ] );
        }
        else {
            # both primary and backup talkleft hosts down.  can't do much now.
            warn "Unable to insert comment into talkleft, cluster+master down?";
        }
    }

    if ( $comment->{state} ne "D" ) {
        $journalu->do(
            q{
                INSERT INTO talktext2 (journalid, jtalkid, subject, body)
                VALUES (?, ?, ?, ?)
            }, undef, $journalu->{userid}, $jtalkid, $comment->{subject},
            LJ::text_compress( $comment->{body} )
        );
        die $journalu->errstr if $journalu->err;
    }

    my %talkprop;    # propname -> value

    foreach my $key ( keys %{ $comment->{props} || {} } ) {
        $talkprop{$key} = $comment->{props}->{$key};
    }

    $talkprop{'unknown8bit'} = 1 if $comment->{unknown8bit};
    $talkprop{'subjecticon'} = $comment->{subjecticon};

    my $pu = $comment->{u};
    if ( $pu && $pu->userpic_have_mapid ) {
        $talkprop{picture_mapid} =
            $pu->get_mapid_from_keyword( $comment->{picture_keyword}, create => 1 );
    }
    else {
        $talkprop{picture_keyword} = $comment->{picture_keyword};
    }

    $talkprop{'opt_preformatted'} = $comment->{preformat} ? 1 : 0;

    # remove blank/0 values (defaults)
    foreach ( keys %talkprop ) {
        delete $talkprop{$_} unless $talkprop{$_};
    }

    # update the talkprops
    LJ::load_props("talk");
    if (%talkprop) {
        my $values;
        my $hash = {};
        foreach ( keys %talkprop ) {
            my $p = LJ::get_prop( "talk", $_ );
            next unless $p;
            $hash->{$_} = $talkprop{$_};
            my $tpropid = $p->{'tpropid'};
            my $qv      = $journalu->quote( $talkprop{$_} );
            $values .= "($journalu->{'userid'}, $jtalkid, $tpropid, $qv),";
        }
        if ($values) {
            chop $values;
            $journalu->do(
                "INSERT INTO talkprop2 (journalid, jtalkid, tpropid, value) " . "VALUES $values" );
            die $journalu->errstr if $journalu->err;
        }
    }

    # update the "replycount" summary field of the log table
    if ( $comment->{state} eq 'A' || $comment->{state} eq 'F' ) {
        LJ::replycount_do( $journalu, $itemid, "incr" );
    }

    # update the "hasscreened" property of the log item if needed
    if ( $comment->{state} eq 'S' ) {
        LJ::set_logprop( $journalu, $itemid, { 'hasscreened' => 1 } );
    }

    # update the comment alter property
    LJ::Talk::update_commentalter( $journalu, $itemid );

    return $jtalkid;
}

sub init {
    my ( $form, $remote, $need_captcha, $errret ) = @_;
    my $sth;

    my $err = sub {
        my $error = shift;
        push @$errret, $error;
        return undef;
    };
    my $mlerr = sub {
        return $err->( LJ::Lang::ml(@_) );
    };

    my $init = LJ::Talk::init($form);
    return $err->( $init->{error} ) if $init->{error};

    my $journalu = $init->{'journalu'};
    return $mlerr->('talk.error.nojournal') unless $journalu;
    return $err->($LJ::MSG_READONLY_USER) if $journalu->is_readonly;

    return $err->("Account is locked, unable to post or edit a comment.") if $journalu->is_locked;

    my $r = DW::Request->get;
    $r->note( 'journalid', $journalu->userid ) if $r;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    return $mlerr->('error.nodb') unless $dbcr;

    my $itemid = $init->{'itemid'} + 0;

    my $item = LJ::Talk::get_journal_item( $journalu, $itemid );

    if ( $init->{'oldurl'} && $item ) {
        $init->{'anum'}    = $item->{'anum'};
        $init->{'ditemid'} = $init->{'itemid'} * 256 + $item->{'anum'};
    }

    unless ( $item && $item->{'anum'} == $init->{'anum'} ) {
        return $mlerr->('talk.error.noentry');
    }

    my $iprops  = $item->{'props'};
    my $ditemid = $init->{'ditemid'} + 0;

    my $entry   = LJ::Entry->new( $journalu, ditemid => $ditemid );
    my $talkurl = $entry->url;
    $init->{talkurl} = $talkurl;

    ### load users
    LJ::load_userids_multiple(
        [
            $item->{'posterid'} => \$init->{entryu},
        ],
        [$journalu]
    );

    if ( $form->{'userpost'} && $form->{'usertype'} ne "user" ) {
        unless ( $form->{'usertype'} eq "cookieuser"
            && $form->{'userpost'} eq $form->{'cookieuser'} )
        {
            $mlerr->("$SC.error.confused_identity");
        }
    }

    my $cookie_auth;

    # we are posting from talkpost, as currently logged-in user
    if ( $form->{usertype} eq "cookieuser" ) {
        my $userpost = $form->{'userpost'} || $form->{'cookieuser'};
        $mlerr->("$SC.error.lostcookie")
            unless $remote && $remote->{'user'} eq $userpost;
        return undef if @$errret;

        $cookie_auth        = 1;
        $form->{'userpost'} = $remote->{'user'};
        $form->{'usertype'} = "user";
    }

    # FIXME: XXXevan hack:  remove me when we fix preview.
    $init->{cookie_auth} = $cookie_auth;

    # test accounts may only comment on other test accounts.
    if (   ( grep { $form->{'userpost'} eq $_ } @LJ::TESTACCTS )
        && !( grep { $journalu->{'user'} eq $_ } @LJ::TESTACCTS )
        && !$LJ::IS_DEV_SERVER )
    {
        $mlerr->("$SC.error.testacct");
    }

    my $userpost = lc( $form->{'userpost'} );
    my $iscomm   = $journalu->is_community ? '.comm' : '';
    my $up;         # user posting
    my $exptype;    # set to long if ! after username
    my $ipfixed;    # set to remote  ip if < after username

    if ( $form->{'usertype'} eq "user" ) {
        if ( $form->{'userpost'} ) {

            # parse inline login opts
            if ( $form->{userpost} =~ s/([!<]{1,2})$// ) {
                $exptype = 'long' if index( $1, "!" ) >= 0;
                $ipfixed = LJ::get_remote_ip() if index( $1, "<" ) >= 0;
            }

            $up = LJ::load_user( $form->{'userpost'} );
            if ($up) {
                ### see if the user is banned from posting here
                $mlerr->("$SC.error.banned$iscomm") if $journalu->has_banned($up);

                # Reject OpenIDs that are neither validated nor granted access by the user
                if (   $up->is_identity
                    && $journalu->{'opt_whocanreply'} eq "reg"
                    && !( $up->is_validated || $journalu->trusts($remote) ) )
                {
                    $mlerr->(
                        "$SC.error.noopenidpost",
                        {
                            aopts1 => "href='$LJ::SITEROOT/changeemail'",
                            aopts2 => "href='$LJ::SITEROOT/register'"
                        }
                    );
                }

                unless ( $up->is_person || ( $up->is_identity && $cookie_auth ) ) {
                    $mlerr->("$SC.error.postshared");
                }

                # if we're already authenticated via cookie, then userpost was set
                # to the authenticated username, so we got into this block, but we
                # don't want to re-authenticate, so just skip this
                unless ($cookie_auth) {

                    # authenticate on username/password
                    my $ok;
                    if ( $form->{response} ) {
                        $ok = LJ::challenge_check_login( $up, $form->{chal}, $form->{response} );
                    }
                    else {
                        $ok = LJ::auth_okay( $up, $form->{password}, $form->{hpassword} );
                    }
                    $mlerr->(
                        "$SC.error.badpassword2", { aopts => "href='$LJ::SITEROOT/lostinfo'" }
                    ) unless $ok;
                }

                # if the user chooses to log in, do so
                if ( $form->{'do_login'} && !@$errret ) {
                    $init->{didlogin} = $up->make_login_session( $exptype, $ipfixed );
                }
            }
            else {
                $mlerr->(
                    "$SC.error.badusername2",
                    {
                        sitename => $LJ::SITENAMESHORT,
                        aopts    => "href='$LJ::SITEROOT/lostinfo'"
                    }
                );
            }
        }
        elsif ( $journalu->{'opt_whocanreply'} eq "all" ) {
            $mlerr->( "$SC.error.nousername", { sitename => $LJ::SITENAMESHORT } );
        }
        else {
            $mlerr->( "$SC.error.nousername.noanon$iscomm", { sitename => $LJ::SITENAMESHORT } );
        }
    }

    # OpenID
    if ( $form->{'usertype'} eq 'openid' || $form->{'usertype'} eq 'openid_cookie' ) {

        if ( $remote && defined $remote->openid_identity ) {
            $up = $remote;

            ### see if the user is banned from posting here
            $mlerr->("$SC.error.banned") if $journalu->has_banned($up);

            if ( $form->{'oiddo_login'} ) {
                $up->make_login_session( $form->{'exptype'}, $form->{'ipfixed'} );
            }
        }
        else {    # First time through
            my $csr     = LJ::OpenID::consumer();
            my $exptype = 'short';
            my $ipfixed = 0;
            my $etime   = 0;

            # parse inline login opts
            return $err->("No OpenID identity URL entered") unless $form->{'oidurl'};
            if ( $form->{oidurl} =~ s/([!<]{1,2})$// ) {
                if ( index( $1, "!" ) >= 0 ) {
                    $exptype = 'long';
                    $etime   = time() + 60 * 60 * 24 * 60;
                }
                $ipfixed = LJ::get_remote_ip() if index( $1, "<" ) >= 0;
            }

            my $tried_local_ref = LJ::OpenID::blocked_hosts($csr);

            my $claimed_id = $csr->claimed_identity( $form->{'oidurl'} );

            unless ($claimed_id) {
                return $err->(
                    "You can't use a $LJ::SITENAMESHORT OpenID account on $LJ::SITENAME &mdash; "
                        . "just <a href='/login'>go login</a> with your actual $LJ::SITENAMESHORT account."
                ) if $$tried_local_ref;
                return $err->( "No claimed id: " . $csr->err );
            }

            # Store their cleaned up identity url vs what they
            # actually typed in
            $form->{'oidurl'} = $claimed_id->claimed_url();

            # Store the entry
            my $pendcid = LJ::alloc_user_counter( $journalu, "C" );

            $err->("Unable to allocate pending id") unless $pendcid;

            # Since these were gotten from the oidurl and won't
            # persist in the form data
            $form->{'exptype'} = $exptype;
            $form->{'etime'}   = $etime;
            $form->{'ipfixed'} = $ipfixed;
            my $penddata = Storable::freeze($form);

            $err->("Unable to get database handle to store pending comment")
                unless $journalu->writer;

            $journalu->do(
"INSERT INTO pendcomments (jid, pendcid, data, datesubmit) VALUES (?, ?, ?, UNIX_TIMESTAMP())",
                undef, $journalu->{'userid'}, $pendcid, $penddata
            );

            $err->( $journalu->errstr ) if $journalu->err;

            my $check_url = $claimed_id->check_url(
                return_to => "$LJ::SITEROOT/talkpost_do?jid=$journalu->{'userid'}&pendcid=$pendcid",
                trust_root     => "$LJ::SITEROOT",
                delayed_return => 1,
            );

            # Don't redirect them if errors
            return undef if @$errret;
            return BML::redirect($check_url);
        }
    }

    # validate the challenge/response value (anti-spammer)
    my $chrp_err;
    if ( my $chrp = $form->{'chrp1'} ) {
        my ( $c_ditemid, $c_uid, $c_time, $c_chars, $c_res ) =
            split( /\-/, $chrp );
        my $chal   = "$c_ditemid-$c_uid-$c_time-$c_chars";
        my $secret = LJ::get_secret($c_time);
        my $res    = Digest::MD5::md5_hex( $secret . $chal );
        if ( $res ne $c_res ) {
            $chrp_err = "invalid";
        }
        elsif ( $c_time < time() - 2 * 60 * 60 ) {
            $chrp_err = "too_old" if $LJ::REQUIRE_TALKHASH_NOTOLD;
        }
    }
    else {
        $chrp_err = "missing";
    }
    if ($chrp_err) {
        my $ip = LJ::get_remote_ip();
        if ( $LJ::DEBUG{'talkspam'} ) {
            my $ruser = $remote ? $remote->{user} : "[nonuser]";
            print STDERR "talkhash error: from $ruser \@ $ip - $chrp_err - $talkurl\n";
        }
        if ($LJ::REQUIRE_TALKHASH) {
            return $err->(
"Sorry, form expired.  Press back, copy text, reload form, paste into new form, and re-submit."
            ) if $chrp_err eq "too_old";
            return $err->("Missing parameters");
        }
    }

    # check that user can even view this post, which is required
    # to reply to it
    ####  Check security before viewing this post
    my $ent = LJ::Entry->new_from_item_hash($item)
        or die "Unable to create entry object.\n";
    unless ( $ent->visible_to($up) ) {
        $mlerr->("$SC.error.mustlogin") unless defined $up;
        $mlerr->("$SC.error.noauth");
        return undef;
    }

    # If the reply is to a comment, check that it exists.

    my $parpost;
    my $partid = $form->{'parenttalkid'} + 0;

    if ($partid) {
        $parpost = LJ::Talk::get_talk2_row( $dbcr, $journalu->{userid}, $partid );
        unless ($parpost) {
            $mlerr->("$SC.error.noparent");
        }
    }
    $init->{parpost} = $parpost;

    # don't allow anonymous comments on syndicated items
    if ( $journalu->is_syndicated && $journalu->{'opt_whocanreply'} eq "all" ) {
        $journalu->{'opt_whocanreply'} = "reg";
    }

    if (
        (
               $form->{'usertype'} ne "user"
            && $form->{'usertype'} ne 'openid'
            && $form->{'usertype'} ne 'openid_cookie'
        )
        && $journalu->{'opt_whocanreply'} ne "all"
        )
    {
        $mlerr->("$SC.error.noanon$iscomm");
    }

    if ( $ent->comments_disabled ) {
        $mlerr->("$SC.error.nocomments");
    }

    if ($up) {
        if (   $up->{'status'} eq "N"
            && !$up->is_identity
            && !LJ::Hooks::run_hook( "journal_allows_unvalidated_commenting", $journalu ) )
        {
            $mlerr->( "$SC.error.noverify2", { aopts => "href='$LJ::SITEROOT/register'" } );
        }

        $mlerr->("$SC.error.purged")    if $up->is_expunged;
        $mlerr->("$SC.error.deleted")   if $up->is_deleted;
        $mlerr->("$SC.error.suspended") if $up->is_suspended;
    }

    if ( $journalu->{'opt_whocanreply'} eq "friends" ) {
        if ($up) {
            if ( $up->{'userid'} != $journalu->{'userid'} ) {
                unless ( $journalu->trusts_or_has_member($up) ) {
                    my $msg = $journalu->is_comm ? "notamember" : "notafriend";
                    $mlerr->( "$SC.error.$msg", { user => $journalu->user } );
                }
            }
        }
        else {
            my $msg = $journalu->is_comm ? "membersonly" : "friendsonly";
            $mlerr->( "$SC.error.$msg", { user => $journalu->user } );
        }
    }

    $mlerr->("$SC.error.blankmessage") unless $form->{'body'} =~ /\S/;

    # in case this post comes directly from the user's mail client, it
    # may have an encoding field for us.
    if ( $form->{'encoding'} ) {
        $form->{'body'} = Unicode::MapUTF8::to_utf8(
            { -string => $form->{'body'}, -charset => $form->{'encoding'} } );
        $form->{'subject'} = Unicode::MapUTF8::to_utf8(
            { -string => $form->{'subject'}, -charset => $form->{'encoding'} } );
    }

    # unixify line-endings
    $form->{'body'} =~ s/\r\n/\n/g;

    # now check for UTF-8 correctness, it must hold
    return $err->("<?badinput?>") unless LJ::text_in($form);

    $init->{unknown8bit} = 0;

    my ( $bl, $cl ) = LJ::text_length( $form->{'body'} );
    if ( $cl > LJ::CMAX_COMMENT ) {
        $mlerr->(
            "$SC.error.manychars",
            {
                current => $cl,
                limit   => LJ::CMAX_COMMENT
            }
        );
    }
    elsif ( $bl > LJ::BMAX_COMMENT ) {
        $mlerr->(
            "$SC.error.manybytes",
            {
                current => $bl,
                limit   => LJ::BMAX_COMMENT
            }
        );
    }

    # the Subject can be silently shortened, no need to reject the whole comment
    $form->{'subject'} = LJ::text_trim( $form->{'subject'}, 100, 100 );

    my $subjecticon      = "";
    my $form_subjecticon = $form->{'subjecticon'} || "";
    if ( $form_subjecticon ne "none" && $form_subjecticon ne "" ) {
        $subjecticon = LJ::trim( lc($form_subjecticon) );
    }

    # figure out whether to post this comment screened
    my $state     = 'A';
    my $screening = LJ::Talk::screening_level( $journalu, $ditemid >> 8 ) || "";
    $screening = 'A' if $journalu->has_autoscreen($up);
    if (   $screening eq 'A'
        || ( $screening eq 'R' && !$up )
        || ( $screening eq 'F' && !( $up && $journalu->trusts_or_has_member($up) ) ) )
    {
        $state = 'S';
    }

    my $parent = {
        state    => $parpost->{state},
        talkid   => $partid,
        posterid => $parpost->{posterid},
    };
    my $comment = {
        u               => $up,
        usertype        => $form->{'usertype'},
        subject         => $form->{'subject'},
        body            => $form->{'body'},
        unknown8bit     => $init->{unknown8bit},
        subjecticon     => $subjecticon,
        preformat       => $form->{'prop_opt_preformatted'},
        admin_post      => $form->{'prop_admin_post'},
        picture_keyword => $form->{'prop_picture_keyword'},
        state           => $state,
        editid          => $form->{editid},
        editreason      => $form->{editreason},
    };

    $init->{item}    = $item;
    $init->{parent}  = $parent;
    $init->{comment} = $comment;

    # anti-spam captcha check
    if ( ref $need_captcha eq 'SCALAR' ) {

        # see if they're in the second+ phases of a captcha check.
        # are they sending us a response?

        $form->{want} = $form->{captcha_type};
        my $captcha = DW::Captcha->new( undef, %{ $form || {} } );

        if ( $captcha->enabled && $captcha->response ) {

            # assume they won't pass and re-set the flag
            $$need_captcha = 1;

            my $captcha_error;
            return $err->($captcha_error) unless $captcha->validate( err_ref => \$captcha_error );
        }
        else {
            $$need_captcha =
                LJ::Talk::Post::require_captcha_test( $comment->{'u'}, $journalu, $form->{body},
                $ditemid );

            return $err->( LJ::Lang::ml('captcha.title') ) if $$need_captcha;
        }
    }

    return undef if @$errret;
    return $init;
}

# <LJFUNC>
# name: LJ::Talk::Post::require_captcha_test
# des: returns true if user must answer CAPTCHA (human test) before posting a comment
# args: commenter, journal, body, ditemid
# des-commenter: User object of author of comment, undef for anonymous commenter
# des-journal: User object of journal where to post comment
# des-body: Text of the comment (may be checked for spam, may be empty)
# des-ditemid: identifier of post, need for checking reply-count
# </LJFUNC>
sub require_captcha_test {
    my ( $commenter, $journal, $body, $ditemid ) = @_;

    # only require captcha if the site is properly configured for it
    return 0 unless DW::Captcha->site_enabled;

    ## anonymous commenter user =
    ## not logged-in user, or OpenID without validated e-mail
    my $anon_commenter = !LJ::isu($commenter)
        || ( $commenter->identity && !$commenter->is_validated );

    ##
    ## 1. Check rate by remote user and by IP (for anonymous user)
    ##
    my $captcha = DW::Captcha->new;
    if ( $captcha->enabled('anonpost') || $captcha->enabled('authpost') ) {
        return 1 unless LJ::Talk::Post::check_rate( $commenter, $journal );
    }
    if ( $captcha->enabled('anonpost') && $anon_commenter ) {
        return 1 if LJ::sysban_check( 'talk_ip_test', LJ::get_remote_ip() );
    }

    ##
    ## 4. Test preliminary limit on comment.
    ## We must check it before we will allow owner to pass.
    ##
    if ( LJ::Talk::get_replycount( $journal, $ditemid >> 8 ) >=
        $journal->count_maxcomments_before_captcha )
    {
        return 1;
    }

    ##
    ## 2. Don't show captcha to the owner of the journal, no more checks
    ##
    if ( !$anon_commenter && $commenter->equals($journal) ) {
        return 0;
    }

    ##
    ## 3. Custom (journal) settings
    ##
    my $show_captcha_to = $journal->prop('opt_show_captcha_to');
    if ( !$show_captcha_to || $show_captcha_to eq 'N' ) {
        ## no one
    }
    elsif ( $show_captcha_to eq 'R' ) {
        ## anonymous
        return 1 if $anon_commenter;
    }
    elsif ( $show_captcha_to eq 'F' ) {
        ## not friends
        return 1 if !$journal->trusts_or_has_member($commenter);
    }
    elsif ( $show_captcha_to eq 'A' ) {
        ## all
        return 1;
    }

    ##
    ## 4. Global (site) settings
    ## See if they have any tags or URLs in the comment's body
    ##
    if ( $captcha->enabled('comment_html_auth')
        || ( $captcha->enabled('comment_html_anon') && $anon_commenter ) )
    {
        if ( $body =~ /<[a-z]/i ) {

            # strip white-listed bare tags w/o attributes,
            # then see if they still have HTML.  if so, it's
            # questionable.  (can do evil spammy-like stuff w/
            # attributes and other elements)
            my $body_copy = $body;
            $body_copy =~ s/<(?:q|blockquote|b|strong|i|em|cite|sub|sup|var|del|tt|code|pre|p)>//ig;
            return 1 if $body_copy =~ /<[a-z]/i;
        }

        # multiple URLs is questionable too
        return 1 if $body =~ /\b(?:http|ftp|www)\b.+\b(?:http|ftp|www)\b/s;

        # or if they're not even using HTML
        return 1 if $body =~ /\[url/is;

        # or if it's obviously spam
        return 1 if $body =~ /\s*message\s*/is;
    }
}

# returns 1 on success.  0 on fail (with $$errref set)
sub post_comment {
    my ( $entryu, $journalu, $comment, $parent, $item, $errref, $unscreen_parent ) = @_;

    my $parent_state = $parent->{state} || "";

    # unscreen the parent comment if needed
    if ( $parent_state eq 'S' && $unscreen_parent ) {

     # if parent comment is screened and we got this far, the user has the permission to unscreen it
     # in this case the parent comment needs to be unscreened and the comment posted as normal
        LJ::Talk::unscreen_comment( $journalu, $item->{itemid}, $parent->{talkid} );
        $parent->{state} = 'A';
    }
    elsif ( $parent_state eq 'S' ) {

      # if the parent comment is screened and the unscreen option was not selected, we also want the
      # reply to be posted as screened
        $comment->{state} = 'S';
    }

    # check for duplicate entry (double submission)
    # Note:  we don't do it inside a locked section like LJ::Protocol's postevent,
    # so it's not perfect, but it works pretty well.
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;
    my $jtalkid;

    # check for dup ID in memcache.
    my $memkey;
    if (@LJ::MEMCACHE_SERVERS) {

        # avoid warnings FIXME this should be done elsewhere
        foreach my $field (qw(body subject subjecticon preformat admin_post picture_keyword)) {
            $comment->{$field} = '' if not defined $comment->{$field};
        }
        my $md5_b64 = Digest::MD5::md5_base64(
            join(
                ":",
                (
                    $comment->{body},        $comment->{subject},
                    $comment->{subjecticon}, $comment->{preformat},
                    $comment->{picture_keyword}
                )
            )
        );
        $memkey = [
            $journalu->{userid},
            "tdup:$journalu->{userid}:$item->{itemid}-$parent->{talkid}-$posterid-$md5_b64"
        ];
        $jtalkid = LJ::MemCache::get($memkey);
    }

    # they don't have a duplicate...
    unless ($jtalkid) {
        my ( $posteru, $kw ) = ( $comment->{u}, $comment->{picture_keyword} );

        # XXX do select and delete $talkprop{'picture_keyword'} if they're lying
        my $pic = LJ::Userpic->new_from_keyword( $posteru, $kw );
        delete $comment->{picture_keyword} unless $pic && $pic->state eq 'N';
        $comment->{pic} = $pic;

        # put the post in the database
        $item->{anum} ||= 0;    # avoid warning FIXME this should be done elsewhere
        my $ditemid = $item->{itemid} * 256 + $item->{anum};
        $jtalkid = enter_comment( $journalu, $parent, $item, $comment, $errref );
        return 0 unless $jtalkid;

        # save its identifying characteristics to protect against duplicates.
        LJ::MemCache::set( $memkey, $jtalkid + 0, time() + 60 * 10 );
    }

    # the caller wants to know the comment's talkid.
    $comment->{talkid} = $jtalkid;

    # cluster tracking
    LJ::mark_user_active( $comment->{u}, 'comment' );

    DW::Stats::increment(
        'dw.action.comment.post',
        1,
        [
            "journal_type:" . $journalu->journaltype_readable,
            "poster_type:"
                . ( ref $comment->{u} ? $comment->{u}->journaltype_readable : 'anonymous' )
        ]
    );

    LJ::Hooks::run_hooks( 'new_comment', $journalu->{userid}, $item->{itemid}, $jtalkid );

    return 1;
}

# returns 1 on success.  0 on fail (with $$errref set)
sub edit_comment {
    my ( $entryu, $journalu, $comment, $parent, $item, $errref ) = @_;

    my $err = sub {
        $$errref = join( ": ", @_ );
        return 0;
    };

    my $comment_obj = LJ::Comment->new( $journalu, dtalkid => $comment->{editid} );

    my $remote = LJ::get_remote();
    return 0 unless $comment_obj->remote_can_edit($errref);

    my %props = (
        subjecticon      => $comment->{subjecticon},
        opt_preformatted => $comment->{preformat} ? 1 : 0,
        admin_post       => $comment->{admin_post} ? 1 : 0,
        edit_reason      => $comment->{editreason},
    );

    # set to undef if we have blank/0 values (set_props will delete these from the DB later)
    foreach ( keys %props ) { $props{$_} = undef unless $props{$_}; }

    my $pu = $comment_obj->poster;
    if ( $pu && $pu->userpic_have_mapid ) {
        $props{picture_mapid} = $pu->get_mapid_from_keyword( $comment->{picture_keyword} );
    }
    else {
        $props{picture_keyword} = $comment->{picture_keyword};
    }

    # set most of the props together
    $comment_obj->set_props(%props);

    # set edit time separately since it needs to be a raw value
    $comment_obj->set_prop_raw( edit_time => "UNIX_TIMESTAMP()" );

    # set poster IP separately since it has special conditions
    my $opt_logcommentips = $comment_obj->journal->opt_logcommentips;
    if ( $opt_logcommentips eq "A"
        || ( $opt_logcommentips eq "S" && $comment->{usertype} ne "user" ) )
    {
        $comment_obj->set_poster_ip;
    }

    # set subject and body text
    $comment_obj->set_subject_and_body( $comment->{subject}, $comment->{body} );

    # the caller wants to know the comment's talkid.
    $comment->{talkid} = $comment_obj->jtalkid;

    # If we need to rescreen the comment, do so now.
    my $state = $comment->{state} || "";
    if ( $state eq 'S' ) {
        LJ::Talk::screen_comment( $journalu, $item->{itemid}, $comment->{talkid} );
    }

    # cluster tracking
    LJ::mark_user_active( $pu, 'comment' );

    # fire events
    if ( my $sclient = LJ::theschwartz() ) {
        my @jobs;

        if ( LJ::is_enabled('esn') ) {
            push @jobs, LJ::Event::JournalNewComment::Edited->new($comment_obj)->fire_job;
        }

        if (@LJ::SPHINX_SEARCHD) {
            push @jobs,
                TheSchwartz::Job->new_from_array( 'DW::Worker::Sphinx::Copier',
                { userid => $journalu->id, jtalkid => $comment->{talkid}, source => "commtedt" } );
        }

        $sclient->insert_jobs(@jobs);
    }

    DW::Stats::increment(
        'dw.action.comment.edit',
        1,
        [
            "journal_type:" . $journalu->journaltype_readable,
            "poster_type:" . $pu ? $pu->journaltype_readable : 'anonymous'
        ]
    );

    LJ::Hooks::run_hooks( 'edit_comment', $journalu->{userid}, $item->{itemid},
        $comment->{talkid} );

    return 1;
}

# XXXevan:  this function should have its functionality migrated to talkpost.
# because of that, it's probably not worth the effort to make it not mangle $form...
sub make_preview {
    my ( $talkurl, $cookie_auth, $form ) = @_;
    my $ret = "";

    # Adding in the relevant Javascript file to process the More Options button
    LJ::need_res( { group => 'jquery' }, 'js/jquery.commentpreview.js' );

    # preview form

    $ret .=
"<?h2 $BML::ML{'/talkpost_do.bml.preview.title'} h2?><?p $BML::ML{'/talkpost_do.bml.preview'} p?><?hr?>";

    my $cleansubject = $form->{'subject'};
    LJ::CleanHTML::clean_subject( \$cleansubject );
    my $event = $form->{'body'};
    my $spellcheck_html;

    # clean first; if the cleaner finds it invalid, don't spellcheck, so that we
    # can show the user the error.
    my $remote  = LJ::get_remote();
    my $u       = LJ::load_user( $form->{journal} );
    my $cleanok = LJ::CleanHTML::clean_comment(
        \$event,
        {
            anon_comment => LJ::Talk::treat_as_anon( $remote, $u ),
            preformatted => $form->{prop_opt_preformatted},
            admin_post   => $form->{prop_admin_post},
            editor       => $form->{editor},                          # no form option yet
        }
    );
    if ( defined($cleanok) && $LJ::SPELLER && $form->{'do_spellcheck'} ) {
        my $s = new LJ::SpellCheck {
            'spellcommand' => $LJ::SPELLER,
            'color'        => '<?hotcolor?>',
        };
        $spellcheck_html = $s->check_html( \$event, 1 );

        # second arg '1' means don't escape the HTML
    }

    $ret .= "$BML::ML{'/talkpost_do.bml.preview.poster'} ";

    # displays the username or openid url of the commenter, or anonymous otherwise
    my $has_remote = LJ::isu($remote);
    my $has_cookie = { cookieuser => $has_remote, openid_cookie => $has_remote };
    if ( $has_cookie->{ $form->{usertype} } ) {
        $ret .= $remote->ljuser_display;
    }
    elsif ( $form->{'usertype'} eq 'openid' ) {
        $ret .= BML::ml( ".preview.unauthenticated_openid", { openid => $form->{oidurl} } );
    }
    else {    # anonymous usertype or not logged in
        $ret .= $BML::ML{'/talkpost_do.bml.preview.anonymous'};
    }
    $ret .= "<br />";
    $ret .= "$BML::ML{'/talkpost_do.bml.preview.subject'} " . LJ::ehtml($cleansubject) . "<hr />\n";

    my $icon_kw = "";
    if ($cookie_auth) {
        $icon_kw = delete $form->{prop_picture_keyword};
        my $icon = LJ::Userpic->new_from_keyword( $remote, $icon_kw );
        $ret .= "<div class='userpic'>" . $icon->imgtag( keyword => $icon_kw ) . "</div>" if $icon;
    }

    if ($spellcheck_html) {
        $ret .= $spellcheck_html;
        $ret .= "<p>";
    }
    else {
        $ret .= $event;
    }

    $ret .= "<hr />";

    # While it may seem like we need form auth for this form, the form for
    # actually composing a comment includes it.  It is then put into this
    # form about 20 lines below: foreach (keys %$form).
    $ret .= "<div style='width: 90%'><form id='previewform' method='post'><p>\n";
    $ret .= "<label for='subject'>$BML::ML{'/talkpost_do.bml.preview.edit.subject'}</label>";
    $ret .=
          "<input name='subject' size='50' maxlength='100' value='"
        . LJ::ehtml( $form->{'subject'} )
        . "' /><br />";
    if ($cookie_auth) {
        $ret .= "<div class='userpics'>" . LJ::Talk::icon_dropdown( $remote, $icon_kw ) . "</div>";
        if ( $u->is_community && $remote && $remote->can_manage($u) ) {
            $ret .= "<div class='admin_post'>"
                . LJ::html_check(
                {
                    name     => 'prop_admin_post',
                    id       => 'prop_admin_post',
                    value    => 1,
                    selected => $form->{'prop_admin_post'}
                }
                ) . "<label for='prop_admin_post'>Admin Post</label></div>";
        }
    }
    $ret .= "<label for='body'>$BML::ML{'/talkpost_do.bml.preview.edit.body'}</label>";
    $ret .=
"<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' style='width: 100%'>";
    $ret .= LJ::ehtml( $form->{'body'} );
    $ret .= "</textarea></p>";

    # editreason
    if ( $form->{edit} or $form->{editid} ) {
        $ret .=
            "<label for='editreason'>$BML::ML{'/talkpost_do.bml.preview.edit.editreason'}</label>";
        $ret .= "<input name='editreason' size='75' maxlength='255' value='"
            . LJ::ehtml( $form->{editreason} ) . "' />";
    }

    # change mode:
    delete $form->{'submitpreview'};
    $form->{'submitpost'} = 1;
    if ($cookie_auth) {
        $form->{'usertype'} = "cookieuser";
        delete $form->{'userpost'};
    }
    delete $form->{'do_spellcheck'};
    foreach ( keys %$form ) {
        $ret .= LJ::html_hidden( $_, $form->{$_} )
            unless $_ eq 'body'
            || $_ eq 'subject'
            || $_ eq 'prop_opt_preformatted'
            || $_ eq 'editreason';
    }

    my $post_disabled = $u->does_not_allow_comments_from($remote)
        || $u->does_not_allow_comments_from_unconfirmed_openid($remote);
    if ($post_disabled) {
        $ret .= "<div class='ui-state-error'>$BML::ML{'/talkpost.bml.error.nocomment_quick'}</div>";
    }
    my $disabling_extra = $post_disabled ? ' disabled="disabled" class="ui-state-disabled"' : '';
    $ret .=
"<br /><input type='submit' $disabling_extra value='$BML::ML{'/talkpost_do.bml.preview.postcomment'}' />\n";
    $ret .= "<input type='submit' name='submitpreview' value='$BML::ML{'talk.btn.preview'}' />\n";
    $ret .= "<span id='moreoptions-container'></span>\n";
    if ($LJ::SPELLER) {
        $ret .=
"<input type='checkbox' name='do_spellcheck' value='1' id='spellcheck' /> <label for='spellcheck'>$BML::ML{'talk.spellcheck'}</label>";
    }
    $ret .= "<p>";
    $ret .= "$BML::ML{'/talkpost.bml.opt.noautoformat'} "
        . LJ::html_check(
        {
            'name'   => 'prop_opt_preformatted',
            selected => $form->{'prop_opt_preformatted'}
        }
        );
    $ret .= LJ::help_icon_html( "noautoformat", " " );
    $ret .= "</p>";

    $ret .= "<p> <?de $BML::ML{'/talkpost.bml.allowedhtml'}: ";
    foreach ( sort &LJ::CleanHTML::get_okay_comment_tags() ) {
        $ret .= "&lt;$_&gt; ";
    }
    $ret .= "de?> </p>";

    $ret .= "</form></div>";

    # entry details
    my $entry = LJ::Entry->new_from_url($talkurl);
    if ( $entry && $entry->visible_to($remote) ) {
        $ret .= "<?hr?><?h2 $BML::ML{'/talkpost_do.bml.preview.context'} h2?>";

        if ( my $ju = $entry->journal ) {
            $ret .= "<?p ";

            my $pu = $entry->poster;
            if ( $pu && !$pu->equals($ju) ) {
                $ret .= BML::ml(
                    '/talkpost_do.bml.preview.entry.journal',
                    {
                        user    => $pu->ljuser_display,
                        journal => $ju->ljuser_display
                    }
                );
            }
            else {
                $ret .= $ju->ljuser_display;
            }
            my $etime = LJ::mysqldate_to_time( $entry->eventtime_mysql );
            $ret .= " @ " . LJ::S2::sitescheme_secs_to_iso($etime);

            $ret .= " p?>\n";
        }

        $ret .= "<?p ";
        ### security indicator
        my $sec = $entry->security;
        if ( $sec eq "private" ) {
            $ret .= BML::fill_template("securityprivate");
        }
        elsif ( $sec eq "usemask" ) {
            $ret .= BML::fill_template("securityprotected");
        }
        $ret .= "&nbsp;<i><b>" . $entry->subject_html . "</b></i>";
        $ret .= " p?>\n";

        my $cleanopts = {
            preformatted => $entry->prop('opt_preformatted'),
            cuturl       => $talkurl
        };
        my $truncated;
        my $summary = $entry->event_html_summary( 1000, $cleanopts, \$truncated );

        $ret .= "<?p ";
        $ret .= $summary;
        $ret .= "..." if $truncated;
        $ret .= " p?>\n";
    }

    $ret .=
"<div align=\"center\"><b>(<a href=\"$talkurl\">$BML::ML{'talk.commentsread'}</a>)</b></div>";

    return $ret;
}

# given a journalu and jitemid, return 1 if the entry
# is over the maximum comments allowed.
sub over_maxcomments {
    my ( $journalu, $jitemid ) = @_;
    $journalu = LJ::want_user($journalu);
    $jitemid += 0;
    return 0 unless $journalu && $jitemid;

    my $count = LJ::Talk::get_replycount( $journalu, $jitemid );
    return ( $count >= $journalu->count_maxcomments ) ? 1 : 0;
}

# more anti-spammer rate limiting.  returns 1 if rate is okay, 0 if too fast.
sub check_rate {
    my ( $remote, $journalu ) = @_;

    # we require memcache to do rate limiting efficiently
    return 1 unless @LJ::MEMCACHE_SERVERS;

    # return right away if the account is suspended
    return 0 if $remote && ( $remote->is_suspended || $remote->is_deleted );

    # allow some users to be very aggressive commenters and authors. i.e. our bots.
    return 1
        if $remote
        and grep { $remote->username eq $_ } @LJ::NO_RATE_CHECK_USERS;

    my $ip  = LJ::get_remote_ip();
    my $now = time();
    my @watch;

    if ($remote) {

        # registered human (or human-impersonating robot)
        push @watch,
            [
            "talklog:$remote->{userid}", $LJ::RATE_COMMENT_AUTH || [ [ 200, 3600 ], [ 20, 60 ] ],
            ];
    }
    else {
        # anonymous, per IP address (robot or human)
        push @watch,
            [
            "talklog:$ip",
            $LJ::RATE_COMMENT_ANON || [ [ 300, 3600 ], [ 200, 1800 ], [ 150, 900 ], [ 15, 60 ] ]
            ];

        # anonymous, per journal.
        # this particular limit is intended to combat flooders, instead
        # of the other 'spammer-centric' limits.
        push @watch,
            [
            "talklog:anonin:$journalu->{userid}",
            $LJ::RATE_COMMENT_ANON || [ [ 300, 3600 ], [ 200, 1800 ], [ 150, 900 ], [ 15, 60 ] ]
            ];

        # throttle based on reports of spam
        push @watch,
            [ "spamreports:anon:$ip", $LJ::SPAM_COMMENT_RATE || [ [ 50, 86400 ], [ 10, 3600 ] ] ];
    }

WATCH:
    foreach my $watch (@watch) {
        my ( $key, $rates ) = ( $watch->[0], $watch->[1] );
        my $max_period = $rates->[0]->[1];

        my $log = LJ::MemCache::get($key) || "";

        # parse the old log
        my @times;
        if ( length($log) % 4 == 1 && substr( $log, 0, 1 ) eq $RATE_DATAVER ) {
            my $ct = ( length($log) - 1 ) / 4;
            for ( my $i = 0 ; $i < $ct ; $i++ ) {
                my $time = unpack( "N", substr( $log, $i * 4 + 1, 4 ) );
                push @times, $time if $time > $now - $max_period;
            }
        }

        # add this event unless we're throttling based on spamreports
        push @times, $now unless $key =~ /^spamreports/;

        # check rates
        foreach my $rate (@$rates) {
            my ( $allowed, $period ) = ( $rate->[0], $rate->[1] );
            my $events = scalar grep { $_ > $now - $period } @times;
            if ( $events > $allowed ) {

                if ( $LJ::DEBUG{'talkrate'}
                    && LJ::MemCache::add( "warn:$key", 1, 600 ) )
                {

                    my $ruser = ( exists $remote->{'user'} ) ? $remote->{'user'} : 'Not logged in';
                    my $nowtime = localtime($now);
                    my $body    = <<EOM;
Talk spam from $key:
$events comments > $allowed allowed / $period secs
     Remote user: $ruser
     Remote IP:   $ip
     Time caught: $nowtime
     Posting to:  $journalu->{'user'}
EOM

                    LJ::send_mail(
                        {
                            'to'       => $LJ::DEBUG{'talkrate'},
                            'from'     => $LJ::ADMIN_EMAIL,
                            'fromname' => $LJ::SITENAME,
                            'charset'  => 'utf-8',
                            'subject'  => "talk spam: $key",
                            'body'     => $body,
                        }
                    );
                }    # end sending email

                last WATCH;
            }
        }

        # build the new log
        my $newlog = $RATE_DATAVER;
        foreach (@times) {
            $newlog .= pack( "N", $_ );
        }

        LJ::MemCache::set( $key, $newlog, $max_period );
    }

    return 1;
}

1;
