#!/usr/bin/perl
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

package LJ::Feed;
use strict;

use LJ::Entry;
use XML::Atom::Person;
use XML::Atom::Feed;

my %feedtypes = (
    rss      => { handler => \&create_view_rss,  need_items => 1 },
    atom     => { handler => \&create_view_atom, need_items => 1 },
    userpics => { handler => \&create_view_userpics, },
    comments => { handler => \&create_view_comments, },
);

sub make_feed {
    my ( $r, $u, $remote, $opts ) = @_;

    $opts->{pathextra} =~ s!^/(\w+)!!;
    my $feedtype = $1;
    my $viewfunc = $feedtypes{$feedtype};

    unless ( $viewfunc && LJ::isu($u) ) {
        $opts->{'handler_return'} = 404;
        return undef;
    }

    $r->note( 'codepath' => "feed.$feedtype" ) if $r;

    my $dbr = LJ::get_db_reader();

    my $user = $u->user;

    $u->preload_props(qw/ journaltitle journalsubtitle opt_synlevel /);

    LJ::text_out( \$u->{$_} ) foreach ( "name", "url", "urlname" );

    # opt_synlevel will default to 'cut'
    $u->{opt_synlevel} = 'cut'
        unless $u->{opt_synlevel}
        && $u->{opt_synlevel} =~ /^(?:full|cut|summary|title)$/;

    # some data used throughout the channel
    my $journalinfo = {
        u         => $u,
        link      => $u->journal_base . "/",
        title     => $u->{journaltitle} || $u->name_raw || $u->user,
        subtitle  => $u->{journalsubtitle} || $u->name_raw,
        builddate => LJ::time_to_http( time() ),
    };

    # if we do not want items for this view, just call out
    $opts->{'contenttype'} = 'text/xml; charset=' . $opts->{'saycharset'};
    return $viewfunc->{handler}->( $journalinfo, $u, $opts )
        unless ( $viewfunc->{need_items} );

    # for syndicated accounts, redirect to the syndication URL
    # However, we only want to do this if the data we're returning
    # is similar.
    if ( $u->is_syndicated ) {
        my $synurl =
            $dbr->selectrow_array("SELECT synurl FROM syndicated WHERE userid=$u->{'userid'}");
        unless ($synurl) {
            return 'No syndication URL available.';
        }
        $opts->{'redir'} = $synurl;
        return undef;
    }

    my %FORM = LJ::parse_args( $r->query_string );

    ## load the itemids
    my ( @itemids, @items );

    # for consistency, we call ditemids "itemid" in user-facing settings
    my $ditemid = defined $FORM{itemid} ? $FORM{itemid} + 0 : 0;

    if ($ditemid) {
        my $entry = LJ::Entry->new( $u, ditemid => $ditemid );

        if ( !$entry || !$entry->valid || !$entry->visible_to($remote) ) {
            $opts->{'handler_return'} = 404;
            return undef;
        }

        @itemids = $entry->jitemid;

        push @items,
            {
            itemid      => $entry->jitemid,
            anum        => $entry->anum,
            posterid    => $entry->poster->id,
            security    => $entry->security,
            alldatepart => LJ::alldatepart_s2( $entry->eventtime_mysql ),
            rlogtime    => $LJ::EndOfTime - LJ::mysqldate_to_time( $entry->logtime_mysql, 0 ),
            };
    }
    else {
        @items = $u->recent_items(
            clusterid     => $u->{clusterid},
            clustersource => 'slave',
            remote        => $remote,
            itemshow      => 25,
            order         => 'logtime',
            tagids        => $opts->{tagids},
            tagmode       => $opts->{tagmode},
            itemids       => \@itemids,
            friendsview   => 1,                  # this returns rlogtimes
            dateformat    => 'S2',               # S2 format time format is easier
        );
    }

    $opts->{'contenttype'} = 'text/xml; charset=' . $opts->{'saycharset'};

    ### load the log properties
    my %logprops = ();
    my $logtext;
    my $logdb = LJ::get_cluster_reader($u);
    LJ::load_log_props2( $logdb, $u->{'userid'}, \@itemids, \%logprops );
    $logtext = LJ::get_logtext2( $u, @itemids );

    # set last-modified header, then let apache figure out
    # whether we actually need to send the feed.
    my $lastmod = 0;
    foreach my $item (@items) {

        # revtime of the item.
        my $revtime = $logprops{ $item->{itemid} }->{revtime} || 0;
        $lastmod = $revtime if $revtime > $lastmod;

        # if we don't have a revtime, use the logtime of the item.
        unless ($revtime) {
            my $itime = $LJ::EndOfTime - $item->{rlogtime};
            $lastmod = $itime if $itime > $lastmod;
        }
    }
    $r->set_last_modified($lastmod) if $lastmod;

    # use this $lastmod as the feed's last-modified time
    # we would've liked to use something like
    # LJ::get_timeupdate_multi instead, but that only changes
    # with new updates and doesn't change on edits.
    $journalinfo->{'modtime'} = $lastmod;

    # regarding $r->set_etag:
    # http://perl.apache.org/docs/general/correct_headers/correct_headers.html#Entity_Tags
    # It is strongly recommended that you do not use this method unless you
    # know what you are doing. set_etag() is expecting to be used in
    # conjunction with a static request for a file on disk that has been
    # stat()ed in the course of the current request. It is inappropriate and
    # "dangerous" to use it for dynamic content.

    # verify that our headers are good; especially check to see if we should
    # return a 304 (Not Modified) response.
    if ( ( my $status = $r->meets_conditions ) != $r->OK ) {
        $opts->{handler_return} = $status;
        return undef;
    }

    $journalinfo->{email} = $u->email_for_feeds if $u && $u->email_for_feeds;

    # load tags now that we have no chance of jumping out early
    my $logtags = LJ::Tags::get_logtags( $u, \@itemids );

    my %posteru = ();    # map posterids to u objects
    LJ::load_userids_multiple( [ map { $_->{'posterid'}, \$posteru{ $_->{'posterid'} } } @items ],
        [$u] );

    my @cleanitems;
    my @entries;         # LJ::Entry objects

ENTRY:
    foreach my $it (@items) {

        # load required data
        my $itemid    = $it->{'itemid'};
        my $ditemid   = $itemid * 256 + $it->{'anum'};
        my $entry_obj = LJ::Entry->new( $u, ditemid => $ditemid );

        next ENTRY if $posteru{ $it->{'posterid'} } && $posteru{ $it->{'posterid'} }->is_suspended;
        next ENTRY if $entry_obj && $entry_obj->is_suspended_for($remote);

        if ( $logprops{$itemid}->{'unknown8bit'} ) {
            LJ::item_toutf8(
                $u,
                \$logtext->{$itemid}->[0],
                \$logtext->{$itemid}->[1],
                $logprops{$itemid}
            );
        }

        # see if we have a subject and clean it
        my $subject = $logtext->{$itemid}->[0];
        if ($subject) {
            $subject =~ s/[\r\n]/ /g;
            LJ::CleanHTML::clean_subject_all( \$subject );
        }

        # an HTML link to the entry. used if we truncate or summarize
        my $entry_url = $entry_obj->url;
        my $readmore  = qq{<b>(<a href="$entry_url">Read more ...</a>)</b>};

        # empty string so we don't waste time cleaning an entry that won't be used
        my $event = $u->{'opt_synlevel'} eq 'title' ? '' : $logtext->{$itemid}->[1];

        # clean the event, if non-empty
        if ($event) {

            # users without 'full_rss' get their logtext bodies truncated
            # do this now so that the html cleaner will hopefully fix html we break
            unless ( $u->can_use_full_rss ) {
                my $trunc = LJ::text_trim( $event, 0, 80 );
                $event = "$trunc $readmore" if $trunc ne $event;
            }

            LJ::CleanHTML::clean_event(
                \$event,
                {
                    wordlength       => 0,
                    preformatted     => $logprops{$itemid}->{opt_preformatted},
                    cuturl           => $u->{opt_synlevel} eq 'cut' ? $entry_url : "",
                    to_external_site => 1,
                }
            );

            # do this after clean so we don't have to about know whether or not
            # the event is preformatted
            if ( $u->{'opt_synlevel'} eq 'summary' ) {
                $event = LJ::Entry->summarize( $event, $readmore );
            }

            if ( $u->journaltype eq 'C' && !$opts->{apilinks} ) {
                $event =
                      "Posted by: "
                    . $posteru{ $it->{posterid} }->ljuser_display
                    . "<br /><br />"
                    . $event;
            }

            while ( $event =~ /<(?:lj-)?poll-(\d+)>/g ) {
                my $pollid = $1;

                my $name = LJ::Poll->new($pollid)->name;
                if ($name) {
                    LJ::Poll->clean_poll( \$name );
                }
                else {
                    $name = "#$pollid";
                }

                $event =~
s!<(lj-)?poll-$pollid>!<div><a href="$LJ::SITEROOT/poll/?id=$pollid">View Poll: $name</a></div>!g;
            }

            LJ::EmbedModule->expand_entry( $u, \$event, expand_full => 1 );
        }

        # include comment count image at bottom of event (for readers
        # that don't understand the commentcount)
        $event .= "<br /><br />" . $entry_obj->comment_imgtag . " comments"
            unless $opts->{'apilinks'} || $r->get_args->{no_comment_count};

        my $mood;
        if ( $logprops{$itemid}->{'current_mood'} ) {
            $mood = $logprops{$itemid}->{'current_mood'};
        }
        elsif ( $logprops{$itemid}->{'current_moodid'} ) {
            $mood = DW::Mood->mood_name( $logprops{$itemid}->{'current_moodid'} + 0 );
        }

        my $createtime  = $LJ::EndOfTime - $it->{rlogtime};
        my $can_comment = !defined $logprops{$itemid}->{opt_nocomments}
            || ( $logprops{$itemid}->{opt_nocomments} == 0 );
        my $cleanitem = {
            itemid     => $itemid,
            ditemid    => $ditemid,
            subject    => $subject,
            event      => $event,
            createtime => $createtime,
            eventtime  => $it->{alldatepart}
            ,    # ugly: this is of a different format than the other two times.
            modtime    => $logprops{$itemid}->{revtime} || $createtime,
            comments   => $can_comment,
            music      => $logprops{$itemid}->{'current_music'},
            mood       => $mood,
            tags       => [ values %{ $logtags->{$itemid} || {} } ],
            security   => $it->{security},
            posterid   => $it->{posterid},
            replycount => $logprops{$itemid}->{'replycount'},
            url        => $entry_url,
        };
        push @cleanitems, $cleanitem;
        push @entries,    $entry_obj;
    }

    # fix up the build date to use entry-time
    my $createtime =
          $items[0]->{rlogtime}
        ? $LJ::EndOfTime - $items[0]->{rlogtime}
        : $LJ::EndOfTime;
    $journalinfo->{builddate} = LJ::time_to_http($createtime);

    return $viewfunc->{handler}->( $journalinfo, $u, $opts, \@cleanitems, \@entries );
}

