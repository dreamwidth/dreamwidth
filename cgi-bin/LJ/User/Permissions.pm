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

package LJ::User;
use strict;
no warnings 'uninitialized';

use Carp;

########################################################################
### 8. Userprops, Caps, and Displaying Content to Others

=head2 Userprops, Caps, and Displaying Content to Others
=cut

sub add_to_class {
    my ($u, $class) = @_;
    my $bit = LJ::Capabilities::class_bit( $class );
    die "unknown class '$class'" unless defined $bit;

    # call add_to_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs the new we say we'll be adding
    if (LJ::Hooks::are_hooks('add_to_class')) {
        LJ::Hooks::run_hooks('add_to_class', $u, $class);
    }

    return $u->modify_caps( [$bit], [] );
}


# 1/0 whether the argument is allowed to search this journal
sub allow_search_by {
    my ( $u, $by ) = @_;
    return 0 unless LJ::isu( $u ) && LJ::isu( $by );

    # the person doing the search has to be an individual
    return 0 unless $by->is_individual;

    # someone in the equation has to be a paid account
    return 0 unless $u->is_paid || $by->is_paid;

    # allow searches if this is a community or it's us
    return 1 if $u->is_community || $u->equals( $by );

    # check the userprop for security access
    my $whocan = $u->prop( 'opt_allowsearchby' ) || 'F';
    return 1 if $whocan eq 'A';
    return 1 if $whocan eq 'F' && $u->trusts( $by );
    return 1 if $whocan eq 'N' && $u->equals( $by );

    # failing the above, sorry, no search for you
    return 0;
}

# whether comments are indexed in this journal
sub allow_comments_indexed {
    my ( $u ) = @_;
    return 0 unless LJ::isu( $u );

    # Comments are indexed in paid accounts only
    return 1 if $u->is_paid;

    # Otherwise comments aren't indexed
    return 0;
}

sub caps {
    my $u = shift;
    return $u->{caps};
}

sub can_beta_payments {
    return $_[0]->get_cap( 'beta_payments' ) ? 1 : 0;
}

sub can_buy_icons {
    return $_[0]->get_cap( 'bonus_icons' ) ? 1 : 0;
}

sub can_create_feeds {
    return $_[0]->get_cap( 'synd_create' ) ? 1 : 0;
}

sub can_create_moodthemes {
    return $_[0]->get_cap( 'moodthemecreate' ) ? 1 : 0;
}

sub can_create_polls {
    return $_[0]->get_cap( 'makepoll' ) ? 1 : 0;
}

sub can_create_s2_props {
    return $_[0]->get_cap( 's2props' ) ? 1 : 0;
}

sub can_create_s2_styles {
    return $_[0]->get_cap( 's2styles' ) ? 1 : 0;
}

sub can_edit_comments {
    return $_[0]->get_cap( 'edit_comments' ) ? 1 : 0;
}

sub can_emailpost {
    return $_[0]->get_cap( 'emailpost' ) ? 1 : 0;
}

sub can_find_similar {
    return $_[0]->get_cap( 'findsim' ) ? 1 : 0;
}

sub can_get_comments {
    return $_[0]->get_cap( 'get_comments' ) ? 1 : 0;
}

sub can_get_self_email {
    return $_[0]->get_cap( 'getselfemail' ) ? 1 : 0;
}

sub can_have_email_alias {
    return 0 unless $LJ::USER_EMAIL;
    return $_[0]->get_cap( 'useremail' ) ? 1 : 0;
}

sub can_leave_comments {
    return $_[0]->get_cap( 'leave_comments' ) ? 1 : 0;
}

sub can_manage_invites_light {
    my $u = $_[0];

    return 1 if $u->has_priv( "payments" );
    return 1 if $u->has_priv( "siteadmin", "invites" );

    return 0;
}

sub can_post {
    return $_[0]->get_cap( 'can_post' ) ? 1 : 0;
}

sub can_post_disabled {
    return $_[0]->get_cap( 'disable_can_post' ) ? 1 : 0;
}

sub can_import_comm {
    return $_[0]->get_cap( 'import_comm' ) ? 1 : 0;
}

sub can_receive_vgifts_from {
    my ( $u, $remote, $is_anon ) = @_;
    $remote ||= LJ::get_remote();
    my $valid_remote = LJ::isu( $remote ) && $remote->is_personal ? 1 : 0;

    # no virtual gifts for syndicated accounts
    return 0 if $u->is_syndicated;

    # check for shop status
    return 0 unless exists $LJ::SHOP{vgifts};

    # check for journal ban
    return 0 if $remote && $u->has_banned( $remote );

    # check for anonymous
    return 0 if $is_anon && $u->prop( 'opt_anonvgift_optout' );

    # if the prop isn't set, default to true
    my $prop = $u->prop( 'opt_allowvgiftsfrom' );
    return 1 unless $prop;

    # all: always true; none: always false
    return 1 if $prop eq 'all';
    return 0 if $prop eq 'none';

    # registered: must have $remote
    return $valid_remote if $prop eq 'registered';
    return 0 unless $valid_remote;  # shortcut: skip remaining tests

    # access: anyone on trust/membership list
    return $u->trusts_or_has_member( $remote ) if $prop eq 'access';

    # remaining options not allowed for communities
    return 0 if $u->is_community;

    # circle: also includes watch list
    return $u->watches( $remote ) || $u->trusts( $remote )
        if $prop eq 'circle';

    # only remaining valid option: trust group, which must be numeric.
    # if it's not a valid value, assume false
    return 0 unless $prop =~ /^\d+$/;

    # check the trustmask
    my $mask = 1 << $prop;
    return ( $u->trustmask( $remote ) & $mask );
}

