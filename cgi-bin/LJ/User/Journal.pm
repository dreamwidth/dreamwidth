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
use Storable;
use LJ::Global::Constants;
use LJ::Keywords;

########################################################################
### 13. Community-Related Functions and Authas

=head2 Community-Related Functions and Authas
=cut

sub can_manage {
    # true if the first user is an admin for the target user.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    # is same user?
    return 1 if $u->equals( $target );

    # people/syn/rename accounts can only be managed by the one account
    return 0 if $target->journaltype =~ /^[PYR]$/;

    # check for admin access
    return 1 if LJ::check_rel( $target, $u, 'A' );

    # failed checks, return false
    return 0;
}


sub can_manage_other {
    # true if the first user is an admin for the target user,
    # UNLESS the two users are the same.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    return 0 if $u->equals( $target );
    return $u->can_manage( $target );
}


sub can_moderate {
    # true if the first user can moderate the target user.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    return 1 if $u->can_manage_other( $target );
    return LJ::check_rel( $target, $u, 'M' );
}


# can $u post to $targetu?
sub can_post_to {
    my ( $u, $targetu ) = @_;
    croak "Invalid users passed to LJ::User->can_post_to."
        unless LJ::isu( $u ) && LJ::isu( $targetu );

    # if it's you, and you're a person, you can post to it
    return 1 if $u->is_person && $u->equals( $targetu );

    # else, you have to be an individual and the target has to be a comm
    return 0 unless $u->is_individual && $targetu->is_community;

    # check if user has access explicit posting access
    return 1 if LJ::check_rel( $targetu, $u, 'P' );

    # let's check if this community is allowing post access to non-members
    if ( $targetu->has_open_posting ) {
        my ( $ml, $pl ) = $targetu->get_comm_settings;
        return 1 if $pl eq 'members';
    }

    # is the poster an admin for this community?  admins can always post
    return 1 if $u->can_manage( $targetu );

    return 0;
}

# list of communities that $u manages
sub communities_managed_list {
    my ( $u ) = @_;

    croak "Invalid users passed to LJ::User->communities_managed_list"
        unless LJ::isu( $u );

    my $cids = LJ::load_rel_target( $u, 'A' );
    return undef unless $cids;

    my %users = %{ LJ::load_userids( @$cids ) };

    return  map { $_ }
                grep { $_ && ( $_->is_visible || $_->is_readonly ) }
            values %users;
}

# list of communities that $u moderates
sub communities_moderated_list {
    my ( $u ) = @_;

    croak "Invalid users passed to LJ::User->communities_moderated_list"
        unless LJ::isu( $u );

    my $cids = LJ::load_rel_target( $u, 'M' );
    return undef unless $cids;

    my %users = %{ LJ::load_userids( @$cids ) };

    return  map { $_ }
                grep { $_ && ( $_->is_visible || $_->is_readonly ) }
            values %users;
}

# Get an array of usernames a given user can authenticate as.
# Valid keys for opts hashref:
#     - type: filter by given journaltype (P or C)
#     - cap:  filter by users who have given cap
#     - showall: override hiding of non-visible/non-read-only journals
sub get_authas_list {
    my ( $u, $opts ) = @_;

    # Two valid types, Personal or Community
    $opts->{type} = undef unless $opts->{type} =~ m/^[PC]$/;

    my $ids = LJ::load_rel_target( $u, 'A' );
    return undef unless $ids;
    my %users = %{ LJ::load_userids( @$ids ) };

    return map { $_->user }
           grep { ! $opts->{cap}  || $_->get_cap( $opts->{cap} ) }
           grep { ! $opts->{type} || $opts->{type} eq $_->journaltype }

           # unless overridden, hide non-visible/non-read-only journals.
           # always display the user's acct
           grep { $opts->{showall} || $_->is_visible || $_->is_readonly || $_->equals( $u ) }

           # can't work as an expunged account
           grep { ! $_->is_expunged && $_->clusterid > 0 }

           # put $u at the top of the list, then sort the rest
           ( $u,  sort { $a->user cmp $b->user } values %users );
}


