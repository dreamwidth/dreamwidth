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

package LJ;
use strict;
use Carp qw/ croak /;

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpics at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids.
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
# </LJFUNC>
sub load_userpics {
    my ($upics, $idlist) = @_;

    return undef unless ref $idlist eq 'ARRAY' && $idlist->[0];

    # $idlist needs to be an arrayref of arrayrefs,
    # HOWEVER, there's a special case where it can be
    # an arrayref of 2 items:  $u (which is really an arrayref)
    # as well due to 'fields' and picid which is an integer.
    #
    # [$u, $picid] needs to map to [[$u, $picid]] while allowing
    # [[$u1, $picid1], [$u2, $picid2], [etc...]] to work.
    if (scalar @$idlist == 2 && ! ref $idlist->[1]) {
        $idlist = [ $idlist ];
    }

    my @load_list;
    foreach my $row (@{$idlist})
    {
        my ($u, $id) = @$row;
        next unless ref $u;

        if ($LJ::CACHE_USERPIC{$id}) {
            $upics->{$id} = $LJ::CACHE_USERPIC{$id};
        } elsif ($id+0) {
            push @load_list, [$u, $id+0];
        }
    }
    return unless @load_list;

    if (@LJ::MEMCACHE_SERVERS) {
        my @mem_keys = map { [$_->[1],"userpic.$_->[1]"] } @load_list;
        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
        while (my ($k, $v) = each %$mem) {
            next unless $v && $k =~ /(\d+)/;
            my $id = $1;
            $upics->{$id} = LJ::MemCache::array_to_hash("userpic", $v);
        }
        @load_list = grep { ! $upics->{$_->[1]} } @load_list;
        return unless @load_list;
    }

    my %db_load;
    foreach my $row (@load_list) {
        # ignore users on clusterid 0
        next unless $row->[0]->{clusterid};

        push @{$db_load{$row->[0]->{clusterid}}}, $row;
    }

    foreach my $cid (keys %db_load) {
        my $dbcr = LJ::get_cluster_def_reader($cid);
        unless ($dbcr) {
            print STDERR "Error: LJ::load_userpics unable to get handle; cid = $cid\n";
            next;
        }

        my (@bindings, @data);
        foreach my $row (@{$db_load{$cid}}) {
            push @bindings, "(userid=? AND picid=?)";
            push @data, ($row->[0]->{userid}, $row->[1]);
        }
        next unless @data && @bindings;

        my $sth = $dbcr->prepare("SELECT userid, picid, width, height, fmt, state, ".
                                 "       UNIX_TIMESTAMP(picdate) AS 'picdate', location, flags ".
                                 "FROM userpic2 WHERE " . join(' OR ', @bindings));
        $sth->execute(@data);

        while (my $ur = $sth->fetchrow_hashref) {
            my $id = delete $ur->{'picid'};
            $upics->{$id} = $ur;

            # force into numeric context so they'll be smaller in memcache:
            foreach my $k (qw(userid width height flags picdate)) {
                $ur->{$k} += 0;
            }
            $ur->{location} = uc(substr($ur->{location}, 0, 1));

            $LJ::CACHE_USERPIC{$id} = $ur;
            LJ::MemCache::set([$id,"userpic.$id"], LJ::MemCache::hash_to_array("userpic", $ur));
        }
    }
}

1;