sub can_show_location {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);
    my $remote = LJ::get_remote();

    return 0 if $u->opt_showlocation eq 'N';
    return 0 if $u->opt_showlocation eq 'R' && !$remote;
    return 0 if $u->opt_showlocation eq 'F' && !$u->trusts( $remote );
    return 1;
}


# The option to track all comments is available to:
# -- community admins for any community they manage
# -- all users if community's seed or premium paid
# -- members only if community's paid
sub can_track_all_community_comments {
    my ( $remote, $journal ) = @_;
     return 1 if LJ::isu( $journal ) && $journal->is_community
                 && ( $remote->can_manage_other( $journal )
                    || $journal->get_cap( 'track_all_comments' )
                    || $journal->is_paid && $remote->member_of( $journal ) );
}

sub can_track_defriending {
    return $_[0]->get_cap( 'track_defriended' ) ? 1 : 0;
}

sub can_track_new_userpic {
    return $_[0]->get_cap( 'track_user_newuserpic' ) ? 1 : 0;
}

sub can_track_pollvotes {
    return $_[0]->get_cap( 'track_pollvotes' ) ? 1 : 0;
}

sub can_track_thread {
    return $_[0]->get_cap( 'track_thread' ) ? 1 : 0;
}

sub can_use_checkforupdates {
    return $_[0]->get_cap( 'checkfriends' ) ? 1 : 0;
}

sub can_use_daily_readpage {
    return $_[0]->get_cap( 'friendspage_per_day' ) ? 1 : 0;
}

sub can_use_directory {
    return $_[0]->get_cap( 'directory' ) ? 1 : 0;
}

sub can_use_fastlane {
    return $_[0]->get_cap( 'fastserver' ) ? 1 : 0;
}

sub can_use_full_rss {
    return $_[0]->get_cap( 'full_rss' ) ? 1 : 0;
}

sub can_use_google_analytics {
    return $_[0]->get_cap( 'google_analytics' ) ? 1 : 0;
}

sub can_use_latest_comments_rss {
    return $_[0]->get_cap( 'latest_comments_rss' ) ? 1 : 0;
}

sub can_use_mass_privacy {
    return $_[0]->get_cap( 'mass_privacy' ) ? 1 : 0;
}

sub can_use_popsubscriptions {
    return $_[0]->get_cap( 'popsubscriptions' ) ? 1 : 0;
}

sub can_use_network_page {
    return 0 unless $_[0]->get_cap( 'friendsfriendsview' ) && $_[0]->is_person;
}


sub can_use_active_entries {
    return $_[0]->get_cap( 'activeentries' ) ? 1 : 0;
}

# Check if the user can use *any* page statistic module for their own journal.
sub can_use_page_statistics {
    return $_[0]->can_use_google_analytics;
}

sub can_use_userpic_select {
    return 0 unless LJ::is_enabled( 'userpicselect' );
    return $_[0]->get_cap( 'userpicselect' ) ? 1 : 0;
}

sub can_view_mailqueue {
    return $_[0]->get_cap( 'viewmailqueue' ) ? 1 : 0;
}

sub captcha_type {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( captcha => $_[1] );
    }

    return $_[1] || $u->prop( 'captcha' ) || $LJ::DEFAULT_CAPTCHA_TYPE;
}

sub cc_msg {
    my ( $u, $value ) = @_;
    if ( defined $value && $value=~ /[01]/ ) {
       $u->set_prop( cc_msg => $value );
       return $value;
    }

    return $u->prop( 'cc_msg' ) ? 1 : 0;
}

sub clear_prop {
    my ($u, $prop) = @_;
    $u->set_prop($prop, undef);
    return 1;
}

=head3 C<< $self->clear_daycounts( @security ) >>

Clears the day counts relevant to the entry security

security is an array of strings: "public", a number (allowmask), "private"

=cut

sub clear_daycounts
{
    my ( $u, @security ) = @_;

    return undef unless LJ::isu( $u );
    # if old and new security are equal, don't clear the day counts
    return undef if scalar @security == 2 && $security[0] eq $security[1];

    # memkind can be one of:
    #  a = all entries in this journal
    #  g# = access or groupmask
    #  p = only public entries
    my @memkind;
    my $access = 0;
    foreach my $security ( @security )
    {
        push @memkind, "p" if $security eq 'public'; # public
        push @memkind, "g$security" if $security =~ /^\d+/;

        $access++ if $security eq 'public' || ( $security =~ /^\d+/ && $security != 1 );
    }
    # clear access only security, but does not cover custom groups
    push @memkind, "g1" if $access;

    # any change to any entry security means this must be expired
    push @memkind, "a";

    foreach my $memkind ( @memkind )
    {
        LJ::MemCache::delete( [ $u->userid, "dayct2:" . $u->userid . ":$memkind" ] );
    }
}

sub optout_community_promo {
    my ( $u, $val ) = @_;

    if ( defined $val && $val =~ /^[01]$/ ) {
        $u->set_prop( optout_community_promo => $val );
        return $val;
    }

    return $u->prop( 'optout_community_promo' ) ? 1 : 0;
}

sub community_invite_members_url {
    return "$LJ::SITEROOT/communities/" . $_[0]->user . "/members/new";
}

sub community_manage_members_url {
    return "$LJ::SITEROOT/communities/" . $_[0]->user . "/members/edit";
}