# What journals can this user post to?
sub posting_access_list {
    my $u = shift;

    my @res;

    my $ids = LJ::load_rel_target($u, 'P');
    my $us = LJ::load_userids(@$ids);
    foreach (values %$us) {
        next unless $_->is_visible;
        push @res, $_;
    }

    return sort { $a->{user} cmp $b->{user} } @res;
}

# gets the relevant communities that the user is a member of
# used to suggest communities to a person who know the user
sub relevant_communities {
    my $u = shift;

    my %comms;
    my @ids = $u->member_of_userids;
    my $memberships = LJ::load_userids( @ids );

    # get all communities that $u is a member of that aren't closed membership
    # and that wish to be included in the community promo
    foreach my $membershipid ( keys %$memberships ) {
        my $membershipu = $memberships->{$membershipid};

        next unless $membershipu->is_community;
        next if $membershipu->optout_community_promo;
        next unless $membershipu->is_visible;
        next if $membershipu->is_closed_membership;

        $comms{$membershipid}->{u} = $membershipu;
        $comms{$membershipid}->{istatus} = 'normal';
    }

    # get usage information about comms
    if ( scalar keys %comms ) {
        my $comms_times = LJ::get_times_multi( keys %comms );
        foreach my $commid ( keys %comms ) {
            if ( $comms_times->{created} && defined $comms_times->{created}->{$commid} ) {
                $comms{$commid}->{created} = $comms_times->{created}->{$commid};
            }
            if ( $comms_times->{updated} && defined $comms_times->{updated}->{$commid} ) {
                $comms{$commid}->{updated} = $comms_times->{updated}->{$commid};
            }
        }
    }

    # prune the list of communities
    #
    # keep a community in the list if:
    # * it was created in the past 10 days OR
    # * $u is a maint or mod of it OR
    # * it was updated in the past 30 days
    my $over30 = 0;
    my $now = time();

    COMMUNITY:
        foreach my $commid ( sort { $comms{$b}->{updated} <=> $comms{$a}->{updated} } keys %comms ) {
            my $commu = $comms{$commid}->{u};

            if ( $now - $comms{$commid}->{created} <= 60*60*24*10 ) { # 10 days
                $comms{$commid}->{istatus} = 'new';
                next COMMUNITY;
            }

            my @maintainers = $commu->maintainer_userids;
            my @moderators  = $commu->moderator_userids;
            foreach my $mid ( @maintainers, @moderators ) {
                if ( $mid == $u->id ) {
                    $comms{$commid}->{istatus} = 'mm';
                    next COMMUNITY;
                }
            }

            if ( $over30 ) {
                delete $comms{$commid};
                next COMMUNITY;
            } else {
                if ( $now - $comms{$commid}->{updated} > 60*60*24*30 ) { # 30 days
                    delete $comms{$commid};

                    # since we're going through the communities in timeupdate order,
                    # we know every community in %comms after this one was updated
                    # more than 30 days ago
                    $over30 = 1;
                }
            }
        }

    # if we still have more than 20 comms, delete any with fewer than five members
    # as long as it's not new and $u isn't a maint/mod
    if ( scalar keys %comms > 20 ) {
        foreach my $commid ( keys %comms ) {
            my $commu = $comms{$commid}->{u};

            next unless $comms{$commid}->{istatus} eq 'normal';

            my @ids = $commu->member_userids;
            if ( scalar @ids < 5 ) {
                delete $comms{$commid};
            }
        }
    }

    return %comms;
}


sub trusts_or_has_member {
    my ( $u, $target_u ) = @_;
    $target_u = LJ::want_user( $target_u ) or return 0;

    return $target_u->member_of( $u ) ? 1 : 0
        if $u->is_community;

    return $u->trusts( $target_u ) ? 1 : 0;
}

