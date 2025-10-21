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

package LJ::SynSuck;
use strict;
use HTTP::Status;

use LJ::Protocol;
use LJ::ParseFeed;
use LJ::CleanHTML;
use DW::FeedCanonicalizer;

sub update_feed {
    my ( $urow, $verbose ) = @_;
    return unless $urow;

    my ( $user, $userid, $synurl, $lastmod, $etag, $readers ) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders);

    # we can't deal with non-visible journals.  try again in a couple
    # hours.  maybe they were unsuspended or whatever.

    my $su = LJ::load_userid($userid);
    return delay( $userid, 120, "non_statusvis_v" )
        unless $su->is_visible;

    # we're a child process now, need to invalidate caches and
    # get a new database handle
    LJ::start_request();

    my $resp = get_content( $urow, $verbose ) or return 0;
    return process_content( $urow, $resp, $verbose );
}

sub delay {
    my ( $userid, $minutes, $status, $synurl ) = @_;

    # add some random backoff to avoid waves building up
    $minutes += int( rand(5) );

    # in old ljmaint-based codepath, LJ::Worker::SynSuck won't be loaded.  hence the eval.
    eval {
        LJ::Worker::SynSuck->cond_debug(
            "Syndication userid $userid rescheduled for $minutes minutes due to $status");
    };

    my $token = defined $synurl ? DW::FeedCanonicalizer::canonicalize($synurl) : undef;

    my $dbh = LJ::get_db_writer();

    $dbh->do(
        "UPDATE syndicated SET lastcheck=NOW(), checknext=DATE_ADD(NOW(), "
            . "INTERVAL ? MINUTE), laststatus=?, fuzzy_token = COALESCE(?,fuzzy_token) WHERE userid=?",
        undef, $minutes, $status, $token, $userid
    );
    return undef;
}

sub max_size {
    my ($u) = @_;                                    # optional user object for feed
    my $max_size = $LJ::SYNSUCK_MAX_SIZE || 3000;    # in kb

    if ( $u && $u->has_priv( "siteadmin", "largefeedsize" ) ) {
        $max_size = $LJ::SYNSUCK_LARGE_MAX_SIZE || 6000;    # in kb
    }

    return 1024 * $max_size;                                # in bytes
}

sub get_content {
    my ( $urow, $verbose ) = @_;

    my ( $user, $userid, $synurl, $lastmod, $etag, $readers ) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders);

    my $dbh = LJ::get_db_writer();

    # see if things have changed since we last looked and acquired the lock.
    # otherwise we could 1) check work, 2) get lock, and between 1 and 2 another
    # process could do both steps.  we don't want to duplicate work already done.
    my $now_checknext =
        $dbh->selectrow_array( "SELECT checknext FROM syndicated " . "WHERE userid=?",
        undef, $userid );
    return if $now_checknext ne $urow->{checknext};

    my $ua          = LJ::get_useragent( role => 'syn_sucker' );
    my $reader_info = $readers ? "; $readers readers" : "";
    $ua->agent(
        "$LJ::SITENAME ($LJ::ADMIN_EMAIL; for $LJ::SITEROOT/users/$user/" . $reader_info . ")" );

    print "[$$] Synsuck: $user ($synurl)\n" if $verbose;

    my $req        = HTTP::Request->new( "GET", $synurl );
    my $can_accept = HTTP::Message::decodable;
    $req->header( 'Accept-Encoding',   $can_accept );
    $req->header( 'If-Modified-Since', LJ::time_to_http($lastmod) )
        if $lastmod;
    $req->header( 'If-None-Match', $etag )
        if $etag;

    my ( $content, $too_big );
    my $syn_u    = LJ::load_user($user);
    my $max_size = max_size($syn_u);
    my $res      = eval {
        $ua->request(
            $req,
            sub {
                if ( length($content) > $max_size ) { $too_big = 1; return; }
                $content .= $_[0];
            },
            4096
        );
    };
    if ($@)       { return delay( $userid, 120, "lwp_death" ); }
    if ($too_big) { return delay( $userid, 60,  "toobig" ); }

    # Since we are treating content specially above, we have to recreate
    #   the HTTP::Message with it to get the decoded content.
    my $message = HTTP::Message->new( $res->headers, $content );
    $content = $message->decoded_content( charset => 'none' );

    if ( $res->is_error() ) {

        # http error
        print "HTTP error!\n" if $verbose;

        # overload parseerror here because it's already there -- we'll
        # never have both an http error and a parse error on the
        # same request
        delay( $userid, 3 * 60, "parseerror" );

        $syn_u->set_prop( "rssparseerror", $res->status_line() ) if $syn_u;
        return;
    }

    # check if not modified
    if ( $res->code() == RC_NOT_MODIFIED ) {
        print "  not modified.\n" if $verbose;
        return delay( $userid, $readers ? 60 : 24 * 60, "notmodified", $synurl );
    }

    return [ $res, $content ];
}

