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

package LJ::Tags;
use strict;

use LJ::Global::Constants;
use LJ::Lang;

# <LJFUNC>
# name: LJ::Tags::get_usertagsmulti
# class: tags
# des: Gets a bunch of tags for the specified list of users.
# args: opts?, uobj*
# des-opts: Optional hashref with options. Keys can be 'no_gearman' to skip gearman
#           task dispatching.
# des-uobj: One or more user ids or objects to load the tags for.
# returns: Hashref; { userid => *tagref*, userid => *tagref*, ... } where *tagref* is the
#          return value of LJ::Tags::get_usertags -- undef on failure
# </LJFUNC>
sub get_usertagsmulti {
    return {} unless LJ::is_enabled('tags');

    # options if provided
    my $opts = {};
    $opts = shift if ref $_[0] eq 'HASH';

    # get input users
    my @uobjs = grep { defined } map { LJ::want_user($_) } @_;
    return {} unless @uobjs;

    # now setup variables we'll need
    my @memkeys;  # memcache keys to fetch
    my $res = {}; # { jid => { tagid => {}, ... }, ... }; results return hashref
    my %need;     # ( jid => 0/1 ); whether we need tags for this user

    # prepopulate our structures
    foreach my $u (@uobjs) {
        # don't load if we've previously gotten this one
        if (my $cached = $LJ::REQ_CACHE_USERTAGS{$u->{userid}}) {
            $res->{$u->{userid}} = $cached;
            next;
        }

        # setup that we need this one
        $need{$u->{userid}} = $u;
        push @memkeys, [ $u->{userid}, "tags:$u->{userid}" ];
    }
    return $res unless @memkeys;

    # gather data from memcache if available
    my $memc = LJ::MemCache::get_multi(@memkeys) || {};
    foreach my $key (keys %$memc) {
        if ($key =~ /^tags:(\d+)$/) {
            my $jid = $1;

            # set this up in our return hash and mark unneeded
            $LJ::REQ_CACHE_USERTAGS{$jid} = $memc->{$key};
            $res->{$jid} = $memc->{$key};
            delete $need{$jid};
        }
    }
    return $res unless %need;

    # if we're not using gearman, or we're not in web context (implies that we're
    # in gearman context?) then we need to use the loader to get the data
    my $gc = LJ::gearman_client();
    return LJ::Tags::_get_usertagsmulti($res, values %need)
        unless LJ::conf_test($LJ::LOADTAGS_USING_GEARMAN, values %need) && $gc && ! $opts->{no_gearman};

    # spawn gearman jobs to get each of the users
    my $ts = $gc->new_task_set();
    foreach my $u (values %need) {
        $ts->add_task(Gearman::Task->new("load_usertags", \"$u->{userid}",
            {
                uniq => '-',
                on_complete => sub {
                    my $resp = shift;
                    my $tags = Storable::thaw($$resp);
                    return unless $tags;

                    $LJ::REQ_CACHE_USERTAGS{$u->{userid}} = $tags;
                    $res->{$u->{userid}} = $tags;
                    delete $need{$u->{userid}};
                },
            }));
    }

    # now wait for gearman to finish, then we're done
    $ts->wait(timeout => 15);
    return $res;
}

# internal sub used by get_usertagsmulti
sub _get_usertagsmulti {
    my ($res, @uobjs) = @_;
    return $res unless @uobjs;

    # now setup variables we'll need
    my @memkeys;  # memcache keys to fetch
    my %jid2cid;  # ( jid => cid ); cross reference journals to clusters
    my %need;     # ( cid => { jid => 0/1 } ); whether we need tags for this user
    my %need_kws; # ( cid => { jid => 0/1 } ); whether we need keywords for this user
    my %kws;      # ( jid => { kwid => keyword, ... } ); keywords for a user
    my %dbcrs;    # ( cid => dbcr ); stores database handles

    # prepopulate our structures
    foreach my $u (@uobjs) {
        # we will have to load these
        $jid2cid{$u->{userid}} = $u->{clusterid};
        $need{$u->{clusterid}}->{$u->{userid}} = 1;
        $need_kws{$u->{clusterid}}->{$u->{userid}} = 1;
        push @memkeys, [ $u->{userid}, "kws:$u->{userid}" ];
    }

    # gather data from memcache if available
    my $memc = LJ::MemCache::get_multi(@memkeys) || {};
    foreach my $key (keys %$memc) {
        if ($key =~ /^kws:(\d+)$/) {
            my $jid = $1;
            my $cid = $jid2cid{$jid};

            # save for later and mark unneeded
            $kws{$jid} = $memc->{$key};
            delete $need_kws{$cid}->{$jid};
            delete $need_kws{$cid} unless %{$need_kws{$cid}};
        }
    }

    # get keywords first
    foreach my $cid (keys %need_kws) {
        next unless %{$need_kws{$cid}};

        # get db for this cluster
        my $dbcr = ($dbcrs{$cid} ||= LJ::get_cluster_def_reader($cid))
            or next;

        # get the keywords from the database
        my $in = join(',', map { $_ + 0 } keys %{$need_kws{$cid}});
        my $kwrows = $dbcr->selectall_arrayref("SELECT userid, kwid, keyword FROM userkeywords WHERE userid IN ($in)");
        next if $dbcr->err || ! $kwrows;

        # break down into data structures
        my %keywords; # ( jid => { kwid => keyword } )
        $keywords{$_->[0]}->{$_->[1]} = $_->[2]
            foreach @$kwrows;
        next unless %keywords;

        # save and store to memcache
        foreach my $jid (keys %keywords) {
            $kws{$jid} = $keywords{$jid};
            LJ::MemCache::add([ $jid, "kws:$jid" ], $keywords{$jid});
        }
    }

    # now, what we need per cluster...
    foreach my $cid (keys %need) {
        next unless %{$need{$cid}};

        # get db for this cluster
        my $dbcr = ($dbcrs{$cid} ||= LJ::get_cluster_def_reader($cid))
            or next;

        my @all_jids = map { $_ + 0 } keys %{$need{$cid}};

        # get the tags from the database
        my $in = join(',', @all_jids);
        my $tagrows = $dbcr->selectall_arrayref("SELECT journalid, kwid, parentkwid, display FROM usertags WHERE journalid IN ($in)");
        next if $dbcr->err;

        # break down into data structures
        my %tags; # ( jid => { kwid => display } )
        $tags{$_->[0]}->{$_->[1]} = $_->[3]
            foreach @$tagrows;

        # now turn this into a tentative results hash: { userid => { tagid => { name => tagname, ... }, ... } }
        # this is done by combining the information we got from the tags lookup along with
        # the stuff from the keyword lookup.  we need the relevant rows from both sources
        # before they appear in this hash.
        foreach my $jid (keys %tags) {
            next unless $kws{$jid};
            foreach my $kwid (keys %{$tags{$jid}}) {
                $res->{$jid}->{$kwid} =
                    {
                        name => $kws{$jid}->{$kwid},
                        security => {
                            public => 0,
                            groups => {},
                            private => 0,
                            protected => 0
                        },
                        uses => 0,
                        display => $tags{$jid}->{$kwid},
                    };
            }
        }

        # get security counts
        my @resjids = keys %$res;
        my $ids = join(',', map { $_+0 } @resjids);

        my $counts = [];

        # populate security counts
        if ( @resjids ) {
            $counts = $dbcr->selectall_arrayref("SELECT journalid, kwid, security, entryct FROM logkwsum WHERE journalid IN ($ids)");
            next if $dbcr->err;
        }

        # setup some helper values
        my $public_mask = 1 << 63;
        my $trust_mask = 1 << 0;

        # melt this information down into the hashref
        foreach my $row (@$counts) {
            my ($jid, $kwid, $sec, $ct) = @$row;

            # make sure this journal and keyword are present in the results already
            # so we don't auto-vivify something with security that has no keyword with it
            next unless $res->{$jid} && $res->{$jid}->{$kwid};

            # add these to the total uses
            $res->{$jid}->{$kwid}->{uses} += $ct;

            if ($sec & $public_mask) {
                $res->{$jid}->{$kwid}->{security}->{public} += $ct;
                $res->{$jid}->{$kwid}->{security_level} = 'public';
            } elsif ($sec & $trust_mask) {
                $res->{$jid}->{$kwid}->{security}->{protected} += $ct;
                $res->{$jid}->{$kwid}->{security_level} = 'protected'
                    unless $res->{$jid}->{$kwid}->{security_level} &&
                           $res->{$jid}->{$kwid}->{security_level} eq 'public';
            } elsif ($sec) {
                # if $sec is true (>0), and not trust/public, then it's a group(s).  but it's
                # still in the form of a number, and we want to know which group(s) it is.  so
                # we must convert the mask back to a bit number with LJ::bit_breakdown.
                foreach my $grpid ( LJ::bit_breakdown($sec) ) {
                    $res->{$jid}->{$kwid}->{security}->{groups}->{$grpid} += $ct;
                }
                $res->{$jid}->{$kwid}->{security_level} ||= 'group';
            } else {
                # $sec must be 0
                $res->{$jid}->{$kwid}->{security}->{private} += $ct;
            }
        }

        # default securities to private and store to memcache
        foreach my $jid (@all_jids) {
            $res->{$jid} ||= {};
            $res->{$jid}->{$_}->{security_level} ||= 'private'
                foreach keys %{$res->{$jid}};

            $LJ::REQ_CACHE_USERTAGS{$jid} = $res->{$jid};
            LJ::MemCache::add([ $jid, "tags:$jid" ], $res->{$jid});
        }
    }

    return $res;
}