########################################################################
### 14. Comment-Related Functions

=head2 Comment-Related Functions
=cut

# true if u1 restricts commenting to trusted and u2 is not trusted
sub does_not_allow_comments_from {
    my ( $u1, $u2 ) = @_;
    return unless LJ::isu( $u1 ) && LJ::isu( $u2 );
    return $u1->prop('opt_whocanreply') eq 'friends'
        && ! $u1->trusts_or_has_member( $u2 );
}


# true if u1 restricts comments to registered users and u2 is a
# non-circled OpenID with an unconfirmed email
# FIXME: fold into does_not_allow_comments_from without disabling
# QuickReply in that situation due to S2.pm:3677
sub does_not_allow_comments_from_unconfirmed_openid {
    my ( $u1, $u2 ) = @_;
    return unless LJ::isu( $u1 ) && LJ::isu( $u2 );
    return $u1->{'opt_whocanreply'} eq 'reg'
        && $u2->is_identity
        && ! ( $u2->is_validated || $u1->trusts( $u2 ));
}


# get recent talkitems posted to this user
# args: maximum number of comments to retrieve
# returns: array of hashrefs with jtalkid, nodetype, nodeid, parenttalkid, posterid, state
sub get_recent_talkitems {
    my ($u, $maxshow, %opts) = @_;

    $maxshow ||= 15;
    my $max_fetch = int($LJ::TOOLS_RECENT_COMMENTS_MAX*1.5) || 150;
    # We fetch more items because some may be screened
    # or from suspended users, and we weed those out later

    my $remote   = $opts{remote} || LJ::get_remote();
    return undef unless LJ::isu($u);

    ## $raw_talkitems - contains DB rows that are not filtered
    ## to match remote user's permissions to see
    my $raw_talkitems;
    my $memkey = [$u->userid, 'rcntalk:' . $u->userid ];
    $raw_talkitems = LJ::MemCache::get($memkey);
    if (!$raw_talkitems) {
        my $sth = $u->prepare(
            "SELECT jtalkid, nodetype, nodeid, parenttalkid, ".
            "       posterid, UNIX_TIMESTAMP(datepost) as 'datepostunix', state ".
            "FROM talk2 ".
            "WHERE journalid=? AND state <> 'D' " .
            "ORDER BY jtalkid DESC ".
            "LIMIT $max_fetch"
        );
        $sth->execute( $u->userid );
        $raw_talkitems = $sth->fetchall_arrayref({});
        LJ::MemCache::set($memkey, $raw_talkitems, 60*5);
    }

    ## Check remote's permission to see the comment, and create singletons
    my @recv;
    foreach my $r (@$raw_talkitems) {
        last if @recv >= $maxshow;

        # construct an LJ::Comment singleton
        my $comment = LJ::Comment->new($u, jtalkid => $r->{jtalkid});
        $comment->absorb_row(%$r);
        next unless $comment->visible_to($remote);
        push @recv, $r;
    }

    # need to put the comments in order, with "oldest first"
    # they are fetched from DB in "recent first" order
    return reverse @recv;
}


# return the number of comments a user has posted
sub num_comments_posted {
    my $u = shift;
    my %opts = @_;

    my $dbcr = $opts{dbh} || LJ::get_cluster_reader($u);
    my $userid = $u->id;

    my $memkey = [$userid, "talkleftct:$userid"];
    my $count = LJ::MemCache::get($memkey);
    unless ($count) {
        my $expire = time() + 3600*24*2; # 2 days;
        $count = $dbcr->selectrow_array("SELECT COUNT(*) FROM talkleft " .
                                        "WHERE userid=?", undef, $userid);
        LJ::MemCache::set($memkey, $count, $expire) if defined $count;
    }

    return $count;
}