sub control_strip_display {
    my $u = shift;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'control_strip_display' );
    return 0 if $prop_val eq 'none';
    return $prop_val if $prop_val =~ /^\d+$/;

    # otherwise, return the default: all options checked
    my $ret;
    my @pageoptions = LJ::Hooks::run_hook( 'page_control_strip_options' );
    for ( my $i = 0; $i < scalar @pageoptions; $i++ ) {
        $ret |= 1 << $i;
    }

    return $ret ? $ret : 0;
}

sub count_bookmark_max {
    return $_[0]->get_cap( 'bookmark_max' );
}

sub count_inbox_max {
    return $_[0]->get_cap( 'inbox_max' );
}

sub count_maxcomments {
    return $_[0]->get_cap( 'maxcomments' );
}

sub count_maxcomments_before_captcha {
    return $_[0]->get_cap( 'maxcomments-before-captcha' );
}

sub count_maxfriends {
    return $_[0]->get_cap( 'maxfriends' );
}

sub count_max_interests {
    return $_[0]->get_cap( 'interests' );
}

sub count_max_mod_queue {
    return $_[0]->get_cap( 'mod_queue' );
}

sub count_max_mod_queue_per_poster {
    return $_[0]->get_cap( 'mod_queue_per_poster' );
}

sub count_max_stickies {
    return $_[0]->get_cap( 'stickies' );
}

sub count_max_subscriptions {
    return $_[0]->get_cap( 'subscriptions' );
}

sub count_max_userlinks {
    return $_[0]->get_cap( 'userlinks' );
}

sub count_max_userpics {
    return $_[0]->userpic_quota;
}

sub count_max_xpost_accounts {
    return $_[0]->get_cap( 'xpost_accounts' );
}

sub count_recent_comments_display {
    return $_[0]->get_cap( 'tools_recent_comments_display' );
}

sub count_s2layersmax {
    return $_[0]->get_cap( 's2layersmax' );
}

sub count_s2stylesmax {
    return $_[0]->get_cap( 's2stylesmax' );
}

sub count_tags_max {
    return $_[0]->get_cap( 'tags_max' );
}

sub count_usermessage_length {
    return $_[0]->get_cap( 'usermessage_length' );
}

# returns the country specified by the user
sub country {
    return $_[0]->prop( 'country' );
}

sub disable_auto_formatting {
    my ( $u, $value ) = @_;
    if ( defined $value && $value =~ /[01]/ ) {
        $u->set_prop( disable_auto_formatting => $value );
        return $value;
    }

    return $u->prop( 'disable_auto_formatting' ) ? 1 : 0;
}

sub displaydate_check {
    my ( $u, $value ) = @_;
    if ( defined $value && $value =~ /[01]/ ) {
        $u->set_prop( displaydate_check => $value );
        return $value;
    }

    return $u->prop( 'displaydate_check' ) ? 1 : 0;
}

sub exclude_from_own_stats {
    my $u = shift;

    if ( defined $_[0] && $_[0] =~ /[01]/ ) {
        $u->set_prop( exclude_from_own_stats => $_[0] );
        return $_[0];
    }

    return $u->prop( 'exclude_from_own_stats' ) ? 1 : 0;
}

# returns the max capability ($cname) for all the classes
# the user is a member of
sub get_cap {
    my ( $u, $cname ) = @_;

    # turn on all caps for tests, except the read-only cap
    return 1 if $LJ::T_HAS_ALL_CAPS && $cname ne "readonly";
    return LJ::get_cap( $u, $cname );
}

# returns the gift shop URL to buy a gift for that user
sub gift_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/account?for=gift&user=" . $u->user;
}


# returns the gift shop URL to buy points for that user
sub gift_points_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/points?for=" . $u->user;
}

# returns the gift shop URL to transfer your own points to that user
sub transfer_points_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/transferpoints?for=" . $u->user;
}

# returns the shop URL to buy a virtual gift for that user
sub virtual_gift_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/vgift?user=" . $u->user;
}

=head3 C<< $self->give_shop_points( %options ) >>

The options hash MUST contain the following keys:

=over 4

=item amount

How many points to give the user.  May be positive or negative, s
use a negative number to deduct points from a user's balance.  Will not allow
a user's balance to go negative.

=item reason

A short description of why this transaction is happening.  For
example: 'purchase of cart 9883463'.

=back

The options hash MAY contain these keys, as well:

=over 4

=item admin

If this action was being done by an administrator, pass their userid
or user object here.  This helps us record when admins make things happen.

=back

Example usage:

C<<   $self->give_shop_points( amount => 50, reason => 'purchased' ); >>

This gives 50 points to the user as a routine purchase.

C<<   $self->give_shop_points( amount => -100, reason => 'refund', admin => $remote ); >>

Admin processed refund, remove 100 points from the user's balance.

Returns a true value on success, undef on error.

=cut

sub give_shop_points {
    my ( $self, %opts ) = @_;
    return unless LJ::isu( $self );

    # do some cleanup on our input parameters
    $opts{amount} += 0;
    $opts{reason} = LJ::trim( $opts{reason} );
    return unless $opts{amount} && $opts{reason};

    # ensure we're not going negative ...
    my $old = $self->shop_points;
    die "Unable to set points balance to negative value.\n"
        if $old + $opts{amount} < 0;

    # log the change first so we know what's going on
    my $admin = $opts{admin} ? LJ::want_user( $opts{admin} ) : undef;
    my $msg = sprintf( 'old balance: %d, adjust amount: %d, reason: %s', $old, $opts{amount}, $opts{reason} );
    LJ::statushistory_add( $self->id, $admin ? $admin->id : undef, 'shop_points', $msg);

    # finally set the value
    $self->set_prop( shop_points => $old + $opts{amount } );
    return 1;
}