# helper method to add a namespace to the root of a feed
sub _add_feed_namespace {
    my ( $feed, $ns_prefix, $namespace ) = @_;
    my $doc = $feed->elem->ownerDocument->getDocumentElement;
    $doc->setAttribute( "xmlns:$ns_prefix", $namespace );
}

# helper method for create_view_rss and create_view_comments
sub _init_talkview {
    my ( $journalinfo, $u, $opts, $talkview ) = @_;
    my $bot_director = LJ::Hooks::run_hook( "bot_director", "<!-- ", " -->" ) || '';
    my $ret;

    # header
    $ret .= "<?xml version='1.0' encoding='$opts->{'saycharset'}' ?>\n";
    $ret .= "$bot_director\n";
    $ret .= "<rss version='2.0' xmlns:lj='http://www.livejournal.org/rss/lj/1.0/' "
        . "xmlns:atom10='http://www.w3.org/2005/Atom'>\n";

    # channel attributes
    my $desc = {
        rss      => LJ::exml("$journalinfo->{title} - $LJ::SITENAME"),
        comments => "Latest comments in " . LJ::exml( $journalinfo->{title} )
    };

    $ret .= "<channel>\n";
    $ret .= "  <title>" . LJ::exml( $journalinfo->{title} ) . "</title>\n";
    $ret .= "  <link>$journalinfo->{link}</link>\n";
    $ret .= "  <description>" . $desc->{$talkview} . "</description>\n";
    $ret .= "  <managingEditor>" . LJ::exml( $journalinfo->{email} ) . "</managingEditor>\n"
        if $journalinfo->{email};
    $ret .= "  <lastBuildDate>$journalinfo->{builddate}</lastBuildDate>\n";
    $ret .= "  <generator>LiveJournal / $LJ::SITENAME</generator>\n";
    $ret .= "  <lj:journal>" . $u->user . "</lj:journal>\n";
    $ret .= "  <lj:journaltype>" . $u->journaltype_readable . "</lj:journaltype>\n";

    # TODO: add 'language' field when user.lang has more useful information

    ### image block, returns info for their current userpic
    if ( $u->{'defaultpicid'} ) {
        my $icon = $u->userpic;
        my $url  = $icon->url;
        my ( $width, $height ) = $icon->dimensions;

        $ret .= "  <image>\n";
        $ret .= "    <url>$url</url>\n";
        $ret .= "    <title>" . LJ::exml( $journalinfo->{title} ) . "</title>\n";
        $ret .= "    <link>$journalinfo->{link}</link>\n";
        $ret .= "    <width>$width</width>\n";
        $ret .= "    <height>$height</height>\n";
        $ret .= "  </image>\n\n";
    }

    return $ret;
}