# <LJFUNC>
# name: LJ::Tags::get_usertags
# class: tags
# des: Returns the tags that a user has defined for their account.
# args: uobj, opts?
# des-uobj: User object to get tags for.
# des-opts: Optional hashref; key can be 'remote' to filter tags to only ones that remote can see
# returns: Hashref; key being tag id, value being a large hashref (FIXME: document)
# </LJFUNC>
sub get_usertags {
    return {} unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift)
        or return undef;
    my $opts = shift() || {};

    # get tags for this user
    my $tags = LJ::Tags::get_usertagsmulti($u);
    return undef unless $tags;

    # get the tags for this user
    my $res = $tags->{$u->{userid}} || {};
    return {} unless %$res;

    # now if they provided a remote, remove the ones they don't want to see; note that
    # remote may be undef so we have to check exists
    if ( exists $opts->{remote} ) {
        # never going to cull anything if you control it, so just return
        return $res if LJ::isu( $opts->{remote} ) && $opts->{remote}->can_manage( $u );

        # setup helper variables from u to remote
        my ($trusted, $grpmask) = (0, 0);
        if ($opts->{remote}) {
            $trusted = $u->trusts_or_has_member( $opts->{remote} );
            $grpmask = $u->trustmask( $opts->{remote} );
        }

        # figure out what we need to purge
        my @purge;
TAG:    foreach my $tagid (keys %$res) {
            my $sec = $res->{$tagid}->{security_level};
            next TAG if $sec eq 'public';
            next TAG if $trusted && $sec eq 'protected';
            if ($grpmask && $sec eq 'group') {
                foreach my $grpid (keys %{$res->{$tagid}->{security}->{groups}}) {
                    next TAG if $grpmask & (1 << $grpid);
                }
            }
            push @purge, $tagid;
        }
        delete $res->{$_} foreach @purge;
    }

    return $res;
}

# <LJFUNC>
# name: LJ::Tags::get_entry_tags
# class: tags
# des: Gets tags that have been used on an entry.
# args: uuserid, jitemid
# des-uuserid: User id or object of account with entry
# des-jitemid: Journal itemid of entry; may also be arrayref of jitemids in journal.
# returns: Hashref; { jitemid => { tagid => tagname, tagid => tagname, ... }, ... }
# </LJFUNC>
sub get_logtags {
    return {} unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    return undef unless $u;

    # handle magic jitemid parameter
    my $jitemid = shift;
    unless (ref $jitemid eq 'ARRAY') {
        $jitemid = [ $jitemid+0 ];
        return undef unless $jitemid->[0];
    }
    return undef unless @$jitemid;

    # transform to a call to get_logtagsmulti
    my $ret = LJ::Tags::get_logtagsmulti({ $u->{clusterid} => [ map { [ $u->{userid}, $_ ] } @$jitemid ] });
    return undef unless $ret && ref $ret eq 'HASH';

    # now construct result hashref
    return { map { $_ => $ret->{"$u->{userid} $_"} } @$jitemid };
}

# <LJFUNC>
# name: LJ::Tags::get_logtagsmulti
# class: tags
# des: Load tags on a given set of entries
# args: idsbycluster
# des-idsbycluster: { clusterid => [ [ jid, jitemid ], [ jid, jitemid ], ... ] }
# returns: hashref with "jid jitemid" keys, value of each being a hashref of
#          { tagid => tagname, ... }
# </LJFUNC>
sub get_logtagsmulti {
    return {} unless LJ::is_enabled('tags');

    # get parameter (only one!)
    my $idsbycluster = shift;
    return undef unless $idsbycluster && ref $idsbycluster eq 'HASH';

    # the mass of variables to make this mess work!
    my @jids;     # journalids we've seen
    my @memkeys;  # memcache keys to load
    my %ret;      # ( jid => { jitemid => [ tagid, tagid, ... ], ... } ); storage for data pre-final conversion
    my %set;      # ( jid => ( jitemid => [ tagid, tagid, ... ] ) ); for setting in memcache
    my $res = {}; # { "jid jitemid" => { tagid => kw, tagid => kw, ... } }; final results hashref for return
    my %need;     # ( cid => { jid => { jitemid => 1, jitemid => 1 } } ); what still needs loading
    my %jid2cid;  # ( jid => cid ); map of journal id to clusterid

    # construct memcache keys for loading below
    foreach my $cid (keys %$idsbycluster) {
        foreach my $row (@{$idsbycluster->{$cid} || []}) {
            $need{$cid}->{$row->[0]}->{$row->[1]} = 1;
            $jid2cid{$row->[0]} = $cid;
            $set{$row->[0]}->{$row->[1]} = []; # empty initially
            push @memkeys, [ $row->[0], "logtag:$row->[0]:$row->[1]" ];
        }
    }

    # now hit up memcache to try to find what we can
    my $memc = LJ::MemCache::get_multi(@memkeys) || {};
    foreach my $key (keys %$memc) {
        if ($key =~ /^logtag:(\d+):(\d+)$/) {
            my ($jid, $jitemid) = ($1, $2);
            my $cid = $jid2cid{$jid};

            # save memcache output hashref to out %ret var
            $ret{$jid}->{$jitemid} = $memc->{$key};

            # remove the need to prevent loading from the database and storage to memcache
            delete $need{$cid}->{$jid}->{$jitemid};
            delete $need{$cid}->{$jid} unless %{$need{$cid}->{$jid}};
            delete $need{$cid} unless %{$need{$cid}};
        }
    }

    # iterate over clusters and construct SQL to get the data...
    foreach my $cid (keys %need) {
        my $dbcm = LJ::get_cluster_master($cid)
            or return undef;

        # list of (jid, jitemid) pairs that we get from %need
        my @where;
        foreach my $jid (keys %{$need{$cid} || {}}) {
            my @jitemids = keys %{$need{$cid}->{$jid} || {}};
            next unless @jitemids;

            push @where, "(journalid = $jid AND jitemid IN (" . join(",", @jitemids) . "))";
        }

        # prepare the query to run
        my $where = join(' OR ', @where);
        my $rows = $dbcm->selectall_arrayref("SELECT journalid, jitemid, kwid FROM logtags WHERE $where");
        return undef if $dbcm->err || ! $rows;

        # get data into %set so we add it to memcache later
        push @{$set{$_->[0]}->{$_->[1]} ||= []}, $_->[2] foreach @$rows;
    }

    # now add the things to memcache that we loaded from the clusters and also
    # transport them into the $ret hashref or returning to the user
    foreach my $jid (keys %set) {
        foreach my $jitemid (keys %{$set{$jid}}) {
            next unless $need{$jid2cid{$jid}}->{$jid}->{$jitemid};
            LJ::MemCache::add([ $jid, "logtag:$jid:$jitemid" ], $set{$jid}->{$jitemid});
            $ret{$jid}->{$jitemid} = $set{$jid}->{$jitemid};
        }
    }

    # quickly load all tags for the users we've found
    @jids = keys %ret;
    my $utags = LJ::Tags::get_usertagsmulti(@jids);
    return undef unless $utags;

    # last step: convert keywordids to keywords
    foreach my $jid (@jids) {
        my $tags = $utags->{$jid};
        next unless $tags;

        # transpose data from %ret into $res hashref which has (kwid => keyword) pairs
        foreach my $jitemid (keys %{$ret{$jid}}) {
            $res->{"$jid $jitemid"}->{$_} = $tags->{$_}->{name}
                foreach @{$ret{$jid}->{$jitemid} || []};
        }
    }

    # finally return the result hashref
    return $res;
}