# return the number of comments a user has received
sub num_comments_received {
    my $u = shift;
    my %opts = @_;

    my $dbcr = $opts{dbh} || LJ::get_cluster_reader($u);
    my $userid = $u->id;

    my $memkey = [$userid, "talk2ct:$userid"];
    my $count = LJ::MemCache::get($memkey);
    unless ($count) {
        my $expire = time() + 3600*24*2; # 2 days;
        $count = $dbcr->selectrow_array("SELECT COUNT(*) FROM talk2 ".
                                        "WHERE journalid=?", undef, $userid);
        LJ::MemCache::set($memkey, $count, $expire) if defined $count;
    }

    return $count;
}


########################################################################
###  15. Entry-Related Functions

=head2 Entry-Related Functions
=cut

# front-end to recent_entries, which forces the remote user to be
# the owner, so we get everything.
sub all_recent_entries {
    my ( $u, %opts ) = @_;
    $opts{filtered_for} = $u;
    return $u->recent_entries(%opts);
}


sub draft_text {
    my ($u) = @_;
    return $u->prop('entry_draft');
}

sub entryform_width {
    my ( $u ) = @_;

    if ( $u->raw_prop( 'entryform_width' ) =~ /^(F|P)$/ ) {
        return $u->raw_prop( 'entryform_width' )
    } else {
        return 'F';
    }
}

# getter/setter
sub default_entryform_panels {
    my ( %opts ) = @_;
    my $anonymous = $opts{anonymous} ? 1 : 0;
    my $force_show = $anonymous;

    return {
        order => $anonymous ?
                [   [ "tags", "displaydate", "slug" ],
                    [ "currents" ],
                    [ "comments", "age_restriction" ],
                ] :
                [   [ "tags", "displaydate", "slug" ],

                    # FIXME: should be [ "status" ... ] %]
                    [ "currents", "comments", "age_restriction" ],

                    # FIXME: should be [ ... "scheduled" ]
                    [ "icons", "crosspost", "sticky" ],
                ],
        show => {
            "tags"          => 1,
            "currents"      => 1,
            "slug"          => 1,
            "displaydate"   => $force_show,
            "comments"      => $force_show,
            "age_restriction" => $force_show,
            "icons"         => 1,

            "crosspost"     => $force_show,
            #"scheduled"     => $force_show,

            "sticky"        => 1,

            #"status"        => 1,
        },
        collapsed => {
        }
    };
}
sub entryform_panels {
    my ( $u, $val ) = @_;

    if ( defined $val ) {
        $u->set_prop( entryform_panels => Storable::nfreeze( $val ) );
        return $val;
    }

    my $prop = $u->prop( "entryform_panels" );
    my $default = LJ::User::default_entryform_panels();
    my %obsolete = (
        access => 1,
        journal => 1,
        flags => 1,
    );

    my %need_panels = map { $_ => 1 } keys %{$default->{show}};

    my $ret;
    $ret = Storable::thaw( $prop ) if $prop;

    if ( $ret ) {
        # remove any obsolete panels from "show" and "collapse"
        foreach my $panel ( keys %obsolete ) {
            delete $ret->{show}->{$panel};
            delete $ret->{collapsed}->{$panel};
        }

        foreach my $column ( @{$ret->{order}} ) {
            # remove any obsolete panels from "order"
            my @col = @{$column};
            my @del_indexes = grep { $obsolete{$col[$_]} } 0..$#col;
            if ( @del_indexes ) {
                foreach my $del ( reverse @del_indexes ) {
                    splice @col, $del, 1;
                }
            }
            $column = \@col;

            # fill in any modules that somehow are not in this list
            foreach my $panel ( @{$column} ) {
                delete $need_panels{$panel};
            }
        }

        my @col = @{$ret->{order}->[2]};
        foreach ( keys %need_panels ) {
            # add back into last column, but respect user's option to show/not-show
            push @col, $_;
            $ret->{show}->{$_} = 0 unless defined $ret->{show}->{$_};
        }
        $ret->{order}->[2] = \@col;
    } else {
        $ret = $default;
    }

    return $ret;
}