# helper function which takes feed XML
# and returns a list of $num items from the feed
# in proper order
sub parse_items_from_feed {
    my ( $content, $num, $verbose ) = @_;
    $num ||= 20;
    return ( 0, { type => "noitems" } ) unless defined $content;

    # WARNING: blatant XML spec violation ahead...
    #
    # Blogger doesn't produce valid XML, since they don't handle encodings
    # correctly.  So if we see they have no encoding (which is UTF-8 implictly)
    # but it's not valid UTF-8, say it's Windows-1252, which won't
    # cause XML::Parser to barf... but there will probably be some bogus characters.
    # better than nothing I guess.  (personally, I'd prefer to leave it broken
    # and have people bitch at Blogger, but jwz wouldn't stop bugging me)
    # XML::Parser doesn't include Windows-1252, but we put it in cgi-bin/XML/* for it
    # to find.
    my $encoding;
    if ( $content =~ /(<\?xml.+?>)/ && $1 =~ /encoding=([\"\'])(.+?)\1/ ) {
        $encoding = lc($2);
    }
    if ( !$encoding && !LJ::is_utf8($content) ) {
        $content =~ s/\?>/ encoding='windows-1252' \?>/;
    }

    # WARNING: another hack...
    # People produce what they think is iso-8859-1, but they include
    # Windows-style smart quotes.  Check for invalid iso-8859-1 and correct.
    if ( $encoding =~ /^iso-8859-1$/i && $content =~ /[\x80-\x9F]/ ) {

        # They claimed they were iso-8859-1, but they are lying.
        # Assume it was Windows-1252.
        print "Invalid ISO-8859-1; assuming Windows-1252...\n" if $verbose;
        $content =~ s/encoding=([\"\'])(.+?)\1/encoding='windows-1252'/;
    }

    # ANOTHER hack: if a feed asks for ANSI_v3.4-1968 (ASCII), alias it to us-ascii
    if ( $encoding =~ /^ANSI_X3.4-1968$/i ) {
        $content =~ s/encoding=([\"\'])(.+?)\1/encoding='us-ascii'/;
    }

    # and yet another hack, this time to alias 'ascii' to 'us-ascii'
    if ( $encoding =~ /^ascii$/i ) {
        $content =~ s/encoding=([\"\'])(.+?)\1/encoding='us-ascii'/;
    }

    # parsing time...
    my ( $feed, $error ) = LJ::ParseFeed::parse_feed($content);
    return ( 0, { type => "parseerror", message => $error } ) if $error;

    # another sanity check
    return ( 0, { type => "noitems" } ) unless ref $feed->{items} eq "ARRAY";

    my @items = reverse @{ $feed->{items} }
        or return ( 0, { type => "noitems" } );

    # If the feed appears to be datestamped, resort chronologically,
    # from earliest to latest - oldest entries are posted first, below.
    my $timesort = sub { LJ::mysqldate_to_time( $_[0]->{time} ) };
    @items = sort { $timesort->($a) <=> $timesort->($b) } @items
        if $items[0]->{time};

    # take most recent 20
    splice( @items, 0, @items - $num ) if @items > $num;

    return ( 1, { items => \@items, feed => $feed } );
}

sub process_content {
    my ( $urow, $resp, $verbose ) = @_;

    my ( $res, $content ) = @$resp;
    my ( $user, $userid, $synurl, $lastmod, $etag, $readers, $fuzzy_token ) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders fuzzy_token);

    my $dbh = LJ::get_db_writer();

    my ( $ok, $rv ) = parse_items_from_feed( $content, 20, $verbose );
    unless ($ok) {
        if ( $rv->{type} eq "parseerror" ) {

            # parse error!
            delay( $userid, 3 * 60, "parseerror", $synurl );
            if ( my $error = $rv->{message} ) {
                print "Parse error! $error\n" if $verbose;
                $error =~ s! at /.*!!;
                $error =~ s/^\n//;       # cleanup of newline at the beginning of the line
                my $syn_u = LJ::load_user($user);
                $syn_u->set_prop( "rssparseerror", $error ) if $syn_u;
            }
            return;
        }
        elsif ( $rv->{type} eq "noitems" ) {
            return delay( $userid, 3 * 60, "noitems", $synurl );
        }
        else {
            print "Unknown error type!\n" if $verbose;
            return delay( $userid, 3 * 60, "unknown" );
        }
    }

    my $feed = $rv->{feed};

    # Eval'd so this failing for some reason doesn't break
    #   the feed
    my $final_url = eval { return $res->request->uri; };
    $feed->{final_url} = $final_url->as_string
        if $final_url;

    $fuzzy_token = DW::FeedCanonicalizer::canonicalize( $synurl, $feed );

    my @items = @{ $rv->{items} };

    # delete existing items older than the age which can show on a
    # friends view.
    my $su = LJ::load_userid($userid);

    my $udbh = LJ::get_cluster_master($su);
    unless ($udbh) {
        return delay( $userid, 15, "nodb" );
    }

    # TAG:LOG2:synsuck_delete_olderitems
    my $secs = ( $LJ::MAX_FRIENDS_VIEW_AGE || 3600 * 24 * 14 ) + 0;    # 2 week default.
    my $sth = $udbh->prepare( "SELECT jitemid, anum FROM log2 WHERE journalid=? AND "
            . "logtime < DATE_SUB(NOW(), INTERVAL $secs SECOND)" );
    $sth->execute($userid);
    die $udbh->errstr if $udbh->err;
    while ( my ( $jitemid, $anum ) = $sth->fetchrow_array ) {
        print "DELETE itemid: $jitemid, anum: $anum... \n" if $verbose;
        if ( LJ::delete_entry( $su, $jitemid, 0, $anum ) ) {
            print "success.\n" if $verbose;
        }
        else {
            print "fail.\n" if $verbose;
        }
    }

    # determine if link tags are good or not, where good means
    # "likely to be a unique per item".  some feeds have the same
    # <link> element for each item, which isn't good.
    # if we have unique ids, we don't compare link tags

    my ( $compare_links, $have_ids ) = 0;
    {
        my %link_seen;
        foreach my $it (@items) {
            $have_ids = 1 if $it->{'id'};
            next unless $it->{'link'};
            $link_seen{ $it->{'link'} } = 1;
        }
        $compare_links = 1
            if !$have_ids
            and $feed->{'type'} eq 'rss'
            and scalar( keys %link_seen ) == scalar(@items);
    }

    # if we have unique links/ids, load them for syndicated
    # items we already have on the server.  then, if we have one
    # already later and see it's changed, we'll do an editevent
    # instead of a new post.
    my %existing_item = ();
    if ( $have_ids || $compare_links ) {
        my $p =
            $have_ids
            ? LJ::get_prop( "log", "syn_id" )
            : LJ::get_prop( "log", "syn_link" );
        my $sth = $udbh->prepare(
            "SELECT jitemid, value FROM logprop2 WHERE " . "journalid=? AND propid=? LIMIT 1000" );
        $sth->execute( $su->{'userid'}, $p->{'id'} );
        while ( my ( $itemid, $id ) = $sth->fetchrow_array ) {
            $existing_item{$id} = $itemid;
        }
    }

    # post these items
    my $itemcount = scalar @items;
    my $newfeed   = !$su->timeupdate;    # true if never updated before
    my $newcount  = 0;
    my $errorflag = 0;
    my $mindate;                         # "yyyy-mm-dd hh:mm:ss";
    my $notedate = sub {
        my $date = shift;
        $mindate = $date if !$mindate || $date lt $mindate;
    };

    foreach my $it (@items) {

        # remove the SvUTF8 flag.  it's still UTF-8, but
        # we don't want perl knowing that and messing stuff up
        # for us behind our back in random places all over
        # http://zilla.livejournal.org/show_bug.cgi?id=1037
        foreach my $attr (qw(id subject text link author)) {
            next unless exists $it->{$attr} && defined $it->{$attr};
            $it->{$attr} = LJ::no_utf8_flag( $it->{$attr} );
        }

        # duplicate entry detection
        my $dig     = LJ::md5_struct($it)->b64digest;
        my $prevadd = $dbh->selectrow_array(
            "SELECT MAX(dateadd) FROM synitem WHERE " . "userid=? AND item=?",
            undef, $userid, $dig );
        if ($prevadd) {
            $notedate->($prevadd);
            $itemcount--;
            next;
        }

        my $now_dateadd = $dbh->selectrow_array("SELECT NOW()");
        die "unexpected format" unless $now_dateadd =~ /^\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d$/;

        $dbh->do( "INSERT INTO synitem (userid, item, dateadd) VALUES (?,?,?)",
            undef, $userid, $dig, $now_dateadd );
        $notedate->($now_dateadd);

        print "[$$] $dig - $it->{'subject'}\n" if $verbose;
        $it->{'text'} =~ s/^\s+//;
        $it->{'text'} =~ s/\s+$//;

        my $author = "";
        if ( defined $it->{author} ) {
            $author =
                "<p class='syndicationauthor'>Posted by " . LJ::ehtml( $it->{author} ) . "</p>";
        }

        my $htmllink;
        if ( defined $it->{'link'} ) {
            $htmllink = "<p class=\"ljsyndicationlink\">"
                . "<a href=\"$it->{'link'}\">$it->{'link'}</a></p>";
        }

        # Show the <guid> link if it's present and different than the
        # <link>.
        # [zilla: 267] Patch: Chaz Meyers <lj-zilla@thechaz.net>
        if (   defined $it->{'id'}
            && $it->{'id'} ne $it->{'link'}
            && $it->{'id'} =~ m!^https?://! )
        {
            $htmllink .=
                "<p class=\"ljsyndicationlink\">" . "<a href=\"$it->{'id'}\">$it->{'id'}</a></p>";
        }

        # rewrite relative URLs to absolute URLs, but only invoke the HTML parser
        # if we see there's some image or link tag, to save us some work if it's
        # unnecessary (the common case)
        if ( $it->{'text'} =~ /<(?:img|a)\b/i ) {

            # TODO: support XML Base?  http://www.w3.org/TR/xmlbase/
            my $base_href = $it->{'link'} || $synurl;
            LJ::CleanHTML::resolve_relative_urls( \$it->{'text'}, $base_href );
        }

        # $own_time==1 means we took the time from the feed rather than localtime
        my ( $own_time, $year, $mon, $day, $hour, $min );

        if (   $it->{'time'}
            && $it->{'time'} =~ m!^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)! )
        {
            $own_time = 1;
            ( $year, $mon, $day, $hour, $min ) = ( $1, $2, $3, $4, $5 );
        }
        else {
            $own_time = 0;
            my @now = localtime();
            ( $year, $mon, $day, $hour, $min ) =
                ( $now[5] + 1900, $now[4] + 1, $now[3], $now[2], $now[1] );
        }

        # just bail on entries older than two weeks instead of reposting them
        if ($own_time) {
            my $age = time() - LJ::mysqldate_to_time( $it->{'time'} );
            if ( $age > $secs ) {    # $secs is defined waaaaaaaay above
                $itemcount--;
                next;
            }
        }

        $newcount++;                 # we're committed to posting this item now

        my $command = "postevent";
        my $req     = {
            'username' => $user,
            'ver'      => 1,
            'subject'  => $it->{'subject'},
            'event'    => "$author$htmllink$it->{'text'}$htmllink",
            'year'     => $year,
            'mon'      => $mon,
            'day'      => $day,
            'hour'     => $hour,
            'min'      => $min,
            'props'    => {
                'syn_link' => $it->{'link'},
            },
        };
        $req->{'props'}->{'syn_id'} = $it->{'id'}
            if $it->{'id'};

        my $flags = {
            'nopassword'              => 1,
            'allow_truncated_subject' => 1,
        };

        # if the post contains html linebreaks, assume it's preformatted.
        if ( $it->{'text'} =~ /<(?:p|br)\b/i ) {
            $req->{'props'}->{'opt_preformatted'} = 1;
        }

        # If this is a new feed, backdate all but last three items.
        # Note this is a best effort; might not print all three entries
        # if duplicate entries are detected later in the feed.

        $req->{props}->{opt_backdated} = 1
            if $newfeed && ( $itemcount - $newcount ) >= 3;

        # do an editevent if we've seen this item before
        my $id         = $have_ids ? $it->{'id'} : $it->{'link'};
        my $old_itemid = $existing_item{$id};
        if ( $id && $old_itemid ) {
            $newcount--;    # cancel increment above
            $command = "editevent";
            $req->{'itemid'} = $old_itemid;

            # the editevent requires us to resend the date info, which
            # we have to go fetch first, in case the feed doesn't have it

            # TAG:LOG2:synsuck_fetch_itemdates
            unless ($own_time) {
                my $origtime =
                    $udbh->selectrow_array(
                    "SELECT eventtime FROM log2 WHERE " . "journalid=? AND jitemid=?",
                    undef, $su->{'userid'}, $old_itemid );
                $origtime =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)/;
                $req->{'year'} = $1;
                $req->{'mon'}  = $2;
                $req->{'day'}  = $3;
                $req->{'hour'} = $4;
                $req->{'min'}  = $5;
            }
        }

        my $err;
        my $pres = LJ::Protocol::do_request( $command, $req, \$err, $flags );
        unless ( $pres && !$err ) {
            print "  Error: $err\n" if $verbose;
            $errorflag = 1;
        }
    }

    # delete some unneeded synitems.  the limit 1000 is because
    # historically we never deleted and there are accounts with
    # 222,000 items on a myisam table, and that'd be quite the
    # delete hit.
    # the 14 day interval is because if a remote site deleted an
    # entry, it's possible for the oldest item that was previously
    # gone to reappear, and we want to protect against that a
    # little.
    unless ( $LJ::DEBUG{'no_synitem_clean'} || !$mindate ) {
        $dbh->do(
            "DELETE FROM synitem WHERE userid=? AND " . "dateadd < ? - INTERVAL 14 DAY LIMIT 1000",
            undef, $userid, $mindate
        );
    }
    $dbh->do( "UPDATE syndicated SET oldest_ourdate=? WHERE userid=?", undef, $mindate, $userid );

    # bail out if errors, and try again shortly
    if ($errorflag) {
        delay( $userid, 30, "posterror" );
        return;
    }

    # update syndicated account's profile if necessary
    $su->preload_props( "url", "urlname" );
    {
        my $title = $feed->{'title'};
        $title = $su->{'user'} unless LJ::is_utf8($title);
        if ( defined $title && $title ne $su->{'name'} ) {
            $title =~ s/[\n\r]//g;
            $su->update_self( { name => $title } );
            $su->set_prop( "urlname", $title );
        }

        my $link = $feed->{'link'};
        if ( $link && $link ne $su->{'url'} ) {
            $su->set_prop( "url", $link );
        }

        my $bio = $su->bio;
        $su->set_bio( $feed->{'description'} )
            unless $bio && $bio =~ /\[LJ:KEEP\]/;

    }

    my $r_lastmod = LJ::http_to_time( $res->header('Last-Modified') );
    my $r_etag    = $res->header('ETag');

    # decide when to poll next (in minutes).
    # FIXME: this is super bad.  (use hints in RSS file!)
    my $int       = $newcount ? 30                : 60;
    my $status    = $newcount ? "ok"              : "nonew";
    my $updatenew = $newcount ? ", lastnew=NOW()" : "";

    # update reader count while we're changing things, but not
    # if feed is stale (minimize DB work for inactive things)
    if ( $newcount || !defined $readers ) {
        $readers = $su->watched_by_userids;
    }

    # if readers are gone, don't check for a whole day
    $int = 60 * 24 unless $readers;

    $dbh->do(
        "UPDATE syndicated SET fuzzy_token=?, checknext=DATE_ADD(NOW(), INTERVAL ? MINUTE), "
            . "lastcheck=NOW(), lastmod=?, etag=?, laststatus=?, numreaders=? $updatenew "
            . "WHERE userid=?",
        undef,
        $fuzzy_token,
        $int,
        $r_lastmod,
        $r_etag,
        $status,
        $readers,
        $userid
    ) or die $dbh->errstr;
    eval { LJ::Worker::SynSuck->cond_debug("Syndication userid $userid updated w/ new items") };
    return 1;
}

1;