# <LJFUNC>
# name: LJ::Tags::can_add_tags
# class: tags
# des: Determines if one account is allowed to add tags to another's entry.
# args: u, remote
# des-u: User id or object of account tags are being added to
# des-remote: User id or object of account performing the action
# returns: 1 if allowed, 0 if not, undef on error
# </LJFUNC>
sub can_add_tags {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my $remote = LJ::want_user(shift);
    return undef unless $u && $remote;

    # we don't allow identity users to add tags, even when tag permissions would otherwise allow any user on the site
    # exception are communities that explicitly allow identity users to post in them
    # FIXME: perhaps we should restrict on all users, but allow for more restrictive settings such as members?
    return undef unless $remote->is_individual;
    return undef if $u->has_banned( $remote );

    # get permission hashref and check it; note that we fall back to the control
    # permission, which will allow people to add even if they can't add by default
    my $perms = LJ::Tags::get_permission_levels($u);
    return LJ::Tags::_remote_satisfies_permission($u, $remote, $perms->{add}) ||
           LJ::Tags::_remote_satisfies_permission($u, $remote, $perms->{control});
}


sub can_add_entry_tags {
    return undef unless LJ::is_enabled( "tags" );

    my ( $remote, $entry ) = @_;
    $remote = LJ::want_user( $remote );

    return undef unless $remote && $entry;

    my $journal = $entry->journal;
    return undef unless $remote->is_individual;
    return undef if $journal->has_banned( $remote );

    my $perms = LJ::Tags::get_permission_levels( $journal );

    # specific case: are we the author of this entry, or otherwise an admin of the journal?
    if ( $perms->{add} eq 'author_admin' ) {
        # is author
        return 1 if $remote->equals( $entry->poster );

        # is journal administrator
        return $remote->can_manage( $journal );
    }

    # general case, see if the remote can add tags to the journal, in general
    return 1 if $remote->can_add_tags_to( $journal );

    # not allowed
    return undef;
}

# <LJFUNC>
# name: LJ::Tags::can_control_tags
# class: tags
# des: Determines if one account is allowed to control (add, edit, delete) the tags of another.
# args: u, remote
# des-u: User id or object of account tags are being edited on.
# des-remote: User id or object of account performing the action.
# returns: 1 if allowed, 0 if not, undef on error
# </LJFUNC>
sub can_control_tags {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my $remote = LJ::want_user(shift);
    return undef unless $u && $remote;
    return undef unless $remote->is_individual;
    return undef if $u->has_banned( $remote );

    # get permission hashref and check it
    my $perms = LJ::Tags::get_permission_levels($u);
    return LJ::Tags::_remote_satisfies_permission($u, $remote, $perms->{control});
}

# helper sub internal used by can_*_tags functions
sub _remote_satisfies_permission {
    my ($u, $remote, $perm) = @_;
    return undef unless $u && $remote && $perm;

    # allow if they can manage it (own, or 'A' edge)
    return 1 if $remote->can_manage( $u );

    # permission checks
    if ($perm eq 'public') {
        return 1;
    } elsif ($perm eq 'none') {
        return 0;
    } elsif ( $perm eq 'protected' || $perm eq 'friends' ) { # 'friends' for backwards compatibility
        return $u->trusts_or_has_member( $remote );
    } elsif ($perm eq 'private') {
        return 0;  # $remote->can_manage( $u ) already returned 1 above
    } elsif ( $perm eq 'author_admin' ) {
        # this tests whether the remote can add tags for this journal in general
        # when we don't have an entry object available to us (e.g., posting)
        # Existing entries, checking per-entry author permissions, should use
        # LJ::Tag::can_add_entry_tags
        return $remote->can_manage( $u ) || $remote->member_of( $u );
    } elsif ($perm =~ /^group:(\d+)$/) {
        my $grpid = $1+0;
        return undef unless $grpid >= 1 && $grpid <= 60;

        my $mask = $u->trustmask( $remote );
        return ($mask & (1 << $grpid)) ? 1 : 0;
    } else {
        # else, problem!
        return undef;
    }
}

# <LJFUNC>
# name: LJ::Tags::get_permission_levels
# class: tags
# des: Gets the permission levels on an account.
# args: uobj
# des-uobj: User id or object of account to get permissions for.
# returns: Hashref; keys one of 'add', 'control'; values being 'private' (only the account
#          in question), 'protected' (all trusted), 'public' (everybody), 'group:N' (one
#          trust group with given id), or 'none' (nobody can).
# </LJFUNC>
sub get_permission_levels {
    return { add => 'none', control => 'none' }
        unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    return undef unless $u;

    # return defaults for accounts
    unless ( $u->prop( 'opt_tagpermissions' ) ) {
        if ( $u->is_community ) {
            # communities are members (trusted) add, private (maintainers) control
            return { add => 'protected', control => 'private' };
        } elsif ( $u->is_person ) {
            # people let trusted add, self control
            return { add => 'private', control => 'private' };
        } else {
            # other account types can't add tags
            return { add => 'none', control => 'none' };
        }
    }

    # now split and return
    my ($add, $control) = split(/\s*,\s*/, $u->{opt_tagpermissions});
    return { add => $add, control => $control };
}