sub entryform_panels_order {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;

    if ( defined $val ) {
        $panels->{order} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{order};
}

sub entryform_panels_visibility {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;
    if ( defined $val ) {
        $panels->{show} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{show};
}

sub entryform_panels_collapsed {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;
    if ( defined $val ) {
        $panels->{collapsed} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{collapsed};
}



# <LJFUNC>
# name: LJ::get_post_ids
# des: Given a user object and some options, return the number of posts or the
#      posts'' IDs (jitemids) that match.
# returns: number of matching posts, <strong>or</strong> IDs of
#          matching posts (default).
# args: u, opts
# des-opts: 'security' - [public|private|usemask]
#           'allowmask' - integer for friends-only or custom groups
#           'start_date' - UTC date after which to look for match
#           'end_date' - UTC date before which to look for match
#           'return' - if 'count' just return the count
#           FIXME: Add caching?
# </LJFUNC>
sub get_post_ids {
    my ($u, %opts) = @_;

    my $query = 'SELECT';
    my @vals; # parameters to query

    if ($opts{'start_date'} || $opts{'end_date'}) {
        croak "start or end date not defined"
            if (!$opts{'start_date'} || !$opts{'end_date'});

        if (!($opts{'start_date'} >= 0) || !($opts{'end_date'} >= 0) ||
            !($opts{'start_date'} <= $LJ::EndOfTime) ||
            !($opts{'end_date'} <= $LJ::EndOfTime) ) {
            return undef;
        }
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        $query .= " COUNT(*)";
    } else {
        $query .= " jitemid";
    }

    # from the journal entries table for this user
    $query .= " FROM log2 WHERE journalid=?";
    push( @vals, $u->userid );

    # filter by security
    if ($opts{'security'}) {
        $query .= " AND security=?";
        push(@vals, $opts{'security'});
        # If friends-only or custom
        if ($opts{'security'} eq 'usemask' && $opts{'allowmask'}) {
            $query .= " AND allowmask=?";
            push(@vals, $opts{'allowmask'});
        }
    }

    # filter by date, use revttime as it is indexed
    if ($opts{'start_date'} && $opts{'end_date'}) {
        # revttime is reverse event time
        my $s_date = $LJ::EndOfTime - $opts{'start_date'};
        my $e_date = $LJ::EndOfTime - $opts{'end_date'};
        $query .= " AND revttime<?";
        push(@vals, $s_date);
        $query .= " AND revttime>?";
        push(@vals, $e_date);
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        return $u->selectrow_array($query, undef, @vals);
    } else {
        my $jitemids = $u->selectcol_arrayref($query, undef, @vals) || [];
        die $u->errstr if $u->err;
        return @$jitemids;
    }
}


# Returns 'rich' or 'plain' depending on user's
# setting of which editor they would like to use
# and what they last used
sub new_entry_editor {
    my $u = shift;

    my $editor = $u->prop('entry_editor');
    return 'plain' if $editor eq 'always_plain'; # They said they always want plain
    return 'rich' if $editor eq 'always_rich'; # They said they always want rich
    return $editor if $editor =~ /(rich|plain)/; # What did they last use?
    return $LJ::DEFAULT_EDITOR; # Use config default
}

# What security level to use for new posts. This magic flag is used to give
# user's the ability to specify that "if I try to post public, don't let me".
# To override this, you have to go back and edit your post.
sub newpost_minsecurity {
    return $_[0]->prop( 'newpost_minsecurity' ) || 'public';
}

# This loads the user's specified post-by-email security. If they haven't
# set that up, then we fall back to the standard new post minimum security.
sub emailpost_security {
    return $_[0]->prop( 'emailpost_security' ) ||
        $_[0]->newpost_minsecurity;
}


*get_post_count = \&number_of_posts;
sub number_of_posts {
    my ($u, %opts) = @_;

    # to count only a subset of all posts
    if (%opts) {
        $opts{return} = 'count';
        return $u->get_post_ids(%opts);
    }

    my $userid = $u->userid;
    my $memkey = [$userid, "log2ct:$userid"];
    my $expire = time() + 3600*24*2; # 2 days
    return LJ::MemCache::get_or_set($memkey, sub {
        return $u->selectrow_array( "SELECT COUNT(*) FROM log2 WHERE journalid=?",
                                    undef, $userid );
    }, $expire);
}


# returns array of LJ::Entry objects, ignoring security
sub recent_entries {
    my ($u, %opts) = @_;
    my $remote = delete $opts{'filtered_for'} || LJ::get_remote();
    my $count  = delete $opts{'count'}        || 50;
    my $order  = delete $opts{'order'}        || "";
    die "unknown options" if %opts;

    my $err;
    my @recent = $u->recent_items(
        itemshow  => $count,
        err       => \$err,
        clusterid => $u->clusterid,
        remote    => $remote,
        order     => $order,
    );
    die "Error loading recent items: $err" if $err;

    my @objs;
    foreach my $ri (@recent) {
        my $entry = LJ::Entry->new($u, jitemid => $ri->{itemid});
        push @objs, $entry;
        # FIXME: populate the $entry with security/posterid/alldatepart/ownerid/rlogtime
    }
    return @objs;
}


sub security_group_display {
    my ( $u, $allowmask ) = @_;
    return '' unless LJ::isu( $u );
    return '' unless defined $allowmask;

    my $remote = LJ::get_remote() or return '';
    my $use_urls = $remote->get_cap( "security_filter" ) || $u->get_cap( "security_filter" );

    # see which group ids are in the security mask
    my %group_ids = ( map { $_ => 1 } grep { $allowmask & ( 1 << $_ ) } 1..60 );
    return '' unless scalar( keys %group_ids ) > 0;

    my @ret;

    my @groups = $u->trust_groups;
    foreach my $group ( @groups ) {
        next unless $group_ids{$group->{groupnum}};  # not in mask

        my $name = LJ::ehtml( $group->{groupname} );
        if ( $use_urls ) {
            my $url = LJ::eurl( $u->journal_base . "/security/group:$name" );
            push @ret, "<a href='$url'>$name</a>";
        } else {
            push @ret, $name;
        }
    }

    return join( ', ', @ret );
}



sub set_draft_text {
    my ($u, $draft) = @_;
    my $old = $u->draft_text;

    $LJ::_T_DRAFT_RACE->() if $LJ::_T_DRAFT_RACE;

    # try to find a shortcut that makes the SQL shorter
    my @methods;  # list of [ $subref, $cost ]

    # one method is just setting it all at once.  which incurs about
    # 75 bytes of SQL overhead on top of the length of the draft,
    # not counting the escaping
    push @methods, [ "set", sub { $u->set_prop('entry_draft', $draft); 1 },
                     75 + length $draft ];

    # stupid case, setting the same thing:
    push @methods, [ "noop", sub { 1 }, 0 ] if $draft eq $old;

    # simple case: appending
    if (length $old && $draft =~ /^\Q$old\E(.+)/s) {
        my $new = $1;
        my $appending = sub {
            my $prop = LJ::get_prop("user", "entry_draft") or die; # FIXME: use exceptions
            my $rv = $u->do("UPDATE userpropblob SET value = CONCAT(value, ?) WHERE userid=? AND upropid=? AND LENGTH(value)=?",
                            undef, $new, $u->userid, $prop->{id}, length $old);
            return 0 unless $rv > 0;
            $u->uncache_prop("entry_draft");
            return 1;
        };
        push @methods, [ "append", $appending, 40 + length $new ];
    }

    # FIXME: prepending/middle insertion (the former being just the latter), as
    # well as appending, wihch we could then get rid of

    # try the methods in increasing order
    foreach my $m (sort { $a->[2] <=> $b->[2] } @methods) {
        my $func = $m->[1];
        if ($func->()) {
            $LJ::_T_METHOD_USED->($m->[0]) if $LJ::_T_METHOD_USED; # for testing
            return 1;
        }
    }
    return 0;
}

sub third_party_notify_list {
    my $u = shift;

    my $val = $u->prop('third_party_notify_list');
    my @services = split(',', $val);

    return @services;
}


# Add a service to a user's notify list
sub third_party_notify_list_add {
    my ( $u, $svc ) = @_;
    return 0 unless $svc;

    # Is it already there?
    return 1 if $u->third_party_notify_list_contains($svc);

    # Create the new list of services
    my @cur_services = $u->third_party_notify_list;
    push @cur_services, $svc;
    my $svc_list = join(',', @cur_services);

    # Trim a service from the list if it is too long
    if (length $svc_list > 255) {
        shift @cur_services;
        $svc_list = join(',', @cur_services)
    }

    # Set it
    $u->set_prop('third_party_notify_list', $svc_list);
    return 1;
}


# Check if the user's notify list contains a particular service
sub third_party_notify_list_contains {
    my ( $u, $val ) = @_;

    return 1 if grep { $_ eq $val } $u->third_party_notify_list;

    return 0;
}


# Remove a service to a user's notify list
sub third_party_notify_list_remove {
    my ( $u, $svc ) = @_;
    return 0 unless $svc;

    # Is it even there?
    return 1 unless $u->third_party_notify_list_contains($svc);

    # Remove it!
    $u->set_prop('third_party_notify_list',
                 join(',',
                      grep { $_ ne $svc } $u->third_party_notify_list
                      )
                 );
    return 1;
}


########################################################################
###  27. Tag-Related Functions

=head2 Tag-Related Functions
=cut

# can $u add existing tags to $targetu's entries?
sub can_add_tags_to {
    my ($u, $targetu) = @_;

    return LJ::Tags::can_add_tags($targetu, $u);
}

# can $u control (add, delete, edit) the tags of $targetu?
sub can_control_tags {
   my ($u, $targetu) = @_;

   return LJ::Tags::can_control_tags($targetu, $u);
}

# <LJFUNC>
# name: LJ::User::get_keyword_id
# class:
# des: Get the id for a keyword.
# args: uuid, keyword, autovivify?
# des-uuid: User object or userid to use.
# des-keyword: A string keyword to get the id of.
# returns: Returns a kwid into [dbtable[userkeywords]].
#          If the keyword doesn't exist, it is automatically created for you.
# des-autovivify: If present and 1, automatically create keyword.
#                 If present and 0, do not automatically create the keyword.
#                 If not present, default behavior is the old
#                 style -- yes, do automatically create the keyword.
# </LJFUNC>
sub get_keyword_id {
    my ( $u, $kw, $autovivify ) = @_;
    $u = LJ::want_user( $u );
    return undef unless $u;
    $autovivify = 1 unless defined $autovivify;

    # setup the keyword for use
    return 0 unless $kw =~ /\S/;
    $kw = LJ::text_trim( $kw, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD );

    # get the keyword and insert it if necessary
    my $kwid = $u->selectrow_array( 'SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                    undef, $u->userid, $kw ) + 0;
    if ( $autovivify && ! $kwid ) {
        # create a new keyword
        $kwid = LJ::alloc_user_counter( $u, 'K' );
        return undef unless $kwid;

        # attempt to insert the keyword
        my $rv = $u->do( "INSERT IGNORE INTO userkeywords (userid, kwid, keyword) VALUES (?, ?, ?)",
                         undef, $u->userid, $kwid, $kw ) + 0;
        return undef if $u->err;

        # at this point, if $rv is 0, the keyword is already there so try again
        unless ( $rv ) {
            $kwid = $u->selectrow_array( 'SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                         undef, $u->userid, $kw ) + 0;
        }

        # nuke cache
        $u->memc_delete( 'kws' );
    }
    return $kwid;
}


sub tags {
    my $u = shift;

    return LJ::Tags::get_usertags($u);
}


1;
