package LJ;
use strict;

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpic at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids.
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
# </LJFUNC>
sub load_userpics
{
    &nodb;
    my ($upics, $idlist) = @_;

    return undef unless ref $idlist eq 'ARRAY' && $idlist->[0];

    # deal with the old calling convention, just an array ref of picids eg. [7, 4, 6, 2]
    if (! ref $idlist->[0] && $idlist->[0]) { # assume we have an old style caller
        my $in = join(',', map { $_+0 } @$idlist);
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT userid, picid, width, height " .
                                "FROM userpic WHERE picid IN ($in)");

        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            my $id = $_->{'picid'};
            undef $_->{'picid'};
            $upics->{$id} = $_;
        }
        return;
    }

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
    my @load_list_d6;
    foreach my $row (@load_list) {
        # ignore users on clusterid 0
        next unless $row->[0]->{clusterid};

        if ($row->[0]->{'dversion'} > 6) {
            push @{$db_load{$row->[0]->{'clusterid'}}}, $row;
        } else {
            push @load_list_d6, $row;
        }
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

    # following path is only for old style d6 userpics... don't load any if we don't
    # have any to load
    return unless @load_list_d6;

    my $dbr = LJ::get_db_writer();
    my $picid_in = join(',', map { $_->[1] } @load_list_d6);
    my $sth = $dbr->prepare("SELECT userid, picid, width, height, contenttype, state, ".
                            "       UNIX_TIMESTAMP(picdate) AS 'picdate' ".
                            "FROM userpic WHERE picid IN ($picid_in)");
    $sth->execute;
    while (my $ur = $sth->fetchrow_hashref) {
        my $id = delete $ur->{'picid'};
        $upics->{$id} = $ur;

        # force into numeric context so they'll be smaller in memcache:
        foreach my $k (qw(userid width height picdate)) {
            $ur->{$k} += 0;
        }
        $ur->{location} = "?";
        $ur->{flags} = undef;
        $ur->{fmt} = {
            'image/gif' => 'G',
            'image/jpeg' => 'J',
            'image/png' => 'P',
        }->{delete $ur->{contenttype}};

        $LJ::CACHE_USERPIC{$id} = $ur;
        LJ::MemCache::set([$id,"userpic.$id"], LJ::MemCache::hash_to_array("userpic", $ur));
    }
}