# <LJFUNC>
# name: LJ::Tags::is_valid_tagstring
# class: tags
# des: Determines if a string contains a valid list of tags.
# args: tagstring, listref?, opts?
# des-tagstring: Opaque tag string provided by the user.
# des-listref: If specified, return valid list of canonical tags in arrayref here.
# des-opts: currently only 'omit_underscore_check' is recognized
# returns: 1 if list is valid, 0 if not.
# </LJFUNC>
sub is_valid_tagstring {
    my ($tagstring, $listref, $opts) = @_;
    return 0 unless $tagstring;
    $listref ||= [];
    $opts    ||= {};

    # setup helper subs
    my $valid_tag = sub {
        my $tag = shift;

        # a tag that starts with an underscore is reserved for future use,
        # but we added this after some underscores already existed.
        # Allow underscore tags to be viewed/deleted, but not created/modified.
        return 0 if ! $opts->{'omit_underscore_check'} && $tag =~ /^_/;

        return 0 if $tag =~ /[\<\>\r\n\t]/;     # no HTML, newlines, tabs, etc
        return 0 unless $tag =~ /^(?:.+\s?)+$/; # one or more "words"
        return 1;
    };
    my $canonical_tag = sub {
        my $tag = shift;
        $tag =~ s/\s+/ /g; # condense multiple spaces to a single space
        $tag = LJ::text_trim($tag, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD);
        $tag = LJ::utf8_lc( $tag );
        return $tag;
    };

    # now iterate
    my @list = grep { length $_ }            # only keep things that are something
               map { LJ::trim($_) }          # remove leading/trailing spaces
               split(/\s*,\s*/, $tagstring); # split on comma with optional spaces
    return 0 unless @list;

    # now validate each one as we go
    foreach my $tag (@list) {
        # canonicalize and determine validity
        $tag = $canonical_tag->($tag);
        return 0 unless $valid_tag->($tag);

        # now push on our list
        push @$listref, $tag;
    }

    # well, it must have been okay if we got here
    return 1;
}

# <LJFUNC>
# name: LJ::Tags::get_security_level
# class: tags
# des: Returns the security level that applies to the given security information.
# args: security, allowmask
# des-security: 'private', 'public', or 'usemask'
# des-allowmask: a bitmask in standard allowmask form
# returns: Bitwise security level to use for [dbtable[logkwsum]] table.
# </LJFUNC>
sub get_security_level {
    my ($sec, $mask) = @_;

    return 0 if $sec eq 'private';
    return 1 << 63 if $sec eq 'public';
    return $mask;
}