# get/set the Google Analytics ID
sub google_analytics {
    my $u = shift;

    if ( defined $_[0] ) {
        $u->set_prop( google_analytics => $_[0] );
        return $_[0];
    }

    return $u->prop( 'google_analytics' );
}


# is there a suspend note?
sub get_suspend_note {
    my $u = $_[0];
    return $u->prop( 'suspendmsg' );
}

# get/set post to community link visibility
sub hide_join_post_link {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( hide_join_post_link => $_[1] );
        return $_[1];
    }

    return $u->prop( 'hide_join_post_link' );
}

=head3 C<< $self->iconbrowser_metatext( [ $arg ] ) >>

If no argument, returns whether to show meta text in the icon browser or not.
Default is to show meta text (true)

If argument is passed in, acts as setter. Argument can be "Y" / "N"

=cut

sub iconbrowser_metatext {
    my $u = $_[0];

    if ( $_[1] ) {
        my $newval = $_[1] eq "N" ? "N": undef;
        $u->set_prop( iconbrowser_metatext => $newval );
    }

    return  ( $_[1] || $u->prop( 'iconbrowser_metatext' ) || "Y" ) eq 'Y' ? 1 : 0;
}


=head3 C<< $self->iconbrowser_smallicons( [ $small_icons ] ) >>

If no argument, returns whether to show small icons in the icon browser or large.
Default is large.

If argument is passed in, acts as setter. Argument can be "Y" / "N"

=cut

sub iconbrowser_smallicons {
    my $u = $_[0];

    if ( $_[1] ) {
        my $newval = $_[1] eq "Y" ? "Y" : undef;
        $u->set_prop( iconbrowser_smallicons => $newval );
    }

    return  ( $_[1] || $u->prop( 'iconbrowser_smallicons' ) || "N" ) eq 'Y' ? 1 : 0;
}

# whether to respect cut tags in the inbox
sub cut_inbox {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( cut_inbox => $_[1] );
    }

    return  ( $_[1] || $u->prop( 'cut_inbox' ) || "N" ) eq 'Y' ? 1 : 0;
}

# tests to see if a user is in a specific named class. class
# names are site-specific.
sub in_class {
    my ($u, $class) = @_;
    return LJ::Capabilities::caps_in_group( $u->{caps}, $class );
}


# 1/0; whether or not this account should be included in the global search
# system.  this is used by the bin/worker/sphinx-copier mostly.
sub include_in_global_search {
    my $u = $_[0];

    # only P/C accounts should be globally searched
    return 0 unless $u->is_person || $u->is_community;

    # default) check opt_blockglobalsearch and use that if it's defined
    my $bgs = $u->prop( 'opt_blockglobalsearch' );
    return $bgs eq 'Y' ? 0 : 1 if defined $bgs && length $bgs;

    # fallback) use their robot blocking value if it's set
    my $br = $u->prop( 'opt_blockrobots' );
    return $br ? 0 : 1 if defined $br && length $br;

    # allow search of this user's content
    return 1;
}


# whether this user wants to have their content included in the latest feeds or not
sub include_in_latest_feed {
    my $u = $_[0];
    return $u->prop( 'latest_optout' ) ? 0 : 1;
}


# must be called whenever birthday, location, journal modtime, journaltype, etc.
# changes.  see LJ/Directory/PackedUserRecord.pm
sub invalidate_directory_record {
    my $u = shift;

    # Future: ?
    # LJ::try_our_best_to("invalidate_directory_record", $u->id);
    # then elsewhere, map that key to subref.  if primary run fails,
    # put in schwartz, then have one worker (misc-deferred) to
    # redo...

    my $dbs = defined $LJ::USERSEARCH_DB_WRITER ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER) : LJ::get_db_writer();
    $dbs->do("UPDATE usersearch_packdata SET good_until=0 WHERE userid=?",
             undef, $u->id);
}


# <LJFUNC>
# name: LJ::User::large_journal_icon
# des: get the large icon by journal type.
# returns: HTML to display large journal icon.
# </LJFUNC>
sub large_journal_icon {
    my $u = shift;
    croak "invalid user object"
        unless LJ::isu($u);

    my $wrap_img = sub {
        my $type = $_[0];
        return LJ::img( "id_$type-24", "",
                        { border => 0, style => 'padding: 0px 2px 0px 0px' } );
    };

    return $wrap_img->( "community" ) if $u->is_comm;

    return $wrap_img->( "feed" ) if $u->is_syndicated;

    return $wrap_img->( "openid" ) if $u->is_identity;

    # personal or unknown fallthrough
    return $wrap_img->( "user" );
}

sub moderation_queue_url {
    my ( $u, $modid ) = @_;
    my $base_url = "$LJ::SITEROOT/communities/" . $_[0]->user . "/queue/entries";
    return $modid ? "$base_url/$modid" : $base_url;
}

sub member_queue_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/communities/" . $_[0]->user . "/queue/members";
}