sub create_view_rss {
    my ( $journalinfo, $u, $opts, $cleanitems ) = @_;

    my $ret = _init_talkview( $journalinfo, $u, $opts, 'rss' );

    my %posteru = ();    # map posterids to u objects
    LJ::load_userids_multiple(
        [ map { $_->{'posterid'}, \$posteru{ $_->{'posterid'} } } @$cleanitems ], [$u] );

    # output individual item blocks

    foreach my $it (@$cleanitems) {
        my $itemid  = $it->{itemid};
        my $ditemid = $it->{ditemid};
        my $poster  = $posteru{ $it->{posterid} };

        $ret .= "<item>\n";

        # use the $ditemid form so it doesn't change
        $ret .= "  <guid isPermaLink='true'>$journalinfo->{link}$ditemid.html</guid>\n";
        $ret .= "  <pubDate>" . LJ::time_to_http( $it->{createtime} ) . "</pubDate>\n";
        $ret .= "  <title>" . LJ::exml( $it->{subject} ) . "</title>\n" if $it->{subject};
        $ret .= "  <author>" . LJ::exml( $journalinfo->{email} ) . "</author>"
            if $journalinfo->{email};
        $ret .= "  <link>$it->{url}</link>\n";

        # omit the description tag if we're only syndicating titles
        #   note: the $event was also emptied earlier, in make_feed
        unless ( $u->{'opt_synlevel'} eq 'title' ) {
            $ret .= "  <description>" . LJ::exml( $it->{event} ) . "</description>\n";
        }
        if ( $it->{comments} ) {
            $ret .= "  <comments>$it->{url}</comments>\n";
        }
        $ret .= "  <category>$_</category>\n" foreach map { LJ::exml($_) } @{ $it->{tags} || [] };

        # TODO: add author field with posterid's email address, respect communities
        $ret .= "  <lj:music>" . LJ::exml( $it->{music} ) . "</lj:music>\n" if $it->{music};
        $ret .= "  <lj:mood>" . LJ::exml( $it->{mood} ) . "</lj:mood>\n"    if $it->{mood};
        $ret .= "  <lj:security>" . LJ::exml( $it->{security} ) . "</lj:security>\n"
            if $it->{security};
        $ret .= "  <lj:poster>" . LJ::exml( $poster->user ) . "</lj:poster>\n"
            unless $u->equals($poster);
        $ret .= "  <lj:reply-count>$it->{replycount}</lj:reply-count>\n";
        $ret .= "</item>\n";
    }

    $ret .= "</channel>\n";
    $ret .= "</rss>\n";

    return $ret;
}