# <LJFUNC>
# name: LJ::Tags::update_logtags
# class: tags
# des: Updates the tags on an entry.  Tags not in the list you provide are deleted.
# args: uobj, jitemid, tags, opts
# des-uobj: User id or object of account with entry
# des-jitemid: Journal itemid of entry to tag
# des-tags: List of tags you want applied to entry.
# des-opts: Hashref; keys being the action and values of the key being an arrayref of
#           tags to involve in the action.  Possible actions are 'add', 'set', and
#           'delete'.  With those, the value is a hashref of the tags (textual tags)
#           to add, set, or delete.  Other actions are 'add_ids', 'set_ids', and
#           'delete_ids'.  The value arrayref should then contain the tag ids to
#           act with.  Can also specify 'add_string', 'set_string', or 'delete_string'
#           as a comma separated list of user-supplied tags which are then canonicalized
#           and used.  'remote' is the remote user taking the actions (required).
#           'err_ref' is ref to scalar to return error messages in.  optional, and may
#           not be set by all error conditions.  'ignore_max' if specified will ignore
#           a user's max tags limit.
# returns: 1 on success, undef on error
# </LJFUNC>
sub update_logtags {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my $jitemid = shift() + 0;
    return undef unless $u && $jitemid;
    return undef unless $u->writer;

    # ensure we have an options hashref
    my $opts = shift;
    return undef unless $opts && ref $opts eq 'HASH';

    # setup error stuff
    my $err = sub {
        my $fake = "";
        my $err_ref = $opts->{err_ref} && ref $opts->{err_ref} eq 'SCALAR' ? $opts->{err_ref} : \$fake;
        $$err_ref = shift() || "Unspecified error";
        return undef;
    };

    # perform set logic?
    my $do_set = exists $opts->{set} || exists $opts->{set_ids} || exists $opts->{set_string};

    # now get extra options
    my $remote = LJ::want_user(delete $opts->{remote});
    return undef unless $remote || $opts->{force};

    # get trust levels
    my $entry = LJ::Entry->new( $u, jitemid => $jitemid );
    my $can_control = LJ::Tags::can_control_tags($u, $remote);
    my $can_add = $can_control || LJ::Tags::can_add_entry_tags( $remote, $entry );

    # bail out early if we can't do any actions
    return $err->( LJ::Lang::ml( 'taglib.error.access' ) )
        unless $can_add || $opts->{force};

    # load the user's tags
    my $utags = LJ::Tags::get_usertags($u);
    return undef unless $utags;

    my @unauthorized_add;

    # take arrayrefs of tag strings and stringify them for validation
    my @to_create;
    foreach my $verb (qw(add set delete)) {
        # if given tags, combine into a string
        if ($opts->{$verb}) {
            $opts->{"${verb}_string"} = join(', ', @{$opts->{$verb}});
            $opts->{$verb} = [];
        }

        # now validate the string, if we have one
        if ($opts->{"${verb}_string"}) {
            $opts->{$verb} = [];
            return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $opts->{"${verb}_string"} ) } ) )
                unless LJ::Tags::is_valid_tagstring($opts->{"${verb}_string"}, $opts->{$verb});
        }

        # and turn everything into ids
        $opts->{"${verb}_ids"} ||= [];
        foreach my $kw (@{$opts->{$verb} || []}) {
            my $kwid = $u->get_keyword_id( $kw, $can_control );

            # error if we should have been able to create a kwid and didn't
            return undef if $can_control && ! $kwid;

            # skip if the tag isn't used in the journal and either
            # (a) we can't add it or (b) we are using force:
            # we only use force if we are clearing all tags or importing, so
            # we will have already added all the canonical tags in the journal,
            # and any additional tags would be bogus
            unless ( $kwid && $utags->{$kwid} ) {
                if ( ! $can_control || $opts->{force} ) {
                    push @unauthorized_add, $kw;
                    next;
                } else {
                    # we need to create this tag later
                    push @to_create, $kw;
                }
            }

            # add the id to the list
            push @{$opts->{"${verb}_ids"}}, $kwid;
        }
    }

    # setup %add/%delete hashes, for easier duplicate removal
    my %add = ( map { $_ => 1 } @{$opts->{add_ids} || []} );
    my %delete = ( map { $_ => 1 } @{$opts->{delete_ids} || []} );

    # used to keep counts in sync
    my $tags = LJ::Tags::get_logtags($u, $jitemid);
    return undef unless $tags;

    # now get tags for this entry; which there might be none, so make it a hashref
    $tags = $tags->{$jitemid} || {};

    # set is broken down into add/delete as necessary
    if ($do_set || ($opts->{set_ids} && @{$opts->{set_ids}})) {
        # mark everything to delete, we'll fix it shortly
        $delete{$_} = 1 foreach keys %{$tags};

        # and now go through the set we want, things that are in the delete
        # pile are just nudge so we don't touch them, and everything else we
        # throw in the add pile
        foreach my $id (@{$opts->{set_ids}}) {
            $add{$id} = 1
                unless delete $delete{$id};
        }
    }

    # now don't readd things we already have
    delete $add{$_} foreach keys %{$tags};

    my @add_delete_errors;
    push @add_delete_errors, LJ::Lang::ml( "taglib.error.add", { tags => join( ", ", @unauthorized_add ) } )
        if @unauthorized_add && ! $opts->{force};
    push @add_delete_errors, LJ::Lang::ml( "taglib.error.delete2", { tags => join( ", ", map { $utags->{$_}->{name} } keys %{$tags} ) } )
        if %delete && ! $can_control && ! $opts->{force};
    return $err->( join "\n\n", @add_delete_errors ) if @add_delete_errors;

    # bail out if nothing needs to be done
    return 1 unless %add || %delete;

    # at this point we have enough information to determine if they're going to break their
    # max, so let's do that so we can bail early enough to prevent a rollback operation
    my $max = $opts->{ignore_max} ? 0 : $u->count_tags_max;
    if (@to_create && $max && $max > 0) {
        my $total = scalar(keys %$utags) + scalar(@to_create);
        if ( $total > $max ) {
            return $err->(LJ::Lang::ml('taglib.error.toomany3', { max => $max,
                                                                 excess => $total - $max }));
        }
    }

    # now we can create the new tags, since we know we're safe
    # We still need to propagate ignore_max, as create_usertag does some checks of it's own.
    LJ::Tags::create_usertag( $u, $_, { display => 1, ignore_max => $opts->{ignore_max} } ) foreach @to_create;

    # %add and %delete are accurate, but we need to track necessary
    # security updates; this is a hash of keyword ids and a modification
    # value (a delta; +/-N) to be applied to that row later
    my %security;

    # get the security of this post for use in %security; do this now so
    # we don't interrupt the transaction below
    my $l2row = LJ::get_log2_row($u, $jitemid);
    return undef unless $l2row;

    # calculate security masks
    my $sec = LJ::Tags::get_security_level($l2row->{security}, $l2row->{allowmask});

    # setup a rollback bail path so that we can undo everything we've done
    # if anything fails in the middle; and if the rollback fails, scream loudly
    # and burst into flames!
    my $rollback = sub {
        die $u->errstr unless $u->rollback;
        return undef;
    };

    # start the big transaction, for great justice!
    $u->begin_work;

    # process additions first
    my @bind;
    foreach my $kwid (keys %add) {
        $security{$kwid}++;
        push @bind, $u->{userid}, $jitemid, $kwid;
    }

    my $recentlimit = $LJ::RECENT_TAG_LIMIT || 500;

    # now add all to both tables; only do $recentlimit rows ($recentlimit * 3 bind vars) at a time
    while (my @list = splice(@bind, 0, 3 * $recentlimit)) {
        my $sql = join(',', map { "(?,?,?)" } 1..(scalar(@list)/3));

        $u->do("REPLACE INTO logtags (journalid, jitemid, kwid) VALUES $sql", undef, @list);
        return $rollback->() if $u->err;

        $u->do("REPLACE INTO logtagsrecent (journalid, jitemid, kwid) VALUES $sql", undef, @list);
        return $rollback->() if $u->err;
    }

    # now process deletions
    @bind = ();
    foreach my $kwid (keys %delete) {
        $security{$kwid}--;
        push @bind, $kwid;
    }

    # now run the SQL
    while (my @list = splice(@bind, 0, $recentlimit)) {
        my $sql = join(',', map { $_ + 0 } @list);

        $u->do("DELETE FROM logtags WHERE journalid = ? AND jitemid = ? AND kwid IN ($sql)",
               undef, $u->{userid}, $jitemid);
        return $rollback->() if $u->err;

        $u->do("DELETE FROM logtagsrecent WHERE journalid = ? AND kwid IN ($sql) AND jitemid = ?",
               undef, $u->{userid}, $jitemid);
        return $rollback->() if $u->err;
    }

    # now handle lazy cleaning of this table for these tag ids; note that the
    # %security hash contains all of the keywords we've operated on in total
    my @kwids = keys %security;
    my $sql = join(',', map { $_ + 0 } @kwids);
    my $sth = $u->prepare("SELECT kwid, COUNT(*) FROM logtagsrecent WHERE journalid = ? AND kwid IN ($sql) GROUP BY 1");
    return $rollback->() if $u->err || ! $sth;
    $sth->execute($u->{userid});
    return $rollback->() if $sth->err;

    # now iterate over counts and find ones that are too high
    my %delrecent; # kwid => [ jitemid, jitemid, ... ]
    while (my ($kwid, $ct) = $sth->fetchrow_array) {
        next unless $ct > $recentlimit + 20;

        # get the times of the entries, the user time (lastn view uses user time), sort it, and then
        # we can chop off jitemids that fall below the threshold -- but only in this keyword and only clean
        # up some number at a time (25 at most, starting at our threshold)
        my $sth2 = $u->prepare(qq{
                SELECT t.jitemid
                FROM logtagsrecent t, log2 l
                WHERE t.journalid = l.journalid
                  AND t.jitemid = l.jitemid
                  AND t.journalid = ?
                  AND t.kwid = ?
                ORDER BY l.eventtime DESC
                LIMIT $recentlimit,25
            });
        return $rollback->() if $u->err || ! $sth2;
        $sth2->execute($u->{userid}, $kwid);
        return $rollback->() if $sth2->err;

        # push these onto the hash for deleting below
        while (my $jit = $sth2->fetchrow_array) {
            push @{$delrecent{$kwid} ||= []}, $jit;
        }
    }

    # now delete any recents we need to into this format:
    #    (kwid = 3 AND jitemid IN (2, 3, 4)) OR (kwid = ...) OR ...
    # but only if we have some to delete
    if (%delrecent) {
        my $del = join(' OR ', map {
                                    "(kwid = " . ($_+0) . " AND jitemid IN (" . join(',', map { $_+0 } @{$delrecent{$_}}) . "))"
                               } keys %delrecent);
        $u->do("DELETE FROM logtagsrecent WHERE journalid = ? AND ($del)", undef, $u->{userid});
        return $rollback->() if $u->err;
    }

    # now we must get the current security values in order to come up with a proper update; note that
    # we select for update, which locks it so we have a consistent view of the rows
    $sth = $u->prepare("SELECT kwid, security, entryct FROM logkwsum WHERE journalid = ? AND kwid IN ($sql) FOR UPDATE");
    return $rollback->() if $u->err || ! $sth;
    $sth->execute($u->{userid});
    return $rollback->() if $sth->err;

    # now iterate and get the security counts
    my %counts;
    while (my ($kwid, $secu, $ct) = $sth->fetchrow_array) {
        $counts{$kwid}->{$secu} = $ct;
    }

    # now we want to update them, and delete any at 0
    my (@replace, @delete);
    foreach my $kwid (@kwids) {
        if (exists $counts{$kwid} && exists $counts{$kwid}->{$sec}) {
            # an old one exists
            my $new = $counts{$kwid}->{$sec} + $security{$kwid};
            if ($new > 0) {
                # update it
                push @replace, [ $kwid, $sec, $new ];
            } else {
                # delete this one
                push @delete, [ $kwid, $sec ];
            }
        } else {
            # add a new one
            push @replace, [ $kwid, $sec, $security{$kwid} ];
        }
    }

    # handle deletes in one move; well, 100 at a time
    while (my @list = splice(@delete, 0, 100)) {
        my $sql = join(' OR ', map { "(kwid = ? AND security = ?)" } 1..scalar(@list));
        $u->do("DELETE FROM logkwsum WHERE journalid = ? AND ($sql)",
               undef, $u->{userid}, map { @$_ } @list);
        return $rollback->() if $u->err;
    }

    # handle replaces and inserts
    while (my @list = splice(@replace, 0, 100)) {
        my $sql = join(',', map { "(?,?,?,?)" } 1..scalar(@list));
        $u->do("REPLACE INTO logkwsum (journalid, kwid, security, entryct) VALUES $sql",
               undef, map { $u->{userid}, @$_ } @list);
        return $rollback->() if $u->err;
    }

    # commit everything and smack caches and we're done!
    die $u->errstr unless $u->commit;
    LJ::Tags::reset_cache($u);
    LJ::Tags::reset_cache($u => $jitemid);
    return 1;

}