# des: Given a list of caps to add and caps to remove, updates a user's caps.
# args: cap_add, cap_del, res
# des-cap_add: arrayref of bit numbers to turn on
# des-cap_del: arrayref of bit numbers to turn off
# des-res: hashref returned from 'modify_caps' hook
# returns: updated u object, retrieved from $dbh, then 'caps' key modified
#          otherwise, returns 0 unless all hooks run properly.
sub modify_caps {
    my ( $argu, $cap_add, $cap_del, $res ) = @_;
    my $userid = LJ::want_userid( $argu );
    return undef unless $userid;

    $cap_add ||= [];
    $cap_del ||= [];
    my %cap_add_mod = ();
    my %cap_del_mod = ();

    # convert capnames to bit numbers
    if ( LJ::Hooks::are_hooks( "get_cap_bit" ) ) {
        foreach my $bit ( @$cap_add, @$cap_del ) {
            next if $bit =~ /^\d+$/;

            # bit is a magical reference into the array
            $bit = LJ::Hooks::run_hook( "get_cap_bit", $bit );
        }
    }

    # get a u object directly from the db
    my $u = LJ::load_userid( $userid, "force" ) or return;

    # add new caps
    my $newcaps = int( $u->{caps} );
    foreach ( @$cap_add ) {
        my $cap = 1 << $_;

        # about to turn bit on, is currently off?
        $cap_add_mod{$_} = 1 unless $newcaps & $cap;
        $newcaps |= $cap;
    }

    # remove deleted caps
    foreach ( @$cap_del ) {
        my $cap = 1 << $_;

        # about to turn bit off, is it currently on?
        $cap_del_mod{$_} = 1 if $newcaps & $cap;
        $newcaps &= ~$cap;
    }

    # run hooks for modified bits
    if ( LJ::Hooks::are_hooks( "modify_caps" ) ) {
        $res = LJ::Hooks::run_hook( "modify_caps",
             { u => $u,
               newcaps => $newcaps,
               oldcaps => $u->{caps},
               cap_on_req  => { map { $_ => 1 } @$cap_add },
               cap_off_req => { map { $_ => 1 } @$cap_del },
               cap_on_mod  => \%cap_add_mod,
               cap_off_mod => \%cap_del_mod } );

        # hook should return a status code
        return undef unless defined $res;
    }

    # update user row
    return 0 unless $u->update_self( { caps => $newcaps } );

    $u->{caps} = $newcaps;
    $argu->{caps} = $newcaps;
    return $u;
}


sub opt_logcommentips {
    my $u = shift;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'opt_logcommentips' );
    return $prop_val if $prop_val =~ /^[NSA]$/;

    # otherwise, return the default: log for all comments
    return 'A';
}

sub opt_nctalklinks {
    my ( $u, $val ) = @_;

    if ( defined $val && $val =~ /^[01]$/ ) {
        $u->set_prop( opt_nctalklinks => $val );
        return $val;
    }

    return $u->prop( 'opt_nctalklinks' ) eq "1" ? 1 : 0;
}

sub opt_randompaidgifts {
    my $u = shift;

    return $u->prop( 'opt_randompaidgifts' ) eq 'N' ? 0 : 1;
}

sub opt_showcontact {
    my $u = shift;

    if ($u->{'allow_contactshow'} =~ /^(N|Y|R|F)$/) {
        return $u->{'allow_contactshow'};
    } else {
        return 'F' if $u->is_minor;
        return 'Y';
    }
}


sub opt_showlocation {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # see comments for opt_showbday
    unless ( LJ::is_enabled('infoshow_migrate') || $u->{allow_infoshow} eq ' ' ) {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showlocation') =~ /^(N|Y|R|F)$/) {
        return $u->raw_prop('opt_showlocation');
    } else {
        return 'F' if ($u->is_minor);
        return 'Y';
    }
}


sub opt_whatemailshow {
    my $u = $_[0];

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'opt_whatemailshow' ) || '';
    $prop_val =~ tr/BVL/ADN/ unless $u->can_have_email_alias;
    return $prop_val if $prop_val =~ /^[ALBNDV]$/;

    # otherwise, return the default: no email shown
    return 'N';
}


# get/set community's guidelines entry ditemid
sub posting_guidelines_entry {
    my ( $u, $args ) = @_;

    if ( defined $args ) {
        unless ( $args ) {
            $u->set_prop( posting_guidelines_entry => '' );
            return 1;
        }
        my $ditemid;
        if ( $args =~ m!/(\d+)\.html! ) {
            $ditemid = $1;
        } elsif ( $args =~ m!^(\d+)$! ) {
            $ditemid = $1;
        } else {
            return 0;
        }

        my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
        return 0 unless $entry && $entry->valid;

        $u->set_prop( posting_guidelines_entry => $ditemid );
        return $ditemid;
    }

    return $u->prop( 'posting_guidelines_entry' );
}


# get community's guidelines entry as entry object
sub get_posting_guidelines_entry {
    my $u = shift;

    if ( my $ditemid = $u->posting_guidelines_entry ) {
        my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
        return $entry if $entry->valid;
    }

    return undef;
}

sub posting_guidelines_url {
    my $u = $_[0];

    return "" unless $u->is_community;

    my $posting_guidelines = $u->posting_guidelines_entry;
    if ( $u->posting_guidelines_location eq "P" ) {
        return $u->profile_url;
    } elsif ( $u->posting_guidelines_location eq "N") {
        return "";
    }

    return "" unless $posting_guidelines;

    return $u->journal_base . "/guidelines";
}

# Where are a community's posting guidelines held?  Blank=Nowhere, P=Profile, E=Entry
sub posting_guidelines_location {
    my ( $u,  $value ) = @_;
    if ( defined $value && $value=~ /[PE]/ ) {
        $u->set_prop( posting_guidelines_location => $value );
        return $value;
    }
    # We store the "N=Nowhere" option in the database as a blank empty entry to
    # reduce space.  N should be returned whenever a blank entry is encountered.
    if ( defined $value && $value eq 'N' ) {
        $u->set_prop( posting_guidelines_location => '' );
        return $value;
    }
    $u->prop( 'posting_guidelines_location' ) || $LJ::DEFAULT_POSTING_GUIDELINES_LOC;
}