# <LJFUNC>
# name: LJ::expunge_userpic
# des: Expunges a userpic so that the system will no longer deliver this userpic.  If
#      your site has off-site caching or something similar, you can also define a hook
#      "expunge_userpic" which will be called with a picid and userid when a pic is
#      expunged.
# args: u, picid
# des-picid: ID of the picture to expunge.
# des-u: User object
# returns: undef on error, or the userid of the picture owner on success.
# </LJFUNC>
sub expunge_userpic {
    # take in a picid and expunge it from the system so that it can no longer be used
    my ($u, $picid) = @_;
    $picid += 0;
    return undef unless $picid && ref $u;

    # get the pic information
    my $state;

    if ($u->{'dversion'} > 6) {
        my $dbcm = LJ::get_cluster_master($u);
        return undef unless $dbcm && $u->writer;

        $state = $dbcm->selectrow_array('SELECT state FROM userpic2 WHERE userid = ? AND picid = ?',
                                        undef, $u->{'userid'}, $picid);
        return undef unless $state; # invalid pic
        return $u->{'userid'} if $state eq 'X'; # already expunged

        # else now mark it
        $u->do("UPDATE userpic2 SET state='X' WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
        return LJ::error($dbcm) if $dbcm->err;
        $u->do("DELETE FROM userpicmap2 WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
    } else {
        my $dbr = LJ::get_db_reader();
        return undef unless $dbr;

        $state = $dbr->selectrow_array('SELECT state FROM userpic WHERE picid = ?',
                                       undef, $picid);
        return undef unless $state; # invalid pic
        return $u->{'userid'} if $state eq 'X'; # already expunged

        # else now mark it
        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;
        $dbh->do("UPDATE userpic SET state='X' WHERE picid = ?", undef, $picid);
        return LJ::error($dbh) if $dbh->err;
        $dbh->do("DELETE FROM userpicmap WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
    }

    # now clear the user's memcache picture info
    LJ::Userpic->delete_cache($u);

    # call the hook and get out of here
    my @rval = LJ::run_hooks('expunge_userpic', $picid, $u->{'userid'});
    return ($u->{'userid'}, map {$_->[0]} grep {$_ && @$_ && $_->[0]} @rval);
}

# <LJFUNC>
# name: LJ::activate_userpics
# des: Wrapper around LJ::User->activate_userpics for compatibility.
# args: uuserid
# returns: undef on failure 1 on success
# </LJFUNC>
sub activate_userpics
{
    my $u = shift;
    return undef unless LJ::isu($u);

    # if a userid was given, get a real $u object
    $u = LJ::load_userid($u, "force") unless isu($u);

    # should have a $u object now
    return undef unless isu($u);

    return $u->activate_userpics;
}

# <LJFUNC>
# name: LJ::get_userpic_info
# des: Given a user, gets their userpic information.
# args: uuid, opts?
# des-uuid: userid, or user object.
# des-opts: Optional; hash of options, 'load_comments'.
# returns: hash of userpicture information;
#          for efficiency, we store the userpic structures
#          in memcache in a packed format.
# info: memory format:
#       [
#       version number of format,
#       userid,
#       "packed string", which expands to an array of {width=>..., ...}
#       "packed string", which expands to { 'kw1' => id, 'kw2' => id, ...}
#       ]
# </LJFUNC>

sub get_userpic_info
{
    my ($uuid, $opts) = @_;
    return undef unless $uuid;
    my $userid = LJ::want_userid($uuid);
    my $u = LJ::want_user($uuid); # This should almost always be in memory already
    return undef unless $u && $u->{clusterid};

    # in the cache, cool, well unless it doesn't have comments or urls
    # and we need them
    if (my $cachedata = $LJ::CACHE_USERPIC_INFO{$userid}) {
        my $good = 1;
        if ($u->{'dversion'} > 6) {
            $good = 0 if $opts->{'load_comments'} && ! $cachedata->{'_has_comments'};
            $good = 0 if $opts->{'load_urls'} && ! $cachedata->{'_has_urls'};
        }
        return $cachedata if $good;
    }

    my $VERSION_PICINFO = 3;

    my $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
    my ($info, $minfo);

    if ($minfo = LJ::MemCache::get($memkey)) {
        # the pre-versioned memcache data was a two-element hash.
        # since then, we use an array and include a version number.

        if (ref $minfo eq 'HASH' ||
            $minfo->[0] != $VERSION_PICINFO) {
            # old data in the cache.  delete.
            LJ::MemCache::delete($memkey);
        } else {
            my (undef, $picstr, $kwstr) = @$minfo;
            $info = {
                'pic' => {},
                'kw' => {},
            };
            while (length $picstr >= 7) {
                my $pic = { userid => $u->{'userid'} };
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
                $info->{kw}->{$kw} = $info->{pic}->{$id} if $info;
            }
        }

        if ($u->{'dversion'} > 6) {

            # Load picture comments
            if ($opts->{'load_comments'}) {
                my $commemkey = [$u->{'userid'}, "upiccom:$u->{'userid'}"];
                my $comminfo = LJ::MemCache::get($commemkey);

                if ($comminfo) {
                    my ($pos, $nulpos);
                    $pos = $nulpos = 0;
                    while (($nulpos = index($comminfo, "\0", $pos)) > 0) {
                        my $comment = substr($comminfo, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($comminfo, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{'pic'}->{$id}->{'comment'} = $comment;
                        $info->{'comment'}->{$id} = $comment;
                    }
                    $info->{'_has_comments'} = 1;
                } else { # Requested to load comments, but they aren't in memcache
                         # so force a db load
                    undef $info;
                }
            }

            # Load picture urls
            if ($opts->{'load_urls'} && $info) {
                my $urlmemkey = [$u->{'userid'}, "upicurl:$u->{'userid'}"];
                my $urlinfo = LJ::MemCache::get($urlmemkey);

                if ($urlinfo) {
                    my ($pos, $nulpos);
                    $pos = $nulpos = 0;
                    while (($nulpos = index($urlinfo, "\0", $pos)) > 0) {
                        my $url = substr($urlinfo, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($urlinfo, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{'pic'}->{$id}->{'url'} = $url;
                    }
                    $info->{'_has_urls'} = 1;
                } else { # Requested to load urls, but they aren't in memcache
                         # so force a db load
                    undef $info;
                }
            }
        }
    }

    my %minfocom; # need this in this scope
    my %minfourl;
    unless ($info) {
        $info = {
            'pic' => {},
            'kw' => {},
        };
        my ($picstr, $kwstr);
        my $sth;
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        return undef unless $dbcr && $db;

        if ($u->{'dversion'} > 6) {
            $sth = $dbcr->prepare("SELECT picid, width, height, state, userid, comment, url ".
                                  "FROM userpic2 WHERE userid=?");
        } else {
            $sth = $db->prepare("SELECT picid, width, height, state, userid ".
                                "FROM userpic WHERE userid=?");
        }
        $sth->execute($u->{'userid'});
        my @pics;
        while (my $pic = $sth->fetchrow_hashref) {
            next if $pic->{state} eq 'X'; # no expunged pics in list
            push @pics, $pic;
            $info->{'pic'}->{$pic->{'picid'}} = $pic;
            $minfocom{int($pic->{picid})} = $pic->{comment} if $u->{'dversion'} > 6
                && $opts->{'load_comments'} && $pic->{'comment'};
            $minfourl{int($pic->{'picid'})} = $pic->{'url'} if $u->{'dversion'} > 6
                && $opts->{'load_urls'} && $pic->{'url'};
        }


        $picstr = join('', map { pack("NCCA", $_->{picid},
                                 $_->{width}, $_->{height}, $_->{state}) } @pics);

        if ($u->{'dversion'} > 6) {
            $sth = $dbcr->prepare("SELECT k.keyword, m.picid FROM userpicmap2 m, userkeywords k ".
                                  "WHERE k.userid=? AND m.kwid=k.kwid AND m.userid=k.userid");
        } else {
            $sth = $db->prepare("SELECT k.keyword, m.picid FROM userpicmap m, keywords k ".
                                "WHERE m.userid=? AND m.kwid=k.kwid");
        }
        $sth->execute($u->{'userid'});
        my %minfokw;
        while (my ($kw, $id) = $sth->fetchrow_array) {
            next unless $info->{'pic'}->{$id};
            next if $kw =~ /[\n\r\0]/;  # used to be a bug that allowed these to get in.
            $info->{'kw'}->{$kw} = $info->{'pic'}->{$id};
            $minfokw{$kw} = int($id);
        }
        $kwstr = join('', map { pack("Z*N", $_, $minfokw{$_}) } keys %minfokw);

        $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
        $minfo = [ $VERSION_PICINFO, $picstr, $kwstr ];
        LJ::MemCache::set($memkey, $minfo);

        if ($u->{'dversion'} > 6) {

            if ($opts->{'load_comments'}) {
                $info->{'comment'} = \%minfocom;
                my $commentstr = join('', map { pack("Z*N", $minfocom{$_}, $_) } keys %minfocom);

                my $memkey = [$u->{'userid'}, "upiccom:$u->{'userid'}"];
                LJ::MemCache::set($memkey, $commentstr);

                $info->{'_has_comments'} = 1;
            }

            if ($opts->{'load_urls'}) {
                my $urlstr = join('', map { pack("Z*N", $minfourl{$_}, $_) } keys %minfourl);

                my $memkey = [$u->{'userid'}, "upicurl:$u->{'userid'}"];
                LJ::MemCache::set($memkey, $urlstr);

                $info->{'_has_urls'} = 1;
            }
        }
    }

    $LJ::CACHE_USERPIC_INFO{$u->{'userid'}} = $info;
    return $info;
}

# <LJFUNC>
# name: LJ::get_pic_from_keyword
# des: Given a userid and keyword, returns the pic row hashref.
# args: u, keyword
# des-keyword: The keyword of the userpic to fetch.
# returns: hashref of pic row found
# </LJFUNC>
sub get_pic_from_keyword
{
    my ($u, $kw) = @_;
    my $info = LJ::get_userpic_info($u) or
        return undef;

    if (my $pic = $info->{'kw'}{$kw}) {
        return $pic;
    }

    # the lame "pic#2343" thing when they didn't assign a keyword
    if ($kw =~ /^pic\#(\d+)$/) {
        my $picid = $1;
        if (my $pic = $info->{'pic'}{$picid}) {
            return $pic;
        }
    }

    return undef;
}

sub get_picid_from_keyword
{
    my ($u, $kw, $default) = @_;
    $default ||= (ref $u ? $u->{'defaultpicid'} : 0);
    return $default unless $kw;

    my $info = LJ::get_userpic_info($u);
    return $default unless $info;

    my $pr = $info->{'kw'}{$kw};
    # normal keyword
    return $pr->{picid} if $pr->{'picid'};

    # the lame "pic#2343" thing when they didn't assign a keyword
    if ($kw =~ /^pic\#(\d+)$/) {
        my $picid = $1;
        return $picid if $info->{'pic'}{$picid};
    }

    return $default;
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
    my @args = @_;

    my $gc = LJ::gearman_client();

    # no gearman, do this in-process
    return LJ::_get_upf_scaled(@args)
        unless $gc;

    # invoke gearman
    my $u = LJ::get_remote()
        or die "No remote user";
    unshift @args, "userid" => $u->id;

    my $result;
    my $arg = Storable::nfreeze(\@args);
    my $task = Gearman::Task->new('lj_upf_resize', \$arg,
                                  {
                                      uniq => '-',
                                      on_complete => sub {
                                          my $res = shift;
                                          return unless $res;
                                          $result = Storable::thaw($$res);
                                      }
                                  });

    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait(timeout => 30); # 30 sec timeout;

    # job failed ... error reporting?
    die "Could not resize image down\n" unless $result;

    return $result;
}

# actual method
sub _get_upf_scaled
{
    my %opts = @_;
    my $size = delete $opts{size} || 640;
    my $x1 = delete $opts{x1};
    my $y1 = delete $opts{y1};
    my $x2 = delete $opts{x2};
    my $y2 = delete $opts{y2};
    my $border = delete $opts{border} || 0;
    my $maxfilesize = delete $opts{maxfilesize} || 38;
    my $u = LJ::want_user(delete $opts{userid} || delete $opts{u}) || LJ::get_remote();
    my $mogkey = delete $opts{mogkey};
    my $downsize_only = delete $opts{downsize_only};
    croak "No userid or remote" unless $u || $mogkey;

    $maxfilesize *= 1024;

    croak "Invalid parameters to get_upf_scaled\n" if scalar keys %opts;

    my $mode = ($x1 || $y1 || $x2 || $y2) ? "crop" : "scale";

    eval "use Image::Magick (); 1;"
        or return undef;

    eval "use Image::Size (); 1;"
        or return undef;

    $mogkey ||= 'upf:' . $u->{userid};
    my $dataref = LJ::mogclient()->get_file_data($mogkey) or return undef;

    # original width/height
    my ($ow, $oh) = Image::Size::imgsize($dataref);
    return undef unless $ow && $oh;

    # converts an ImageMagick object to the form returned to our callers
    my $imageParams = sub {
        my $im = shift;
        my $blob = $im->ImageToBlob;
        return [\$blob, $im->Get('MIME'), $im->Get('width'), $im->Get('height')];
    };

    # compute new width and height while keeping aspect ratio
    my $getSizedCoords = sub {
        my $newsize = shift;

        my $fromw = $ow;
        my $fromh = $oh;

        my $img = shift;
        if ($img) {
            $fromw = $img->Get('width');
            $fromh = $img->Get('height');
        }

        return (int($newsize * $fromw/$fromh), $newsize) if $fromh > $fromw;
        return ($newsize, int($newsize * $fromh/$fromw));
    };

    # get the "medium sized" width/height.  this is the size which
    # the user selects from
    my ($medw, $medh) = $getSizedCoords->($size);
    return undef unless $medw && $medh;

    # simple scaling mode
    if ($mode eq "scale") {
        my $image = Image::Magick->new(size => "${medw}x${medh}")
            or return undef;
        $image->BlobToImage($$dataref);
        unless ($downsize_only && ($medw > $ow || $medh > $oh)) {
            $image->Resize(width => $medw, height => $medh);
        }
        return $imageParams->($image);
    }

    # else, we're in 100x100 cropping mode

    # scale user coordinates  up from the medium pixelspace to full pixelspace
    $x1 *= ($ow/$medw);
    $x2 *= ($ow/$medw);
    $y1 *= ($oh/$medh);
    $y2 *= ($oh/$medh);

    # cropping dimensions from the full pixelspace
    my $tw = $x2 - $x1;
    my $th = $y2 - $y1;

    # but if their selected region in full pixelspace is 800x800 or something
    # ridiculous, no point decoding the JPEG to its full size... we can
    # decode to a smaller size so we get 100px when we crop
    my $min_dim = $tw < $th ? $tw : $th;
    my ($decodew, $decodeh) = ($ow, $oh);
    my $wanted_size = 100;
    if ($min_dim > $wanted_size) {
        # then let's not decode the full JPEG down from its huge size
        my $de_scale = $wanted_size / $min_dim;
        $decodew = int($de_scale * $decodew);
        $decodeh = int($de_scale * $decodeh);
        $_ *= $de_scale foreach ($x1, $x2, $y1, $y2);
    }

    $_ = int($_) foreach ($x1, $x2, $y1, $y2, $tw, $th);

    # make the pristine (uncompressed) 100x100 image
    my $timage = Image::Magick->new(size => "${decodew}x${decodeh}")
        or return undef;
    $timage->BlobToImage($$dataref);
    $timage->Scale(width => $decodew, height => $decodeh);

    my $w = ($x2 - $x1);
    my $h = ($y2 - $y1);
    my $foo = $timage->Mogrify(crop => "${w}x${h}+$x1+$y1");

    my $targetSize = $border ? 98 : 100;

    my ($nw, $nh) = $getSizedCoords->($targetSize, $timage);
    $timage->Scale(width => $nw, height => $nh);

    # add border if desired
    $timage->Border(geometry => "1x1", color => 'black') if $border;

    foreach my $qual (qw(100 90 85 75)) {
        # work off a copy of the image so we aren't recompressing it
        my $piccopy = $timage->Clone();
        $piccopy->Set('quality' => $qual);
        my $ret = $imageParams->($piccopy);
        return $ret if length(${ $ret->[0] }) < $maxfilesize;
    }

    return undef;
}


1;