# <LJFUNC>
# name: LJ::Tags::delete_logtags
# class: tags
# des: Deletes all tags on an entry.
# args: uobj, jitemid
# des-uobj: User id or object of account with entry.
# des-jitemid: Journal itemid of entry to delete tags from.
# returns: undef on error; 1 on success
# </LJFUNC>
sub delete_logtags {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my $jitemid = shift() + 0;
    return undef unless $u && $jitemid;

    # maybe this is wrong, but it does all of the logic we would otherwise
    # have to duplicate here, so no sense in doing that.
    return LJ::Tags::update_logtags($u, $jitemid, { set_string => "", force => 1, });
}

# <LJFUNC>
# name: LJ::Tags::reset_cache
# class: tags
# des: Clears out all cached information for a user's tags.
# args: uobj, jitemid?
# des-uobj: User id or object of account to clear cache for
# des-jitemid: Either a single jitemid or an arrayref of jitemids to clear for the user.  If
#              not present, the user's tags cache is cleared.  If present, the cache for those
#              entries only are cleared.
# returns: undef on error; 1 on success
# </LJFUNC>
sub reset_cache {
    return undef unless LJ::is_enabled('tags');

    while (my ($u, $jitemid) = splice(@_, 0, 2)) {
        next unless
            $u = LJ::want_user($u);

        # standard user tags cleanup
        unless ($jitemid) {
            delete $LJ::REQ_CACHE_USERTAGS{$u->{userid}};
            LJ::MemCache::delete([ $u->{userid}, "tags:$u->{userid}" ]);
        }

        # now, cleanup entries if necessary
        if ($jitemid) {
            $jitemid = [ $jitemid ]
                unless ref $jitemid eq 'ARRAY';
            LJ::MemCache::delete([ $u->{userid}, "logtag:$u->{userid}:$_" ])
                foreach @$jitemid;
        }
    }
    return 1;
}

# <LJFUNC>
# name: LJ::Tags::create_usertag
# class: tags
# des: Creates tags for a user, returning the keyword ids allocated.
# args: uobj, kw, opts?
# des-uobj: User object to create tag on.
# des-kw: Tag string (comma separated list of tags) to create.
# des-opts: Optional; hashref, possible keys being 'display' and value being whether or
#           not this tag should be a display tag and 'parenttagid' being the tagid of a
#           parent tag for hierarchy.  'err_ref' optional key should be a ref to a scalar
#           where we will store text about errors.  'ignore_max' if set will ignore the
#           user's max tags limit when creating this tag.
# returns: undef on error, else a hashref of { keyword => tagid } for each keyword defined
# </LJFUNC>
sub create_usertag {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my $kw = shift;
    my $opts = shift || {};
    return undef unless $u && $kw;

    # setup error stuff
    my $err = sub {
        my $fake = "";
        my $err_ref = $opts->{err_ref} && ref $opts->{err_ref} eq 'SCALAR' ? $opts->{err_ref} : \$fake;
        $$err_ref = shift() || "Unspecified error";
        return undef;
    };

    my $tags = [];
    return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $kw ) } ) )
        unless LJ::Tags::is_valid_tagstring($kw, $tags);

    # check to ensure we don't exceed the max of tags
    my $max = $opts->{ignore_max} ? 0 : $u->count_tags_max;
    if ($max && $max > 0) {
        my $cur = scalar(keys %{ LJ::Tags::get_usertags($u) || {} });
        my $tagtotal = $cur + scalar(@$tags);
        if ($tagtotal > $max) {
            return $err->(LJ::Lang::ml('taglib.error.toomany3', { max => $max,
                                                                 excess => $tagtotal - $max }));
        }
    }

    my $display = $opts->{display} ? 1 : 0;
    my $parentkwid = $opts->{parenttagid} ? ($opts->{parenttagid}+0) : undef;

    my %res;
    foreach my $tag (@$tags) {
        my $kwid = $u->get_keyword_id( $tag );
        return undef unless $kwid;

        $res{$tag} = $kwid;
    }

    my $ct = scalar keys %res;
    my $bind = join(',', map { "(?,?,?,?)" } 1..$ct);
    $u->do("INSERT IGNORE INTO usertags (journalid, kwid, parentkwid, display) VALUES $bind",
           undef, map { $u->{userid}, $_, $parentkwid, $display } values %res);
    return undef if $u->err;

    LJ::Tags::reset_cache($u);
    return \%res;
}

# <LJFUNC>
# name: LJ::Tags::validate_tag
# class: tags
# des: Check the validity of a single tag.
# args: tag
# des-tag: The tag to check.
# returns: If valid, the canonicalized tag, else, undef.
# </LJFUNC>
sub validate_tag {
    my $tag = shift;
    return undef unless $tag;

    my $list = [];
    return undef unless
        LJ::Tags::is_valid_tagstring($tag, $list);
    return undef if scalar(@$list) > 1;

    return $list->[0];
}

# <LJFUNC>
# name: LJ::Tags::delete_usertag
# class: tags
# des: Deletes a tag for a user, and all mappings.
# args: uobj, type, tag
# des-uobj: User object to delete tag on.
# des-type: Either 'id' or 'name', indicating the type of the third parameter.
# des-tag: If type is 'id', this is the tag id (kwid).  If type is 'name', this is the name of the
#          tag that we want to delete from the user.
# returns: undef on error, 1 for success, 0 for tag not found
# </LJFUNC>
sub delete_usertag {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    return undef unless $u;

    my ($type, $val) = @_;

    my $kwid;
    if ($type eq 'name') {
        my $tag = LJ::Tags::validate_tag($val);
        return undef unless $tag;

        $kwid = $u->get_keyword_id( $tag, 0 );
    } elsif ($type eq 'id') {
        $kwid = $val + 0;
    }
    return undef unless $kwid;

    # escape sub
    my $rollback = sub {
        die $u->errstr unless $u->rollback;
        return undef;
    };

    # start the big transaction
    $u->begin_work;

    # get items this keyword is on
    my $sth = $u->prepare('SELECT jitemid FROM logtags WHERE journalid = ? AND kwid = ? FOR UPDATE');
    return $rollback->() if $u->err || ! $sth;

    # now get the items
    $sth->execute($u->{userid}, $kwid);
    return $rollback->() if $sth->err;

    # now get list of jitemids for later cache clearing
    my @jitemids;
    push @jitemids, $_
        while $_ = $sth->fetchrow_array;

    # delete this tag's information from the relevant tables
    foreach my $table (qw(usertags logtags logtagsrecent logkwsum)) {
        # no error checking, we're just deleting data that's already semi-unlinked due
        # to us already updating the userprop above
        $u->do("DELETE FROM $table WHERE journalid = ? AND kwid = ?",
               undef, $u->{userid}, $kwid);
    }

    # all done with our updates
    die $u->errstr unless $u->commit;

    # reset caches, have to do both of these, one for the usertags one for logtags
    LJ::Tags::reset_cache($u);
    LJ::Tags::reset_cache($u => \@jitemids);
    return 1;
}