sub profile_url {
    my ( $u, %opts ) = @_;

    my $url;
    if ( $u->is_identity ) {
        $url = "$LJ::SITEROOT/profile?userid=" . $u->userid . "&t=I";
        $url .= "&mode=full" if $opts{full};
    } else {
        $url = $u->journal_base . "/profile";
        $url .= "?mode=full" if $opts{full};
    }
    return $url;
}


# get/set the displayed email on profile (if user has specified)
sub profile_email {
    my ( $u, $email ) = @_;

    if ( defined $email ) {
        $u->set_prop( opt_profileemail => $email );
        return $email;
    }

    return $u->prop( 'opt_profileemail' );
}


# instance method:  returns userprop for a user.  currently from cache with no
# way yet to force master.
sub prop {
    my ($u, $prop) = @_;

    # some props have accessors which do crazy things, if so they need
    # to be redirected from this method, which only loads raw values
    if ({ map { $_ => 1 }
          qw(opt_sharebday opt_showbday opt_showlocation opt_showmutualfriends
             view_control_strip show_control_strip opt_ctxpopup opt_embedplaceholders
             esn_inbox_default_expand)
        }->{$prop})
    {
        return $u->$prop;
    }

    return $u->raw_prop($prop);
}


# returns the user's public key
sub public_key {
    $_[0]->prop( 'public_key' );
}


sub raw_prop {
    my ($u, $prop) = @_;
    $u->preload_props($prop) unless exists $u->{$prop};
    return $u->{$prop};
}


sub remove_from_class {
    my ($u, $class) = @_;
    my $bit = LJ::Capabilities::class_bit( $class );
    die "unknown class '$class'" unless defined $bit;

    # call remove_from_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs what we'll be removing
    if (LJ::Hooks::are_hooks('remove_from_class')) {
        LJ::Hooks::run_hooks('remove_from_class', $u, $class);
    }

    return $u->modify_caps( [], [$bit] );
}


# Sets/deletes userprop(s) by name for a user.
# This adds or deletes from the [dbtable[userprop]]/[dbtable[userproplite]]
# tables, and also updates $u's cached version. Can set $prop => $value
# or also accepts a hashref of propname keys and corresponding values.
# Returns boolean indicating success or failure.
sub set_prop {
    my ( $u, $prop, $value, $opts ) = @_;
    my $userid = $u->userid + 0;
    my $hash = ref $prop eq "HASH" ? $prop : { $prop => $value };
    $opts ||= {};

    my %action;  # $table -> {"replace"|"delete"} -> [ "($propid, $qvalue)" | propid ]
    my %multihomed;  # { $propid => $value }
    my %propnames;   # { $propid => $propname }

    # enforce limits on data in the code
    # to make sure that memcache and db data are consistent after a save
    my %table_values_lengths = (
        userprop => 60,
        userproplite => 255,
        userproplite2 => 255,
        # userpropblob => ...,
    );

    # Accumulate prepared actions.
    foreach my $propname ( keys %$hash ) {
        $value = $hash->{$propname};

        # Call all hooks, since we don't look at the return values.
        # We expect anybody who uses this hook to do the extra work
        # a property needs when it is set.
        LJ::Hooks::run_hooks( 'setprop', prop => $propname, u => $u, value => $value );

        my $p = LJ::get_prop( "user", $propname ) or
            die "Attempted to set invalid userprop $propname.";
        $propnames{ $p->{id} } = $propname;

        if ( $p->{multihomed} ) {
            # collect into array for later handling
            $multihomed{ $p->{id} } = $value;
            next;
        }
        # if not multihomed, select appropriate table
        my $table = 'userproplite';  # default
        $table = 'userprop' if $p->{indexed};
        $table = 'userproplite2' if $p->{cldversion}
                                 && $u->dversion >= $p->{cldversion};
        $table = 'userpropblob' if $p->{datatype} eq 'blobchar';

        # only assign db for update action if value has changed
        unless ( $opts->{skip_db} && $value eq $u->{$propname} ) {
            my $db = $action{$table}->{db} ||= (
                $table !~ m{userprop(lite2|blob)}
                    ? LJ::get_db_writer()  # global
                    : $u->writer );        # clustered
            return 0 unless $db;  # failure to get db handle
        }

        # determine if this is a replacement or a deletion
        if ( defined $value && $value ) {
            $value = LJ::text_trim( $value, undef, $table_values_lengths{$table} )
                        if defined $table_values_lengths{$table};
            push @{ $action{$table}->{replace} }, [ $p->{id}, $value ];
        } else {
            push @{ $action{$table}->{delete} }, $p->{id};
        }
    }

    # keep in memcache for 24 hours and update user object in memory
    my $memc = sub {
        my ( $p, $v ) = @_;
        LJ::MemCache::set( [ $userid, "uprop:$userid:$p" ], $v, 3600 * 24 );
        $u->{ $propnames{$p} } = $v eq "" ? undef : $v;
    };

    # Execute prepared actions.
    foreach my $table ( keys %action ) {
        my $db = $action{$table}->{db};
        if ( my $list = $action{$table}->{replace} ) {
            if ( $db ) {
                my $vals = join( ',', map { "($userid,$_->[0]," . $db->quote( $_->[1] ) . ")" } @$list );
                $db->do( "REPLACE INTO $table (userid, upropid, value) VALUES $vals" );
                die $db->errstr if $db->err;
            }
            $memc->( $_->[0], $_->[1] ) foreach @$list;
        }
        if ( my $list = $action{$table}->{delete} ) {
            if ( $db ) {
                my $in = join( ',', @$list );
                $db->do( "DELETE FROM $table WHERE userid=$userid AND upropid IN ($in)" );
                die $db->errstr if $db->err;
            }
            $memc->( $_, "" ) foreach @$list;
        }
    }

    # if we had any multihomed props, set them here
    if ( %multihomed ) {
        my $dbh = LJ::get_db_writer();
        return 0 unless $dbh && $u->writer;

        while ( my ( $propid, $pvalue ) = each %multihomed ) {
            if ( defined $pvalue && $pvalue ) {
                my $uprop_pvalue = LJ::text_trim( $pvalue, undef, $table_values_lengths{userprop} );

                # replace data into master
                $dbh->do( "REPLACE INTO userprop VALUES (?, ?, ?)",
                          undef, $userid, $propid, $uprop_pvalue );
            } else {
                # delete data from master, but keep in cluster
                $dbh->do( "DELETE FROM userprop WHERE userid = ? AND upropid = ?",
                          undef, $userid, $propid );
            }

            # fail out?
            return 0 if $dbh->err;

            # put data in cluster
            $pvalue = $pvalue ? LJ::text_trim( $pvalue, undef, $table_values_lengths{userproplite2} ) : '';
            $u->do( "REPLACE INTO userproplite2 VALUES (?, ?, ?)",
                    undef, $userid, $propid, $pvalue );
            return 0 if $u->err;

            # set memcache and update user object
            $memc->( $propid, $pvalue );
        }
    }

    return 1;
}


