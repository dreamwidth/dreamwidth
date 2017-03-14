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

use List::Util qw/ min /;

########################################################################
###  28. Userpic-Related Functions

=head2 Userpic-Related Functions

=head3 C<< $u->activate_userpics >>

Sets/unsets userpics as inactive based on account caps.

=cut
sub activate_userpics {
    my $u = shift;

    # this behavior is optional, but enabled by default
    return 1 if $LJ::ALLOW_PICS_OVER_QUOTA;

    return undef unless LJ::isu($u);

    # can't get a cluster read for expunged users since they are clusterid 0,
    # so just return 1 to the caller from here and act like everything went fine
    return 1 if $u->is_expunged;

    my $userid = $u->userid;
    my $have_mapid = $u->userpic_have_mapid;

    # active / inactive lists
    my @active = ();
    my @inactive = ();

    # get a database handle for reading/writing
    my $dbh = LJ::get_db_writer();
    my $dbcr = LJ::get_cluster_def_reader($u);

    # select all userpics and build active / inactive lists
    return undef unless $dbcr;
    my $sth = $dbcr->prepare( "SELECT picid, state FROM userpic2 WHERE userid=?" );
    $sth->execute($userid);
    while (my ($picid, $state) = $sth->fetchrow_array) {
        next if $state eq 'X'; # expunged, means userpic has been removed from site by admins
        if ($state eq 'I') {
            push @inactive, $picid;
        } else {
            push @active, $picid;
        }
    }

    # inactivate previously activated userpics
    my $allowed = $u->userpic_quota;
    if (scalar @active > $allowed) {
        my $to_ban = scalar @active - $allowed;

        # find first jitemid greater than time 2 months ago using rlogtime index
        # ($LJ::EndOfTime - UnixTime)
        my $jitemid = $dbcr->selectrow_array("SELECT jitemid FROM log2 USE INDEX (rlogtime) " .
                                             "WHERE journalid=? AND rlogtime > ? LIMIT 1",
                                             undef, $userid, $LJ::EndOfTime - time() + 86400*60);

        # query all pickws in logprop2 with jitemid > that value
        my %count_kw = ();
        my $propid;
        if ( $have_mapid ) {
            $propid = LJ::get_prop("log", "picture_mapid")->{id};
        } else {
            $propid = LJ::get_prop("log", "picture_keyword")->{id};
        }
        my $sth = $dbcr->prepare("SELECT value, COUNT(*) FROM logprop2 " .
                                 "WHERE journalid=? AND jitemid > ? AND propid=?" .
                                 "GROUP BY value");
        $sth->execute($userid, $jitemid || 0, $propid);
        while (my ($value, $ct) = $sth->fetchrow_array) {
            # keyword => count
            $count_kw{$value} = $ct;
        }

        my $values_in = join(",", map { $dbh->quote($_) } keys %count_kw);

        # map pickws to picids for freq hash below
        my %count_picid = ();
        if ( $values_in ) {
            if ( $have_mapid ) {
                foreach my $mapid ( keys %count_kw ) {
                    my $picid = $u->get_picid_from_mapid($mapid);
                    $count_picid{$picid} += $count_kw{$mapid} if $picid;
                }
            } else {
                my $sth = $dbcr->prepare( "SELECT k.keyword, m.picid FROM userkeywords k, userpicmap2 m ".
                                        "WHERE k.keyword IN ($values_in) AND k.kwid=m.kwid AND k.userid=m.userid " .
                                        "AND k.userid=?" );
                $sth->execute($userid);
                while (my ($keyword, $picid) = $sth->fetchrow_array) {
                    # keyword => picid
                    $count_picid{$picid} += $count_kw{$keyword};
                }
            }
        }

        # we're only going to ban the least used, excluding the user's default
        my @ban = (grep { $_ != $u->{defaultpicid} }
                   sort { $count_picid{$a} <=> $count_picid{$b} } @active);

        @ban = splice(@ban, 0, $to_ban) if @ban > $to_ban;
        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        $u->do( "UPDATE userpic2 SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                undef, $userid ) if $ban_in;
    }

    # activate previously inactivated userpics
    if (scalar @inactive && scalar @active < $allowed) {
        my $to_activate = $allowed - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        if ( $activate_in ) {
            $u->do( "UPDATE userpic2 SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                    undef, $userid );
        }
    }

    # delete userpic info object from memcache
    LJ::Userpic->delete_cache($u);
    $u->clear_userpic_kw_map;

    return 1;
}


=head3 C<< $u->allpics_base >>

Return the base URL for the icons page.

=cut
sub allpics_base {
    return $_[0]->journal_base . "/icons";
}

=head3 C<< $u->clear_userpic_kw_map >>

Clears the internally cached mapping of userpics to keywords for this user.

=cut
sub clear_userpic_kw_map {
    $_[0]->{picid_kw_map} = undef;
}

=head3 C<< $u->expunge_userpic( $picid ) >>

Expunges a userpic so that the system will no longer deliver this userpic.

=cut
# If your site has off-site caching or something similar, you can also define
# a hook "expunge_userpic" which will be called with a picid and userid when
# a pic is expunged.
sub expunge_userpic {
    my ( $u, $picid ) = @_;
    $picid += 0;
    return undef unless $picid && LJ::isu( $u );

    # get the pic information
    my $state;

    my $dbcm = LJ::get_cluster_master( $u );
    return undef unless $dbcm && $u->writer;

    $state = $dbcm->selectrow_array( 'SELECT state FROM userpic2 WHERE userid = ? AND picid = ?',
                                     undef, $u->userid, $picid );
    return undef unless $state; # invalid pic
    return $u->userid if $state eq 'X'; # already expunged

    # else now mark it
    $u->do( "UPDATE userpic2 SET state='X' WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    return LJ::error( $dbcm ) if $dbcm->err;

    # Since we don't clean userpicmap2 when we migrate to dversion 9, clean it here on expunge no matter the dversion.
    $u->do( "DELETE FROM userpicmap2 WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    if ( $u->userpic_have_mapid ) {
        $u->do( "DELETE FROM userpicmap3 WHERE userid = ? AND picid = ? AND kwid=NULL", undef, $u->userid, $picid );
        $u->do( "UPDATE userpicmap3 SET picid = NULL WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    }

    # now clear the user's memcache picture info
    LJ::Userpic->delete_cache( $u );

    # call the hook and get out of here
    my @rval = LJ::Hooks::run_hooks( 'expunge_userpic', $picid, $u->userid );
    return ( $u->userid, map {$_->[0]} grep {$_ && @$_ && $_->[0]} @rval );
}

=head3 C<< $u->get_keyword_from_mapid( $mapid, %opts ) >>

Returns the keyword for the given mapid or undef if the mapid doesn't exist.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub get_keyword_from_mapid {
    my ( $u, $mapid, %opts ) = @_;
    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return undef unless $info;
    return undef unless $u->userpic_have_mapid;

    $mapid = $u->resolve_mapid_redirects($mapid,%opts);
    my $kw = $info->{mapkw}->{ $mapid };
    return $kw;
}

=head3 C<< $u->get_mapid_from_keyword( $kw, %opts ) >>

Returns the mapid for a given keyword.

Arguments:

=over 4

=item kw

The keyword.

=back

Additional options:

=over 4

=item create

Should a mapid be created if one does not exist.

Default: 0

=back

=cut
sub get_mapid_from_keyword {
    my ( $u, $kw, %opts ) = @_;
    return 0 unless $u->userpic_have_mapid;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return 0 unless $info;

    my $mapid = $info->{kwmap}->{$kw};
    return $mapid if $mapid;

    # the silly "pic#2343" thing when they didn't assign a keyword, if we get here
    # we need to create it.
    if ( $kw =~ /^pic\#(\d+)$/ ) {
        my $picid = $1;
        return 0 unless $info->{pic}{$picid};           # don't create rows for invalid pics
        return 0 unless $info->{pic}{$picid}{state} eq 'N'; # or inactive

        return $u->_create_mapid( undef, $picid )
    }

    return 0 unless $opts{create};

    return $u->_create_mapid( $u->get_keyword_id( $kw ), undef );
}

=head3 C<< $u->get_picid_from_keyword( $kw, $default ) >>

Returns the picid for a given keyword.

=over 4

=item kw

Keyword to look up.

=item default (optional)

Default: the users default userpic.

=back

=cut
sub get_picid_from_keyword {
    my ( $u, $kw, $default ) = @_;
    $default ||= ref $u ? $u->{defaultpicid} : 0;
    return $default unless defined $kw;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return $default unless $info;

    my $pr = $info->{kw}{$kw};
    # normal keyword
    return $pr->{picid} if $pr->{picid};

    # the silly "pic#2343" thing when they didn't assign a keyword
    if ( $kw =~ /^pic\#(\d+)$/ ) {
        my $picid = $1;
        return $picid if $info->{pic}{$picid};
    }

    return $default;
}

=head3 C<< $u->get_picid_from_mapid( $mapid, %opts ) >>

Returns the picid for a given mapid.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item default

Default: the users default userpic.

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub get_picid_from_mapid {
    my ( $u, $mapid, %opts ) = @_;
    my $default = $opts{default} || ref $u ? $u->{defaultpicid} : 0;
    return $default unless $mapid;
    return $default unless $u->userpic_have_mapid;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return $default unless $info;

    $mapid = $u->resolve_mapid_redirects($mapid,%opts);
    my $pr = $info->{mapid}{$mapid};

    return $pr->{picid} if $pr->{picid};

    return $default;
}

=head3 C<< $u->get_userpic_count >>

Return the number of userpics.

=cut
sub get_userpic_count {
    my $u = shift or return undef;
    my $count = scalar LJ::Userpic->load_user_userpics($u);

    return $count;
}

=head3 C<< $u->get_userpic_info( $opts ) >>

Given a user, gets their userpic information

Arguments:

=over 4

=item opts

Hashref of options

Valid options:

=over 4

=item load_comments

=item load_urls

=item load_descriptions

=back

Returns a hashref with the following keys:

=over 4

=item comment

Maps a picid to a comment.
May not be present if load_comments was not specified.

=item description

Maps a picid to a description.
May not be present if load_descriptions was not specified.

=item kw

Maps a keyword to a pic hashref.

=item kwmap

Maps a keyword to a mapid.

=item map_redir

Maps a mapid to a diffrent mapid.

=item mapid

Maps a mapid to a pic hashref.

=item mapkw

Maps a mapid to a keyword.

=item pic

Maps a picid to a pic hashref.

=back

=back

=cut
# returns: hash of userpicture information;
#          for efficiency, we store the userpic structures
#          in memcache in a packed format.
# info: memory format:
#       [
#       version number of format,
#       userid,
#       "packed string", which expands to an array of {width=>..., ...}
#       "packed string", which expands to { 'kw1' => id, 'kw2' => id, ...}
#       series of 3 4-byte numbers, which expands to { mapid1 => id, mapid2 => id, ...}, as well as { mapid1 => mapid2 }
#       "packed string", which expands to { 'kw1' => mapid, 'kw2' => mapid, ...}
#       ]
sub get_userpic_info {
    my ( $u, $opts ) = @_;
    return undef unless LJ::isu( $u ) && $u->clusterid;
    my $mapped_icons = $u->userpic_have_mapid;

    # in the cache, cool, well unless it doesn't have comments or urls or descriptions
    # and we need them
    if (my $cachedata = $LJ::CACHE_USERPIC_INFO{ $u->userid }) {
        my $good = 1;
        $good = 0 if $opts->{load_comments} && ! $cachedata->{_has_comments};
        $good = 0 if $opts->{load_urls} && ! $cachedata->{_has_urls};
        $good = 0 if $opts->{load_descriptions} && ! $cachedata->{_has_descriptions};

        return $cachedata if $good;
    }

    my $VERSION_PICINFO = 4;

    my $memkey = [$u->userid,"upicinf:$u->{'userid'}"];
    my ($info, $minfo);

    if ($minfo = LJ::MemCache::get($memkey)) {
        # the pre-versioned memcache data was a two-element hash.
        # since then, we use an array and include a version number.

        if (ref $minfo eq 'HASH' ||
            $minfo->[0] != $VERSION_PICINFO) {
            # old data in the cache.  delete.
            LJ::MemCache::delete($memkey);
        } else {
            my (undef, $picstr, $kwstr, $picmapstr, $kwmapstr) = @$minfo;
            $info = {
                pic => {},
                kw => {}
            };
            while (length $picstr >= 7) {
                my $pic = { userid => $u->userid };
                ($pic->{picid},
                 $pic->{width}, $pic->{height},
                 $pic->{state}) = unpack "NCCA", substr($picstr, 0, 7, '');
                $info->{pic}->{$pic->{picid}} = $pic;
            }

            my ($pos, $nulpos);
            $pos = $nulpos = 0;
            while (($nulpos = index($kwstr, "\0", $pos)) > 0) {
                my $kw = substr($kwstr, $pos, $nulpos-$pos);
                my $id = unpack("N", substr($kwstr, $nulpos+1, 4));
                $pos = $nulpos + 5; # skip NUL + 4 bytes.
                $info->{kw}->{$kw} = $info->{pic}->{$id};
            }

            if ( $mapped_icons ) {
                if ( defined $picmapstr && defined $kwmapstr ) {
                    $pos =  0;
                    while ($pos < length($picmapstr)) {
                        my ($mapid, $id, $redir) = unpack("NNN", substr($picmapstr, $pos, 12));
                        $pos += 12; # 3 * 4 bytes.
                        $info->{mapid}->{$mapid} = $info->{pic}{$id} if $id;
                        $info->{map_redir}->{$mapid} = $redir if $redir;
                    }

                    $pos = $nulpos = 0;
                    while (($nulpos = index($kwmapstr, "\0", $pos)) > 0) {
                        my $kw = substr($kwmapstr, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($kwmapstr, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{kwmap}->{$kw} = $id;
                        $info->{mapkw}->{$id} = $kw || "pic#" . $info->{mapid}->{$id}->{picid};
                    }
                } else { # This user is on dversion 9, but the data isn't in memcache
                         # so force a db load
                    undef $info;
                }
            }
        }


        # Load picture comments
        if ( $opts->{load_comments} && $info ) {
            my $commemkey = [$u->userid, "upiccom:" . $u->userid];
            my $comminfo = LJ::MemCache::get( $commemkey );

            if ( defined( $comminfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $comminfo, "\0", $pos )) > 0 ) {
                    my $comment = substr( $comminfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $comminfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{comment} = $comment;
                    $info->{comment}->{$id} = $comment;
                }
                $info->{_has_comments} = 1;
            } else { # Requested to load comments, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }

        # Load picture urls
        if ( $opts->{load_urls} && $info ) {
            my $urlmemkey = [$u->userid, "upicurl:" . $u->userid];
            my $urlinfo = LJ::MemCache::get( $urlmemkey );

            if ( defined( $urlinfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $urlinfo, "\0", $pos )) > 0 ) {
                    my $url = substr( $urlinfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $urlinfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{url} = $url;
                }
                $info->{_has_urls} = 1;
            } else { # Requested to load urls, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }

        # Load picture descriptions
        if ( $opts->{load_descriptions} && $info ) {
            my $descmemkey = [$u->userid, "upicdes:" . $u->userid];
            my $descinfo = LJ::MemCache::get( $descmemkey );

            if ( defined ( $descinfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $descinfo, "\0", $pos )) > 0 ) {
                    my $description = substr( $descinfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $descinfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{description} = $description;
                    $info->{description}->{$id} = $description;
                }
                $info->{_has_descriptions} = 1;
            } else { # Requested to load descriptions, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }
    }

    my %minfocom; # need this in this scope
    my %minfourl;
    my %minfodesc;
    unless ($info) {
        $info = {
            pic => {},
            kw => {}
        };
        my ($picstr, $kwstr, $predirstr, $kwmapstr);
        my $sth;
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        return undef unless $dbcr && $db;

        $sth = $dbcr->prepare( "SELECT picid, width, height, state, userid, comment, url, description ".
                               "FROM userpic2 WHERE userid=?" );
        $sth->execute( $u->userid );
        my @pics;
        while (my $pic = $sth->fetchrow_hashref) {
            next if $pic->{state} eq 'X'; # no expunged pics in list
            push @pics, $pic;
            $info->{pic}->{$pic->{picid}} = $pic;
            $minfocom{int($pic->{picid})} = $pic->{comment}
                if $opts->{load_comments} && $pic->{comment};
            $minfourl{int($pic->{picid})} = $pic->{url}
                if $opts->{load_urls} && $pic->{url};
            $minfodesc{int($pic->{picid})} = $pic->{description}
                if $opts->{load_descriptions} && $pic->{description};
        }


        $picstr = join('', map { pack("NCCA", $_->{picid},
                                 $_->{width}, $_->{height}, $_->{state}) } @pics);

        if ( $mapped_icons ) {
            $sth = $dbcr->prepare( "SELECT k.keyword, m.picid, m.mapid, m.redirect_mapid FROM userpicmap3 m LEFT JOIN userkeywords k ON ".
                                "( m.userid=k.userid AND m.kwid=k.kwid ) WHERE m.userid=?" );
        } else {
            $sth = $dbcr->prepare( "SELECT k.keyword, m.picid FROM userpicmap2 m, userkeywords k ".
                                "WHERE k.userid=? AND m.kwid=k.kwid AND m.userid=k.userid" );
        }
        $sth->execute($u->{'userid'});
        my %minfokw;
        my %picmap;
        my %kwmap;
        while (my ($kw, $id, $mapid, $redir) = $sth->fetchrow_array) {
            # used to be a bug that allowed these to get in.
            next if $kw =~ /[\n\r\0]/ || ( defined $kw && length($kw) == 0 );

            my $skip_kw = 0;
            if ( $mapped_icons ) {
                $picmap{$mapid} = [ int($id), int($redir) ];
                if ( $redir ) {
                    $info->{map_redir}->{$mapid} = $redir;
                } else {
                    unless ( defined $kw ) {
                        $skip_kw = 1;
                        $kw = "pic#$id";
                    }
                    $info->{kwmap}->{$kw} = $kwmap{$kw} = $mapid;
                    $info->{mapkw}->{$mapid} = $kw;
                }
            }
            next if $skip_kw;

            next unless $info->{pic}->{$id};
            $info->{kw}->{$kw} = $info->{pic}->{$id};
            $info->{mapid}->{$mapid} = $info->{pic}->{$id} if $mapped_icons && $id;
            $minfokw{$kw} = int($id);
        }
        $kwstr = join('', map { pack("Z*N", $_, $minfokw{$_}) } keys %minfokw);
        if ( $mapped_icons ) {
            $predirstr = join('', map { pack("NNN", $_, @{ $picmap{$_} } ) } keys %picmap);
            $kwmapstr = join('', map { pack("Z*N", $_, $kwmap{$_}) } keys %kwmap);
        }

        $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
        $minfo = [ $VERSION_PICINFO, $picstr, $kwstr, $predirstr, $kwmapstr ];
        LJ::MemCache::set($memkey, $minfo);

        if ( $opts->{load_comments} ) {
            $info->{comment} = \%minfocom;
            my $commentstr = join( '', map { pack( "Z*N", $minfocom{$_}, $_ ) } keys %minfocom );

            my $memkey = [$u->userid, "upiccom:" . $u->userid];
            LJ::MemCache::set( $memkey, $commentstr );

            $info->{_has_comments} = 1;
        }

        if ($opts->{load_urls}) {
            my $urlstr = join( '', map { pack( "Z*N", $minfourl{$_}, $_ ) } keys %minfourl );

            my $memkey = [$u->userid, "upicurl:" . $u->userid];
            LJ::MemCache::set( $memkey, $urlstr );

            $info->{_has_urls} = 1;
        }

        if ($opts->{load_descriptions}) {
            $info->{description} = \%minfodesc;
            my $descstring = join( '', map { pack( "Z*N", $minfodesc{$_}, $_ ) } keys %minfodesc );

            my $memkey = [$u->userid, "upicdes:" . $u->userid];
            LJ::MemCache::set( $memkey, $descstring );

            $info->{_has_descriptions} = 1;
        }
    }

    $LJ::CACHE_USERPIC_INFO{$u->userid} = $info;
    return $info;
}

=head3 C<< $u->get_userpic_kw_map >>

Gets a mapping from userpic ids to keywords for this User.

=cut
sub get_userpic_kw_map {
    my ( $u ) = @_;

    return $u->{picid_kw_map} if $u->{picid_kw_map};  # cache

    my $picinfo = $u->get_userpic_info( { load_comments => 0 } );
    my $keywords = {};
    foreach my $keyword ( keys %{$picinfo->{kw}} ) {
        my $picid = $picinfo->{kw}->{$keyword}->{picid};
        $keywords->{$picid} = [] unless $keywords->{$picid};
        push @{$keywords->{$picid}}, $keyword
            if defined $keyword && $picid && $keyword !~ m/^pic\#(\d+)$/;
    }

    return $u->{picid_kw_map} = $keywords;
}

=head3 C<< $u->resolve_mapid_redirects( $mapid, %opts ) >>

Resolve any mapid redirect, guarding against any redirect loops.

Returns: new map id, or 0 if the mapping cannot be resolved.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub resolve_mapid_redirects {
    my ( $u, $mapid, %opts ) = @_;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return 0 unless $info;

    my %seen = ( $mapid => 1 );
    my $orig_id = $mapid;

    while ( $info->{map_redir}->{ $mapid } ) {
        $orig_id = $mapid;
        $mapid = $info->{map_redir}->{ $mapid };

        # To implement lazy updating or the like
        $opts{redir_callback}->($u, $orig_id, $mapid) if $opts{redir_callback};

        # This should never happen, but am checking it here mainly in case
        # never *does* happen, so we don't hang the web process with an endless loop.
        if ( $seen{$mapid}++ ) {
            warn("userpicmap3 redirectloop for " . $u->id . " on mapid " . $mapid);
            return 0;
        }
    }

    return $mapid;
}

=head3 C<< $u->userpic >>

Returns LJ::Userpic for default userpic, if it exists.

=cut
sub userpic {
    my $u = shift;
    return undef unless $u->{defaultpicid};
    return LJ::Userpic->new($u, $u->{defaultpicid});
}

=head3 C<< $u->userpic_have_mapid >>

Returns true if the userpicmap keyword mappings have a mapid column ( dversion 9 or higher )

=cut
# FIXME: This probably should be userpics_use_mapid
sub userpic_have_mapid {
    return $_[0]->dversion >= 9;
}

=head3 C<< $u->userpic_quota >>

Returns the number of userpics the user can upload (base account type cap + bonus slots purchased)

=cut
sub userpic_quota {
    my $u = shift or return undef;
    my $ct = $u->get_cap( 'userpics' );
    $ct += $u->prop('bonus_icons') || 0
        if $u->is_paid; # paid accounts get bonus icons
    return min( $ct, $LJ::USERPIC_MAXIMUM );
}

# Intentionally no POD here.
# This is an internal helper method
# takes a $kwid and $picid ( either can be undef )
# and creates a mapid row for it
sub _create_mapid {
    my ( $u, $kwid, $picid ) = @_;
    return 0 unless $u->userpic_have_mapid;

    my $mapid = LJ::alloc_user_counter($u,'Y');
    $u->do( "INSERT INTO userpicmap3 (userid, mapid, kwid, picid) VALUES (?,?,?,?)", undef, $u->id, $mapid, $kwid, $picid);
    return 0 if $u->err;

    LJ::Userpic->delete_cache($u);
    $u->clear_userpic_kw_map;

    return $mapid;
}


1;