# <LJFUNC>
# name: LJ::Tags::rename_usertag
# class: tags
# des: Renames a tag for a user
# args: uobj, type, tag, newname, error_ref (optional)
# des-uobj: User object to delete tag on.
# des-type: Either 'id' or 'name', indicating the type of the third parameter.
# des-tag: If type is 'id', this is the tag id (kwid).  If type is 'name', this is the name of the
#          tag that we want to rename for the user.
# des-newname: The new name of this tag.
# des-error_ref: (optional) ref to scalar to return error messages in.
# returns: undef on error, 1 for success, 0 for tag not found
# </LJFUNC>
sub rename_usertag {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    return undef unless $u;

    my ($type, $oldkw, $newkw, $ref) = @_;
    return undef unless $type && $oldkw && $newkw;

    # setup error stuff
    my $err = sub {
        my $fake = "";
        my $err_ref = $ref && ref $ref eq 'SCALAR' ? $ref : \$fake;
        $$err_ref = shift() || "Unspecified error";
        return undef;
    };

    # validate new tag
    my $newname = LJ::Tags::validate_tag($newkw);
    return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $newkw ) } ) )
        unless $newname;
    return $err->( LJ::Lang::ml( 'taglib.error.notcanonical',
                                 { beforetag => LJ::ehtml( $newkw ),
                                   aftertag => LJ::ehtml( $newname ) } ) )
        unless $newkw eq $newname; # Far from ideal UX-wise.

    # get a list of keyword ids to operate on
    my $kwid;
    if ($type eq 'name') {
        my $val = LJ::Tags::validate_tag($oldkw);
        return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $oldkw ) } ) )
            unless $val;
        $kwid = $u->get_keyword_id( $val, 0 );
    } elsif ($type eq 'id') {
        $kwid = $oldkw + 0;
    }
    return $err->() unless $kwid;

    # see if this is already a keyword
    my $newkwid = $u->get_keyword_id( $newname );
    return undef unless $newkwid;

    # see if the tag we're renaming TO already exists as a keyword,
    # if so, error and suggest merging the tags
    # FIXME: ask user to merge and then merge
    my $tags = LJ::Tags::get_usertags( $u );
    return $err->( LJ::Lang::ml( 'taglib.error.exists', { tagname => LJ::ehtml( $newname ) } ) )
        if $tags->{$newkwid};

    # escape sub
    my $rollback = sub {
        die $u->errstr unless $u->rollback;
        return undef;
    };

    # start the big transaction
    $u->begin_work;

    # get items this keyword is on
    my $sth = $u->prepare('SELECT jitemid FROM logtags WHERE journalid = ? AND kwid = ? FOR UPDATE');
    return $rollback->() if $u->err || ! $sth;

    # now get the items
    $sth->execute($u->{userid}, $kwid);
    return $rollback->() if $sth->err;

    # now get list of jitemids for later cache clearing
    my @jitemids;
    push @jitemids, $_
        while $_ = $sth->fetchrow_array;

    # do database update to migrate from old to new
    foreach my $table (qw(usertags logtags logtagsrecent logkwsum)) {
        $u->do("UPDATE $table SET kwid = ? WHERE journalid = ? AND kwid = ?",
               undef, $newkwid, $u->{userid}, $kwid);
        return $rollback->() if $u->err;
    }

    # all done with our updates
    die $u->errstr unless $u->commit;

    # reset caches, have to do both of these, one for the usertags one for logtags
    LJ::Tags::reset_cache($u);
    LJ::Tags::reset_cache($u => \@jitemids);
    return 1;
}

# <LJFUNC>
# name: LJ::Tags::merge_usertags
# class: tags
# des: Merges usertags
# args: uobj, newname, error_ref, oldnames
# des-uobj: User object to merge tag on.
# des-newname: new name for these tags, might be one that already exists
# des-error_ref: ref to scalar to return error messages in.
# des-oldnames: array of tags that need to be merged
# returns: undef on error, 1 for success
# </LJFUNC>
sub merge_usertags {
    return undef unless LJ::is_enabled( 'tags' );

    my $u = LJ::want_user( shift );
    return undef unless $u;
    my ( $merge_to, $ref, @merge_from ) = @_;
    my $userid = $u->userid;
    return undef unless $userid;

    # error output
    my $err = sub {
        my $err_ref = $ref && ref $ref eq 'SCALAR' ? $ref : \"";
        $$err_ref = shift() || "Unspecified error";
        return undef;
    };

    # check whether we have a new name
    return $err->( LJ::Lang::ml( 'taglib.error.mergenoname') )
        unless $merge_to;

    # check whether new tag is valid
    my $newname = LJ::Tags::validate_tag( $merge_to );
    return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $merge_to ) } ) )
        unless $newname;

    # check whether tag to merge to already exists
    # if it exists, but isn't selected for merging, throw error as this could be a mistake
    my $tags = LJ::Tags::get_usertags( $u );
    my $exists = $tags->{$u->get_keyword_id( $newname )} ? 1 : 0;
    my %merge_from = map { $_ => 1 } @merge_from;
    return $err->( LJ::Lang::ml( 'taglib.error.mergetoexisting', { tagname => LJ::ehtml( $merge_to ) } ) )
        if $exists && ! $merge_from{lc( $merge_to )};

    # if necessary, create new tag id
    my $merge_to_id;
    if ( $exists ) {
        $merge_to_id = $u->get_keyword_id( $newname );
    } else {
        my $merge_to_ids = LJ::Tags::create_usertag( $u, $newname, { display => 1 } );
        $merge_to_id = $merge_to_ids->{$newname};
    }

    # get keyword ids of tags to merge - take out the existing one if there is one
    my @merge_from_ids;
    foreach my $tagname ( @merge_from ) {
        my $val = LJ::Tags::validate_tag( $tagname );
        return $err->( LJ::Lang::ml( 'taglib.error.invalid', { tagname => LJ::ehtml( $tagname ) } ) )
            unless $val;
        my $kwid = $u->get_keyword_id( $val, 0 );
        push @merge_from_ids, $kwid unless $kwid eq $merge_to_id;
    }

    # rollback if we encounter any errors in the upcoming database transactions
    my $rollback = sub {
        die $u->errstr unless $u->rollback;
        return undef;
    };

    # begin transaction
    $u->begin_work;

    # get the entry ids of entries the tag is already on if it exists
    my @merge_to_jitemids;
    if ( $exists ) {
        my $sth = $u->prepare( 'SELECT jitemid FROM logtags WHERE journalid= ? AND kwid= ?' );
        return $rollback->() if $u->err || ! $sth;
        $sth->execute( $userid, $merge_to_id );
        return $rollback->() if $sth->err;

        push @merge_to_jitemids, $_
            while $_ = $sth->fetchrow_array;
    }

    # getting the entry ids the tag might need to be added to (might because if we are merging to an existing tag,
    # we need to take out the entries that already have both a tag we are merging from and the tag we are merging to)
    my $sth = $u->prepare( "SELECT DISTINCT jitemid FROM logtags WHERE journalid= ? AND kwid IN (" . join( ", ", ( "?" ) x @merge_from_ids ) . ")" );
    return $rollback->() if $u->err || ! $sth;
    $sth->execute( $userid, @merge_from_ids );
    return $rollback->() if $sth->err;

    # jitemids of all entries the tag needs to be added to, taking out the ones it is already on
    my @jitemids;
    if ( $exists ) {
        my %merge_to_jitemids = map { $_ => 1 } @merge_to_jitemids;
        while ( my $jitemid = $sth->fetchrow_array ) {
            push @jitemids, $jitemid unless $merge_to_jitemids{$jitemid};
        }
    } else {
        push @jitemids, $_
            while $_ = $sth->fetchrow_array;
    }

    # now we do the actual database updates to logtags, logtagsrecent, usertags, and logkwsum:

    # add the tag to all entries we need to change, in both logtags and logtagsrecent
    if ( @jitemids ) {
        foreach my $jitemid ( @jitemids ) {
            $sth = $u->prepare( "INSERT INTO logtags (journalid, jitemid, kwid) VALUES ( ?, ?, ? )");
            return $rollback->() if $u->err || ! $sth;
            $sth->execute( $userid, $jitemid, $merge_to_id );
            return $rollback->() if $sth->err;

            $sth = $u->prepare( "INSERT INTO logtagsrecent (journalid, jitemid, kwid) VALUES ( ?, ?, ? )");
            return $rollback->() if $u->err || ! $sth;
            $sth->execute( $userid, $jitemid, $merge_to_id );
            return $rollback->() if $sth->err;
        }
    }

    # if the tag already existed before, it already has entries in logkwsum, which we delete now
    if ( $exists ) {
        $u->do("DELETE FROM logkwsum WHERE journalid = ? AND kwid = ? " , undef, $userid, $merge_to_id );
        return $rollback->() if $u->err;
    }

    # while we previously only needed the jitemids of the entries we needed to add the tag to, we now need all the ones it is a tag on after the transaction
    # including the one it was already on before the merge
    $sth = $u->prepare( "SELECT jitemid FROM logtags WHERE journalid= ? AND kwid= ?" );
    return $rollback->() if $u->err || ! $sth;
    $sth->execute( $userid, $merge_to_id );
    return $rollback->() if $sth->err;

    # we need all jitemids in an array for later cache clearing
    @jitemids = ();
    while ( my $itemid = $sth->fetchrow_array ) {
        push @jitemids, $itemid;
    }

    # get security of entries this new tag is now on, so we can accurately update logkwsum
    # this can only get executed if the tags we are merging are actually in use on entries
    # since we don't need logkwsum entries for tags that exist and are not used on entries, we can just skip this for them
    if ( @jitemids ) {
        $sth = $u->prepare( "SELECT security, allowmask FROM log2 WHERE journalid=? AND jitemid IN (" . join( ", ", ( "?" ) x @jitemids ) . ")" );
        return $rollback->() if $u->err || ! $sth;

        $sth->execute( $userid, @jitemids );
        return $rollback->() if $sth->err;

        # updating security counts: create hash for storing security values and initialize with zeros
        my $public_mask = 1 << 63;
        my %securities = (
            $public_mask => 0,
            0 => 0,
            1 => 0,
            2 => 0,
        );

        # count securities; if the security isn't public or private and the allowmask isn't 1, the entry is set to trusted
        while ( my ( $security, $allowmask ) = $sth->fetchrow_array ) {
            if ( $security eq 'public' ) {
                $securities{$public_mask}++;
            } elsif ( $security eq 'private' ) {
                $securities{0}++;
            } elsif ( $allowmask == 1 ) {
                $securities{1}++;
            } else {
                $securities{2}++;
            }
        }

        # write to logkwsum
        while ( my ( $sec, $value ) = each %securities ) {
            unless ( $value == 0 ) {
                $u->do( "INSERT INTO logkwsum (journalid, kwid, security, entryct) VALUES (?, ?, ?, ?)",
                    undef, $userid, $merge_to_id, $sec, $value );
                return $rollback->() if $u->err;
            }
        }
    }

    # delete other tags from database and entries
    foreach my $table ( qw( usertags logtags logtagsrecent logkwsum ) ) {
        $sth = $u->prepare( "DELETE FROM $table WHERE journalid = ? AND kwid IN (" . join( ", ", ( "?" ) x @merge_from_ids ) . ")" );
        return $rollback->() if $u->err || ! $sth;

        $sth->execute( $userid, @merge_from_ids );
        return $rollback->() if $sth->err;
    }

    # done with the updates, commit
    die $u->errstr unless $u->commit;

    # reset cache on all changed entries
    LJ::Tags::reset_cache( $u );
    LJ::Tags::reset_cache( $u => \@jitemids );

    return 1;
}