sub share_contactinfo {
    my ($u, $remote) = @_;

    return 0 if $u->is_syndicated;
    return 0 if $u->opt_showcontact eq 'N';
    return 0 if $u->opt_showcontact eq 'R' && !$remote;
    return 0 if $u->opt_showcontact eq 'F' && !$u->trusts( $remote );
    return 1;
}


=head3 C<< $self->shop_points >>

Returns how many points this user currently has available for spending in the
shop.  For adjusting points on a user, please see C<<$self->give_shop_points>>.

=cut

sub shop_points {
    # force false value to be 0 instead of any other false value
    # useful to make sure this gets printed out as "0" in the frontend
    return $_[0]->prop( 'shop_points' ) || 0;
}


sub should_block_robots {
    my $u = shift;

    return 1 if $u->is_syndicated;
    return 1 if $u->is_identity;
    return 1 if $u->prop('opt_blockrobots');

    return 0 unless LJ::is_enabled( 'adult_content' );

    my $adult_content = $u->adult_content_calculated;

    return 1 if $LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 0;
}


sub support_points_count {
    my $u = shift;

    my $dbr = LJ::get_db_reader();
    my $userid = $u->id;
    my $count;

    $count = $u->{_supportpointsum};
    return $count if defined $count;

    my $memkey = [$userid, "supportpointsum:$userid"];
    $count = LJ::MemCache::get($memkey);
    if (defined $count) {
        $u->{_supportpointsum} = $count;
        return $count;
    }

    $count = $dbr->selectrow_array("SELECT totpoints FROM supportpointsum WHERE userid=?", undef, $userid) || 0;
    $u->{_supportpointsum} = $count;
    LJ::MemCache::set($memkey, $count, 60*5);

    return $count;
}


# should show the thread expander for this user/journal
sub show_thread_expander {
    my ( $u, $remote ) = @_;

    return 1 if $remote && $remote->get_cap( 'thread_expander' )
        || $u->get_cap( 'thread_expander' );

    return 0;
}

# should allow expand-all for this user/journal
sub thread_expand_all {
    my ( $u, $remote ) = @_;

    return 1 if $remote && $remote->get_cap( 'thread_expand_all' )
        || $u->get_cap( 'thread_expand_all' );

    return 0;
}

# get/set Sticky Entry parent ID for settings menu
# Expects an array of entry URLs or ditemids as input
# If used as a setter, returns 1 or undef
# Otherwise, returns an array of entry objects
sub sticky_entries {
    my ( $u, $input_ref ) = @_;

    # The user may have previously had an account type that allowed more stickes.
    # we want to preserve a record of these additional stickes in case they once
    # more upgrade their account.  This means we must first extract these
    # if they exist.
    my @entry_ids = $u->sticky_entry_ids;

    my $max_sticky_count = $u->count_max_stickies || 0;
    my $entry_length = @entry_ids;

    my @currently_unused_stickies = @entry_ids[$max_sticky_count..$entry_length];

    # Check we've been sent input and it isn't empty.  If so we need to alter the sticky entries stored.
    if ( defined $input_ref ) {
        my @input = @$input_ref;

        unless ( scalar @input ) {
            $u->set_prop( sticky_entry => '' );
            return 1;
        }

        # sanity check the elements of the input array of candidate stickies.
        my $new_sticky_count = 0;
        foreach my $sticky_input ( @input ) {
            $new_sticky_count++;

            my $e = LJ::Entry->new_from_url_or_ditemid( LJ::trim( $sticky_input ), $u );
            return undef unless $e && $e->valid;
        }

        # The user may have reused a sticky from before their account was downgraded.  To keep
        # stickies unique we should remove this from the list of unused stickies.
        my @new_unused_stickies;
        # We create a hash from the input for quick membership checking.
        my %sticky_hash = map { $_ =>  1 } @input;
        foreach my $unused_sticky ( @currently_unused_stickies ) {
            push @new_unused_stickies, $unused_sticky unless exists $sticky_hash{$unused_sticky};
        }

        # This shouldn't happen but, just in case, we check the number of new stickies and
        # if we have more than we're allowed we trim the input array accordingly.
        @input = @input[0..$max_sticky_count-1] unless $new_sticky_count < $max_sticky_count;

        # We add the currently_unused_stickies onto the end of the new stickies.
        # This has the side effect that, if the user hasn't allocated all their
        # sticky quota but has previously used more than their quota that some of their
        # old stickies will "shuffle up" to fill in the space.
        my $sticky_entry = join( ',', ( @input, @new_unused_stickies ) );
        $u->set_prop( sticky_entry => $sticky_entry );
        return 1;
    }

    my @entries = map { LJ::Entry->new( $u, ditemid => $_ ) } @entry_ids;
    @entries = @entries[0..$max_sticky_count-1] if scalar @entries > $max_sticky_count;
    return @entries;
}