# the creator for the Atom view
# keys of $opts:
# single_entry - only output an <entry>..</entry> block. off by default
# apilinks - output AtomAPI links for posting a new entry or
#            getting/editing/deleting an existing one. off by default
sub create_view_atom {
    my ( $j, $u, $opts, $cleanitems, $entrylist ) = @_;
    my ( $feed, $xml, $ns, $site_ns_prefix );

    $site_ns_prefix = lc $LJ::SITENAMEABBREV;
    $ns             = "http://www.w3.org/2005/Atom";

    # AtomAPI interface path
    my $api =
          $opts->{'apilinks'}
        ? $u->atom_service_document
        : $u->journal_base . "/data/atom";

    my $make_link = sub {
        my ( $rel, $type, $href, $title ) = @_;
        my $link = XML::Atom::Link->new( Version => 1 );
        $link->rel($rel);
        $link->type($type) if $type;
        $link->href($href);
        $link->title($title) if $title;
        return $link;
    };

    my $author   = XML::Atom::Person->new( Version => 1 );
    my $journalu = $j->{u};
    $author->email( $journalu->email_for_feeds ) if $journalu && $journalu->email_for_feeds;
    $author->name( $u->{'name'} );

    # feed information
    unless ( $opts->{'single_entry'} ) {
        $feed = XML::Atom::Feed->new( Version => 1 );
        $xml  = $feed->elem->ownerDocument;
        my $bot_director = LJ::Hooks::run_hook("bot_director") || '';

        if ( $u->should_block_robots ) {
            _add_feed_namespace( $feed, "idx", "urn:atom-extension:indexing" );
            $xml->getDocumentElement->setAttribute( "idx:index", "no" );
        }

        $xml->insertBefore( $xml->createComment($bot_director), $xml->documentElement() );

        # attributes
        $feed->id( $u->atomid );
        $feed->title( $j->{'title'} || $u->{user} );
        if ( $j->{'subtitle'} ) {
            $feed->subtitle( $j->{'subtitle'} );
        }

        $feed->author($author);
        $feed->add_link( $make_link->( 'alternate', 'text/html', $j->{'link'} ) );
        $feed->add_link(
            $make_link->(
                'self',
                $opts->{'apilinks'}
                ? ( 'application/atom+xml', "$api/entries" )
                : ( 'text/xml', $api )
            )
        );
        $feed->updated( LJ::time_to_w3c( $j->{'modtime'}, 'Z' ) );

        my $ljinfo = $xml->createElement("$site_ns_prefix:journal");
        $ljinfo->setAttribute( 'username', LJ::exml( $u->user ) );
        $ljinfo->setAttribute( 'type',     LJ::exml( $u->journaltype_readable ) );
        $xml->getDocumentElement->appendChild($ljinfo);
    }

    my $posteru = LJ::load_userids( map { $_->{posterid} } @$cleanitems );

    # output individual item blocks
    # FIXME: use LJ::Entry->atom_entry?
    foreach my $it (@$cleanitems) {
        my $itemid  = $it->{itemid};
        my $ditemid = $it->{ditemid};
        my $poster  = $posteru->{ $it->{posterid} };

        my $entry     = XML::Atom::Entry->new( Version => 1 );
        my $entry_xml = $entry->elem->ownerDocument;

        $entry->id( $u->atomid . ":$ditemid" );

        # author isn't required if it is in the main <feed>
        # only add author if we are in a single entry view, or
        # the journal entry isn't owned by the journal. (communities)
        if ( $opts->{single_entry} || !$journalu->equals($poster) ) {
            my $author = XML::Atom::Person->new( Version => 1 );
            $author->email( $poster->email_visible ) if $poster && $poster->email_visible;
            $author->name( $poster->{name} );
            $entry->author($author);

            # and the lj-specific stuff
            my $postauthor = $entry_xml->createElement("$site_ns_prefix:poster");
            $postauthor->setAttribute( 'user', LJ::exml( $poster->user ) );
            $entry_xml->getDocumentElement->appendChild($postauthor);
        }

        $entry->add_link( $make_link->( 'alternate', 'text/html', "$j->{'link'}$ditemid.html" ) );
        $entry->add_link( $make_link->( 'self',      'text/xml',  "$api/?itemid=$ditemid" ) );

        $entry->add_link(
            $make_link->(
                'edit', 'application/atom+xml', "$api/entries/$itemid", 'Edit this post'
            )
        ) if $opts->{'apilinks'};

        my ( $year, $mon, $mday, $hour, $min, $sec ) = split( / /, $it->{eventtime} );
        my $event_date =
            sprintf( "%04d-%02d-%02dT%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec );

        # title can't be blank and can't be absent, so we have to fake some subject
        $entry->title( $it->{'subject'} || "$journalu->{user} \@ $event_date" );

        $entry->published( LJ::time_to_w3c( $it->{createtime}, "Z" ) );
        $entry->updated( LJ::time_to_w3c( $it->{modtime}, "Z" ) );

        foreach my $tag ( @{ $it->{tags} || [] } ) {
            my $category = XML::Atom::Category->new( Version => 1 );
            $category->term($tag);
            $entry->add_category($category);
        }

        my @currents = (
            [ 'music'       => $it->{music} ],
            [ 'mood'        => $it->{mood} ],
            [ 'security'    => $it->{security} ],
            [ 'reply-count' => $it->{replycount} ],
        );

        foreach (@currents) {
            my ( $key, $val ) = @$_;
            if ( defined $val ) {
                my $elem = $entry_xml->createElement("$site_ns_prefix:$key");
                $elem->appendTextNode($val);
                $entry_xml->getDocumentElement->appendChild($elem);
            }
        }

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
        my $make_content = sub {
            my $content = $entry_xml->createElement( $_[0] );
            $content->setAttribute( 'type', 'html' );
            $content->setNamespace($ns);
            $content->appendTextNode( $it->{'event'} );
            $entry_xml->getDocumentElement->appendChild($content);
        };
        if ( $u->{'opt_synlevel'} eq 'full' || $u->{'opt_synlevel'} eq 'cut' ) {

            # Do this manually for now, until XML::Atom supports new
            # content type classifications.
            $make_content->('content');
        }
        elsif ( $u->{'opt_synlevel'} eq 'summary' ) {
            $make_content->('summary');
        }

        if ( $opts->{'single_entry'} ) {
            _add_feed_namespace( $entry, $site_ns_prefix, $LJ::SITEROOT );
            return $entry->as_xml;
        }
        else {
            $feed->add_entry($entry);
        }
    }

    _add_feed_namespace( $feed, $site_ns_prefix, $LJ::SITEROOT );
    return $feed->as_xml;
}

# create a userpic page for a user
sub create_view_userpics {
    my ( $journalinfo, $u, $opts ) = @_;
    my ( $feed, $xml, $ns );

    $ns = "http://www.w3.org/2005/Atom";

    my $make_link = sub {
        my ( $rel, $type, $href, $title ) = @_;
        my $link = XML::Atom::Link->new( Version => 1 );
        $link->rel($rel);
        $link->type($type);
        $link->href($href);
        $link->title($title) if $title;
        return $link;
    };

    my $author = XML::Atom::Person->new( Version => 1 );
    $author->name( $u->{name} );

    $feed = XML::Atom::Feed->new( Version => 1 );
    $xml  = $feed->elem->ownerDocument;

    if ( $u->should_block_robots ) {
        _add_feed_namespace( $feed, "idx", "urn:atom-extension:indexing" );
        $xml->getDocumentElement->setAttribute( "idx:index", "no" );
    }

    my $bot = LJ::Hooks::run_hook("bot_director");
    $xml->insertBefore( $xml->createComment($bot), $xml->documentElement() )
        if $bot;

    $feed->id( $u->atomid . ":userpics" );
    $feed->title("$u->{user}'s userpics");

    $feed->author($author);
    $feed->add_link( $make_link->( 'alternate', 'text/html', $u->allpics_base ) );
    $feed->add_link( $make_link->( 'self', 'text/xml', $u->journal_base() . "/data/userpics" ) );

    # now start building all the userpic data
    # start up by loading all of our userpic information and creating that part of the feed
    my $info =
        $u->get_userpic_info( { load_comments => 1, load_urls => 1, load_descriptions => 1 } );

    my %keywords = ();
    while ( my ( $kw, $pic ) = each %{ $info->{kw} } ) {
        LJ::text_out( \$kw );
        push @{ $keywords{ $pic->{picid} } }, LJ::exml($kw);
    }

    my %comments = ();
    while ( my ( $pic, $comment ) = each %{ $info->{comment} } ) {
        LJ::text_out( \$comment );
        $comments{$pic} = LJ::strip_html($comment);
    }

    my %descriptions = ();
    while ( my ( $pic, $description ) = each %{ $info->{description} } ) {
        LJ::text_out( \$description );
        $descriptions{$pic} = LJ::strip_html($description);
    }

    my @pics = map { $info->{pic}->{$_} } sort { $a <=> $b }
        grep { $info->{pic}->{$_}->{state} eq 'N' }
        keys %{ $info->{pic} };

    # FIXME: It sucks that there are two different methods for aggregating
    #        the information for a user's set of icons, one of which doesn't
    #        include keywords and the other of which doesn't include pictime.
    #        But hey, at least they both use caching.

    my %pictimes = map { $_->picid => $_->pictime } LJ::Userpic->load_user_userpics($u);

    my $latest = 0;
    foreach my $pictime ( values %pictimes ) {
        $latest = ( $latest < $pictime ) ? $pictime : $latest;
    }

    $feed->updated( LJ::time_to_w3c( $latest, 'Z' ) );

    foreach my $pic (@pics) {
        my $entry     = XML::Atom::Entry->new( Version => 1 );
        my $entry_xml = $entry->elem->ownerDocument;

        $entry->id( $u->atomid . ":userpics:$pic->{picid}" );

        my $title = ( $pic->{picid} == $u->{defaultpicid} ) ? "default userpic" : "userpic";
        $entry->title($title);

        $entry->updated( LJ::time_to_w3c( $pictimes{ $pic->{picid} }, 'Z' ) );

        my $content;
        $content = $entry_xml->createElement("content");
        $content->setAttribute( 'src', "$LJ::USERPIC_ROOT/$pic->{picid}/$u->{userid}" );
        $content->setNamespace($ns);
        $entry_xml->getDocumentElement->appendChild($content);

        foreach my $kw ( @{ $keywords{ $pic->{picid} } } ) {
            my $category = $entry_xml->createElement('category');
            $category->setAttribute( 'term', $kw );
            $category->setNamespace($ns);
            $entry_xml->getDocumentElement->appendChild($category);
        }

        if ( $descriptions{ $pic->{picid} } ) {
            my $content = $entry_xml->createElement('title');
            $content->setNamespace($ns);
            $content->appendTextNode( $descriptions{ $pic->{picid} } );
            $entry_xml->getDocumentElement->appendChild($content);
        }

        if ( $comments{ $pic->{picid} } ) {
            my $content = $entry_xml->createElement("summary");
            $content->setNamespace($ns);
            $content->appendTextNode( $comments{ $pic->{picid} } );
            $entry_xml->getDocumentElement->appendChild($content);
        }

        $feed->add_entry($entry);
    }

    return $feed->as_xml;
}

sub create_view_comments {
    my ( $journalinfo, $u, $opts ) = @_;

    unless ( LJ::is_enabled( 'latest_comments_rss', $u ) ) {
        $opts->{handler_return} = 404;
        return 404;
    }

    unless ( $u->can_use_latest_comments_rss ) {
        $opts->{handler_return} = 403;
        return;
    }

    my $ret = _init_talkview( $journalinfo, $u, $opts, 'comments' );

    my @comments = $u->get_recent_talkitems(25);
    foreach my $r (@comments) {
        my $c          = LJ::Comment->new( $u, jtalkid => $r->{jtalkid} );
        my $thread_url = $c->thread_url;
        my $subject    = $c->subject_raw;
        LJ::CleanHTML::clean_subject_all( \$subject );

        $ret .= "<item>\n";
        $ret .= "  <guid isPermaLink='true'>$thread_url</guid>\n";
        $ret .= "  <pubDate>" . LJ::time_to_http( $r->{datepostunix} ) . "</pubDate>\n";
        $ret .= "  <title>" . LJ::exml($subject) . "</title>\n" if $subject;
        $ret .= "  <link>$thread_url</link>\n";

        # omit the description tag if we're only syndicating titles
        unless ( $u->{'opt_synlevel'} eq 'title' ) {
            my $body = $c->body_raw;
            LJ::CleanHTML::clean_subject_all( \$body );
            $ret .= "  <description>" . LJ::exml($body) . "</description>\n";
        }
        $ret .= "</item>\n";
    }

    $ret .= "</channel>\n";
    $ret .= "</rss>\n";

    return $ret;
}

# refactored from feeds/index

sub synrow_select {
    my %opts = @_;    # a single key => val pair
    my ( $q, $x );    # what we're looking for

    my %optcols = (
        url    => 's.synurl',
        userid => 's.userid',
        user   => 'u.user',
    );

    foreach my $k ( keys %optcols ) {
        if ( exists $opts{$k} ) {
            $x = $opts{$k};       # the data passed in
            $q = $optcols{$k};    # the relevant DB column
            last;
        }
    }

    die 'LJ::Feed::synrow_select called with invalid arguments' unless $q;

    my $dbr = LJ::get_db_reader() or die "No DB";
    return $dbr->selectrow_hashref(
        "SELECT u.user, s.* FROM syndicated s, useridmap u " . "WHERE u.userid=s.userid AND $q=?",
        undef, $x );
}

# code merged in from LJ::Syn module

sub get_popular_feeds {
    my $popsyn = LJ::MemCache::get("popsyn");
    unless ($popsyn) {
        $popsyn = _get_feeds_from_db();

        # load u objects so we can get usernames
        my %users;
        LJ::load_userids_multiple( [ map { $_, \$users{$_} } map { $_->[0] } @$popsyn ] );
        unshift @$_, $users{ $_->[0] }->{'user'}, $users{ $_->[0] }->{'name'} foreach @$popsyn;

        # format is: [ user, name, userid, synurl, numreaders ]
        # set in memcache
        my $expire = time() + 3600;    # 1 hour
        LJ::MemCache::set( "popsyn", $popsyn, $expire );
    }
    return $popsyn;
}

sub get_popular_feed_ids {
    my $popsyn_ids = LJ::MemCache::get("popsyn_ids");
    unless ($popsyn_ids) {
        my $popsyn = _get_feeds_from_db();
        @$popsyn_ids = map { $_->[0] } @$popsyn;

        # set in memcache
        my $expire = time() + 3600;    # 1 hour
        LJ::MemCache::set( "popsyn_ids", $popsyn_ids, $expire );
    }
    return $popsyn_ids;
}

sub _get_feeds_from_db {
    my $popsyn = [];

    my $dbr = LJ::get_db_reader();
    my $sth =
        $dbr->prepare( "SELECT userid, synurl, numreaders FROM syndicated "
            . "WHERE numreaders > 0 "
            . "AND lastnew > DATE_SUB(NOW(), INTERVAL 14 DAY) "
            . "ORDER BY numreaders DESC LIMIT 1000" );
    $sth->execute();
    while ( my @row = $sth->fetchrow_array ) {
        push @$popsyn, [@row];
    }

    return $popsyn;
}

=head2 C<< LJ::Feed::merge( %opts ) >>

=over

=item Opts:

=over

=item from - Merge from: LJ::User or userid

=item from_name - Merge from username

=item to - Merge to LJ::User or userid

=item to_name - Merge to username

=item url - Merge to URL

=item pretend - Do not actually merge

=back

=back

=cut

sub merge_feed {
    my %args = @_;
    my $from_u;
    if ( $args{from_name} ) {
        $from_u = LJ::load_user( $args{from_name} )
            or return ( 0, "Invalid user: '" . $args{from_name} . "'." );
    }
    else {
        $from_u = LJ::want_user( $args{from} )
            or return ( 0, "Invalid from user." );
    }

    my $to_u;
    if ( $args{to_name} ) {
        $to_u = LJ::load_user( $args{to_name} )
            or return ( 0, "Invalid user: '" . $args{to_name} . "'." );
    }
    else {
        $to_u = LJ::want_user( $args{to} )
            or return ( 0, "Invalid to user." );
    }

    return ( 0, "Trying to merge into yourself." )
        if $from_u->equals($to_u);

    # we don't want to unlimit this, so reject if we have too many users
    my @ids = $from_u->watched_by_userids( limit => $LJ::MAX_WT_EDGES_LOAD + 1 );
    return ( 0,
              "Unable to merge feeds. Too many users are watching the feed '"
            . $from_u->user
            . "'. We only allow merges for feeds with at most $LJ::MAX_WT_EDGES_LOAD watchers." )
        if scalar @ids > $LJ::MAX_WT_EDGES_LOAD;

    foreach ( $to_u, $from_u ) {
        return ( 0,
                  "Invalid user: '"
                . $_->user
                . "' (statusvis is "
                . $_->statusvis
                . ", already merged?)" )
            unless $_->is_visible;

        return ( 0, $_->user . " is not a syndicated account." )
            unless $_->is_syndicated;
    }

    my $url = LJ::CleanHTML::canonical_url( $args{url} )
        or return ( 0, "Invalid URL." );

    return ( 1, "Everything seems okay" ) if $args{pretend};

    my $dbh = LJ::get_db_writer();
    my $from_oldurl =
        $dbh->selectrow_array( "SELECT synurl FROM syndicated WHERE userid=?", undef, $from_u->id );
    my $to_oldurl =
        $dbh->selectrow_array( "SELECT synurl FROM syndicated WHERE userid=?", undef, $to_u->id );

    # 1) set up redirection for 'from_user' -> 'to_user'
    $from_u->update_self( { journaltype => 'R', statusvis => 'R' } );
    $from_u->set_prop( "renamedto", $to_u->user )
        or return ( 0, "Unable to set userprop.  Database unavailable?" );

    # 2) delete the row in the syndicated table for the user
    #    that is now renamed
    $dbh->do( "DELETE FROM syndicated WHERE userid=?", undef, $from_u->id );
    return ( 0, "Database Error: " . $dbh->errstr )
        if $dbh->err;

    # 3) update the url of the destination syndicated account and
    #    tell it to check it now
    $dbh->do( "UPDATE syndicated SET synurl=?, checknext=NOW() WHERE userid=?",
        undef, $url, $to_u->id );
    return ( 0, "Database Error: " . $dbh->errstr )
        if $dbh->err;

    # 4) make users who watch 'from_user' now watch 'to_user'
    # we can't just use delete_ and add_ edges, because we would lose
    # custom group and colors data
    if (@ids) {

        # update ignore so we don't raise duplicate key errors
        $dbh->do( 'UPDATE IGNORE wt_edges SET to_userid=? WHERE to_userid=?',
            undef, $to_u->id, $from_u->id );
        return ( 0, "Database Error: " . $dbh->errstr )
            if $dbh->err;

        # in the event that some rows in the update above caused a duplicate key error,
        # we can delete the rows that weren't updated, since they don't need to be
        # processed anyway
        $dbh->do( "DELETE FROM wt_edges WHERE to_userid=?", undef, $from_u->id );
        return ( 0, "Database Error: " . $dbh->errstr )
            if $dbh->err;

        # clear memcache keys
        foreach my $id (@ids) {
            LJ::memcache_kill( $id, 'wt_edges' );
            LJ::memcache_kill( $id, 'wt_list' );
            LJ::memcache_kill( $id, 'watched' );
        }

        LJ::memcache_kill( $from_u->id, 'wt_edges_rev' );
        LJ::memcache_kill( $from_u->id, 'watched_by' );

        LJ::memcache_kill( $to_u->id, 'wt_edges_rev' );
        LJ::memcache_kill( $to_u->id, 'watched_by' );
    }

    # log to statushistory
    my $remote = LJ::get_remote();
    my $msg    = "Merged " . $from_u->user . " to " . $to_u->user . " using URL: $url.";
    LJ::statushistory_add( $from_u, $remote, 'synd_merge', $msg . " Old URL was $from_oldurl." );
    LJ::statushistory_add( $to_u,   $remote, 'synd_merge', $msg . " Old URL was $to_oldurl." );

    return ( 1, $msg );
}

1;