# <LJFUNC>
# name: LJ::Tags::set_usertag_display
# class: tags
# des: Set the display bool for a tag.
# args: uobj, vartype, var, val
# des-uobj: User id or object of account to edit tag on
# des-vartype: Either 'id' or 'name'; indicating what the next parameter is
# des-var: If vartype is 'id', this is the tag (keyword) id; else, it's the tag/keyword itself
# des-val: 1/0; whether to turn the display flag on or off
# returns: 1 on success, undef on error
# </LJFUNC>
sub set_usertag_display {
    return undef unless LJ::is_enabled('tags');

    my $u = LJ::want_user(shift);
    my ($type, $var, $val) = @_;
    return undef unless $u;

    my $kwid;
    if ($type eq 'id') {
        $kwid = $var + 0;
    } elsif ($type eq 'name') {
        $var = LJ::Tags::validate_tag($var);
        return undef unless $var;

        # do not auto-vivify but get the keyword id
        $kwid = $u->get_keyword_id( $var, 0 );
    }
    return undef unless $kwid;

    $u->do("UPDATE usertags SET display = ? WHERE journalid = ? AND kwid = ?",
           undef, $val ? 1 : 0, $u->{userid}, $kwid);
    return undef if $u->err;

    return 1;
}

# <LJFUNC>
# name: LJ::Tags::deleted_trust_group
# class: tags
# des: Called from LJ::Protocol when a trust group is deleted.
# args: uobj, bit
# des-uobj: User id or object of account deleting the group.
# des-bit: The id (1..60) of the trust group being deleted.
# returns: 1 of success undef on failure.
# </LJFUNC>
sub deleted_trust_group {
    my $u = LJ::want_user(shift);
    my $bit = shift() + 0;
    return undef unless $u && $bit >= 1 && $bit <= 60;

    my $bval = 1 << $bit;
    my %masks;
    $masks{$bval} = 1;  # don't need alterations for rows that only include the deleted group

    my $rollback = sub {
        die $u->errstr unless $u->rollback;
        return undef;
    };

    # get data for all other security masks that include this group
    my $sth = $u->prepare("SELECT security, kwid, entryct FROM logkwsum WHERE journalid = ?" .
                          " AND security & ? AND security != ?");
    return undef if $u->err || ! $sth;
    $sth->execute($u->{userid}, $bval, $bval);
    return undef if $sth->err;
    $u->begin_work;  # rollback begins here

    while (my ($sec, $kwid, $ct) = $sth->fetchrow_array) {
        # remove the group from mask and update logkwsum
        my $newsec = $sec ^ $bval;  # XOR
        unless ( $u->do("UPDATE logkwsum SET entryct = entryct + ? WHERE journalid = ? AND security = ?  AND kwid = ?",
                        undef, $ct, $u->{userid}, $newsec, $kwid) ) {
            # no row to update, have to insert
            $u->do("INSERT INTO logkwsum (journalid, security, kwid, entryct) VALUES (?,?,?,?)",
                   undef, $u->{userid}, $newsec, $kwid, $ct);
        }
        return $rollback->() if $u->err;
        $masks{$sec} = 1;
    }
    # delete from logkwsum and then nuke the user's tags
    $u->do("DELETE FROM logkwsum WHERE journalid = ? AND security IN (?)",
           undef, $u->{userid}, join(', ', keys %masks));
    return $rollback->() if $u->err;

    die $u->errstr unless $u->commit;
    LJ::Tags::reset_cache($u);
    return 1;
}

sub tag_url {
# LJ::Tags::tag_url
# Arguments: $u = user object; $tagname = scalar with name of tag
# Returns: Scalar containing the URL for the "posts with this tag" page.
#   The form that is used varies according to whether the tag name contains
#   difficult characters.
    my ( $u, $tagname ) = @_;
    return undef unless $u && $tagname;

    my $escapedname = LJ::eurl( $tagname );
    # Does it have a slash or plus sign in it?
    my $url = ( $escapedname =~ m![\\\/]|\%2B! )
        ? $u->journal_base . '?tag=' . $escapedname
        : $u->journal_base . '/tag/' . $escapedname;

    return $url;
}

1;