# returns a list of sticky entry ids
sub sticky_entry_ids {
    my $prop = $_[0]->prop( 'sticky_entry' );
    return unless defined $prop;
    return split /,/, $prop;
}

# returns a map of ditemid => 1 of the sticky entries
sub sticky_entries_lookup {
    return { map { $_ => 1 } $_[0]->sticky_entry_ids };
}

# Make a particular entry into a particular sticky.
sub sticky_entry_new {
    my ( $u, $ditemid ) = @_;

    my @stickies = $u->sticky_entry_ids;
    return undef if scalar @stickies >= $u->count_max_stickies;

    unshift @stickies, $ditemid;
    my $sticky_entry_list = join( ',', @stickies );

    $u->set_prop( sticky_entry => $sticky_entry_list );

    return 1;
}

# Remove a particular entry from the sticky list
sub sticky_entry_remove {
    my ( $u, $ditemid ) = @_;

    my @new_stickies  = grep { $_ != $ditemid } $u->sticky_entry_ids;

    my $sticky_entry = join( ',', @new_stickies );
    $u->set_prop( sticky_entry => $sticky_entry );

    return 1;
}


# should times be displayed in 24-hour time format?
sub use_24hour_time { $_[0]->prop( 'timeformat_24' ) ? 1 : 0; }

sub _lazy_migrate_infoshow {
    my ($u) = @_;
    return 1 unless LJ::is_enabled('infoshow_migrate');

    # 1) column exists, but value is migrated
    # 2) column has died from 'user')
    if ($u->{allow_infoshow} eq ' ' || ! $u->{allow_infoshow}) {
        return 1; # nothing to do
    }

    my $infoval = $u->{allow_infoshow} eq 'Y' ? undef : 'N';

    # need to migrate allow_infoshow => opt_showbday
    if ($infoval) {
        foreach my $prop (qw(opt_showbday opt_showlocation)) {
            $u->set_prop($prop => $infoval);
        }
    }

    # setting allow_infoshow to ' ' means we've migrated it
    $u->update_self( { allow_infoshow => ' ' } )
        or die "unable to update user after infoshow migration";
    $u->{allow_infoshow} = ' ';

    return 1;
}


########################################################################
###  22. Priv-Related Functions


sub grant_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||= "";
    my $dbh = LJ::get_db_writer();

    return 1 if $u->has_priv( $priv, $arg );

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("INSERT INTO priv_map (userid, prlid, arg) VALUES (?, ?, ?)",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    return 1;
}

sub has_priv {
    my ( $u, $priv, $arg ) = @_;

    # check to see if the priv is packed, and unpack it if so, this allows
    # someone to call $u->has_priv( "foo:*" ) instead of $u->has_priv( foo => '*' )
    # which is helpful for some callers.
    ( $priv, $arg ) = ( $1, $2 )
        if $priv =~ /^(.+?):(.+)$/;

    # at this point, if they didn't provide us with a priv, bail out
    return 0 unless $priv;

    # load what privileges the user has, if we haven't
    $u->load_user_privs( $priv )
        unless $u->{'_privloaded'}->{$priv};

    # no access if they don't have the priv
    return 0 unless defined $u->{'_priv'}->{$priv};

    # at this point we know they have the priv
    return 1 unless defined $arg;

    # check if they have the right arguments
    return 1 if defined $u->{'_priv'}->{$priv}->{$arg};
    return 1 if defined $u->{'_priv'}->{$priv}->{"*"};

    # don't have the right argument
    return 0;
}

# des: loads all of the given privs for a given user into a hashref, inside
#      the user record.
# args: u, priv, arg?
# des-priv: Priv names to load (see [dbtable[priv_list]]).
# des-arg: Optional argument.
# returns: boolean
sub load_user_privs {
    my ( $remote, @privs ) = @_;
    return unless $remote and @privs;

    # return if we've already loaded these privs for this user.
    @privs = grep { ! $remote->{'_privloaded'}->{$_} } @privs;
    return unless @privs;

    my $dbr = LJ::get_db_reader() or return;
    $remote->{'_privloaded'}->{$_}++ foreach @privs;
    my $bind = join ',', map { '?' } @privs;
    my $sth = $dbr->prepare( "SELECT pl.privcode, pm.arg ".
                             "FROM priv_map pm, priv_list pl ".
                             "WHERE pm.prlid=pl.prlid AND ".
                             "pm.userid=? AND pl.privcode IN ($bind)" );
    $sth->execute( $remote->userid, @privs );
    while ( my ($priv, $arg) = $sth->fetchrow_array ) {
        $arg = "" unless defined $arg;  # NULL -> ""
        $remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}

sub priv_args {
    my ( $u, $priv ) = @_;
    return unless $priv && $u->has_priv( $priv );
    # returns hash of form { arg => 1 }
    return %{ $u->{'_priv'}->{$priv} };
}


sub revoke_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||="";
    my $dbh = LJ::get_db_writer();

    return 1 unless $u->has_priv( $priv, $arg );

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ? AND arg = ?",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}

sub revoke_priv_all {
    my ($u, $priv) = @_;
    my $dbh = LJ::get_db_writer();

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ?",
             undef, $u->id, $privid);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}


1;
