#!/usr/bin/perl
#
# DW::Controller::Export
#
# Pages for exporting journal content.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2015-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Export;

use v5.10;
use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::FormErrors;

use bytes ();
use DW::Logic::AdultContent;
use DW::Mood;
use LJ::Comment;
use LJ::Time;
use Time::Local qw( timegm );
use Unicode::MapUTF8;

use constant POSTED_COMMENTS_LIMIT => 500;
use constant POSTED_COMMENTS_BYTES => 8 * 1024 * 1024;
use constant POSTED_COMMENTS_BATCH => 25;

DW::Routing->register_string( '/export',    \&index_handler, app => 1 );
DW::Routing->register_string( '/export_do', \&post_handler,  app => 1 );

DW::Routing->register_string( '/export_comments',        \&comment_handler,         app => 1 );
DW::Routing->register_string( '/export_posted_comments', \&posted_comments_handler, app => 1 );

sub get_encodings {
    my ( %encodings, %encnames );
    LJ::load_codes( { "encoding" => \%encodings } );
    LJ::load_codes( { "encname"  => \%encnames } );

    my $rv = {};
    foreach my $id ( keys %encodings ) {
        next if lc $encodings{$id} eq 'none';
        $rv->{ $encodings{$id} } = $encnames{$id};
    }
    return $rv;
}

sub index_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my @enclist;
    my %e = %{ get_encodings() };
    push @enclist, ( $_ => $e{$_} ) foreach sort { $e{$a} cmp $e{$b} } keys %e;

    $rv->{encodings}            = \@enclist;
    $rv->{show_posted_comments} = $rv->{u}->equals( $rv->{remote} );

    return DW::Template->render_template( 'export/index.tt', $rv );
}

sub post_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $post   = $r->post_args;
    my $scope  = '/export/index.tt';
    my $errors = DW::FormErrors->new;

    return error_ml('bml.requirepost') unless $r->did_post;

    my $u    = $rv->{u};
    my $dbcr = LJ::get_cluster_reader($u);
    return error_ml('error.nodb') unless $dbcr;

    my $ok_formats = { csv => 'csv', xml => 'xml' };
    my $format     = $ok_formats->{ lc $post->{format} };
    $errors->add( '', "$scope.error.format" ) unless $format;

    my $encoding;

    {
        if ( $post->{encid} ) {
            my %encodings;
            LJ::load_codes( { "encoding" => \%encodings } );
            $encoding = $encodings{ $post->{encid} };
        }

        $encoding ||= $post->{encoding};
        $encoding ||= 'utf-8';

        if ( lc($encoding) ne "utf-8"
            && !Unicode::MapUTF8::utf8_supported_charset($encoding) )
        {
            $errors->add( '', "$scope.error.encoding" );
        }
    }

    return DW::Template->render_template( 'error.tt',
        { errors => $errors, message => LJ::Lang::ml('bml.badcontent.body') } )
        if $errors->exist;

    ##### figure out what fields we're exporting

    my @fields;
    my $opts = { format => $format };    # information needed by printing routines

    foreach my $f (qw(itemid eventtime logtime subject event security allowmask)) {
        push @fields, $f if $post->{"field_${f}"};
    }

    if ( $post->{field_currents} ) {
        push @fields, ( "current_music", "current_mood" );
        $opts->{currents} = 1;
    }

    my $year  = $post->{year}  ? $post->{year} + 0  : 0;
    my $month = $post->{month} ? $post->{month} + 0 : 0;

    my $sth =
        $dbcr->prepare(
              "SELECT jitemid, anum, eventtime, logtime, security, allowmask FROM log2 "
            . "WHERE journalid=? AND year=? AND month=?" );
    $sth->execute( $u->id, $year, $month );

    return DW::Template->render_template( 'error.tt', { message => $dbcr->errstr } )
        if $dbcr->err;

    #### do file-format specific initialization

    if ( $format eq "csv" ) {
        $r->content_type("text/plain");
        my $filename = sprintf( "%s-%04d-%02d.csv", $u->user, $year, $month );
        $r->header_out_add( 'Content-Disposition' => "attachment; filename=$filename" );
        $r->print( join( ",", @fields ) . "\n" ) if $post->{csv_header};
    }

    if ( $format eq "xml" ) {
        my $lenc = lc $encoding;
        $r->content_type("text/xml; charset=$lenc");
        $r->print(qq{<?xml version="1.0" encoding='$lenc'?>\n});
        $r->print("<livejournal>\n");
    }

    $opts->{fields}        = \@fields;
    $opts->{encoding}      = $encoding;
    $opts->{notranslation} = 1 if $post->{notranslation};

    my @buffer;

    while ( my $i = $sth->fetchrow_hashref ) {
        $i->{'ritemid'} = $i->{'jitemid'} || $i->{'itemid'};
        $i->{'itemid'}  = $i->{'jitemid'} * 256 + $i->{'anum'} if $i->{'jitemid'};
        push @buffer, $i;

        # process 20 entries at a time

        if ( scalar @buffer == 20 ) {
            $r->print($_) foreach @{ _load_buffer( $u, \@buffer, $dbcr, $opts ) };
            @buffer = ();
        }

    }

    $r->print($_) foreach @{ _load_buffer( $u, \@buffer, $dbcr, $opts ) };

    $r->print("</livejournal>\n") if $format eq "xml";

    return $r->OK;
}

sub _load_buffer {
    my ( $u, $buf, $dbcr, $opts ) = @_;
    my %props;

    my @ids = map { $_->{ritemid} } @{$buf};
    my $lt  = LJ::get_logtext2( $u, @ids );
    LJ::load_log_props2( $dbcr, $u->id, \@ids, \%props );

    my @result;

    foreach my $e ( @{$buf} ) {
        $e->{'subject'} = $lt->{ $e->{'ritemid'} }->[0];
        $e->{'event'}   = $lt->{ $e->{'ritemid'} }->[1];

        my $eprops = $props{ $e->{'ritemid'} };

        # convert to UTF-8 if necessary
        if ( $eprops->{'unknown8bit'} && !$opts->{'notranslation'} ) {
            my $error;
            $e->{'subject'} = LJ::text_convert( $e->{'subject'}, $u, \$error );
            $e->{'event'}   = LJ::text_convert( $e->{'event'},   $u, \$error );
            foreach ( keys %{$eprops} ) {
                $eprops->{$_} = LJ::text_convert( $eprops->{$_}, $u, \$error );
            }
        }

        if ( $opts->{'currents'} ) {
            $e->{'current_music'} = $eprops->{'current_music'};
            $e->{'current_mood'}  = $eprops->{'current_mood'};
            if ( $eprops->{current_moodid} ) {
                my $mood = DW::Mood->mood_name( $eprops->{current_moodid} );
                $e->{current_mood} = $mood if $mood;
            }
        }

        my $entry = _dump_entry( $e, $opts );

        # now translate this to the chosen encoding but only if this is a
        # Unicode environment. In a pre-Unicode environment the chosen encoding
        # is merely a label.

        if ( lc( $opts->{'encoding'} ) ne 'utf-8' && !$opts->{'notranslation'} ) {
            $entry = Unicode::MapUTF8::from_utf8(
                {
                    -string  => $entry,
                    -charset => $opts->{'encoding'}
                }
            );
        }

        push @result, $entry;
    }

    return \@result;
}

sub _dump_entry {
    my ( $e, $opts ) = @_;

    my $format = $opts->{format};
    my $record = $opts->{record} // 'entry';
    my $entry  = "";
    my @vals   = ();

    if ( $format eq "xml" ) {
        $entry .= "<$record>\n";
    }

    foreach my $f ( @{ $opts->{fields} } ) {
        my $v = $e->{$f} // '';
        if ( $format eq "csv" ) {
            if ( $v =~ /["\r\n,]/ ) {
                $v =~ s/\"/\"\"/g;
                $v = qq{"$v"};
            }
        }
        if ( $format eq "xml" ) {
            $v = LJ::exml($v);
        }
        push @vals, $v;
    }

    if ( $format eq "csv" ) {
        $entry .= join( ",", @vals ) . "\n";
    }

    if ( $format eq "xml" ) {
        foreach my $f ( @{ $opts->{fields} } ) {
            my $v = shift @vals;
            $entry .= "<$f>" . $v . "</$f>\n";
        }
        $entry .= "</$record>\n";
    }

    return $entry;
}

sub posted_comments_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    return error_ml('bml.requirepost') unless $r->did_post;

    my $post   = $r->post_args;
    my $format = lc( $post->{format} // '' );
    return error_ml('/export/index.tt.error.format') unless $format eq 'csv' || $format eq 'xml';

    my $year  = $post->{year}  // '';
    my $month = $post->{month} // '';
    my $day   = $post->{day}   // '';
    return error_ml('/export/index.tt.error.posted_date')
        unless $year =~ /\A[0-9]{4}\z/ && $year >= 1970 && $month =~ /\A(?:0?[1-9]|1[0-2])\z/;
    my $start = timegm( 0, 0, 0, 1, $month - 1,  $year );
    my $end   = timegm( 0, 0, 0, 1, $month % 12, $year + ( $month == 12 ) );
    if ( length $day ) {
        return error_ml('/export/index.tt.error.posted_day')
            unless $day =~ /\A[0-9]{1,2}\z/ && $day >= 1 && $day <= ( $end - $start ) / 86400;
        $start += ( $day - 1 ) * 86400;
        $end = $start + 86400;
    }

    my $author = $rv->{remote};
    my $limit  = POSTED_COMMENTS_LIMIT + 1;
    my $dbcr   = LJ::get_cluster_reader($author);
    return _posted_comments_unavailable($r) unless $dbcr;
    my $rows = $dbcr->selectall_arrayref(
        "SELECT journalid, nodeid, jtalkid, posttime, nodetype FROM talkleft "
            . "WHERE userid=? AND posttime>=? AND posttime<? LIMIT $limit",
        undef, $author->id, $start, $end
    );
    return _posted_comments_unavailable($r) if !$rows || $dbcr->err;
    return _posted_comments_too_large( $r, $day ) if @$rows > POSTED_COMMENTS_LIMIT;

    my @fields = qw(journal permalink datetime subject body icon_keyword);
    my $opts   = { format => $format, fields => \@fields, record => 'comment' };
    my $prefix =
        $format eq 'csv'
        ? join( ',', @fields ) . "\n"
        : qq{<?xml version="1.0" encoding="UTF-8"?>\n<comments>\n};
    my $suffix = $format eq 'xml' ? "</comments>\n" : '';
    my @output = ($prefix);
    my $size   = bytes::length($prefix) + bytes::length($suffix);

    my @ordered = sort { $a->[3] <=> $b->[3] || $a->[0] <=> $b->[0] || $a->[2] <=> $b->[2] } @$rows;
    my %journal_ids = map { $_->[0] => 1 } @ordered;
    my $journals    = LJ::load_userids( keys %journal_ids );
    my $is_minor    = $author->is_minor;
    my %seen;
    while (@ordered) {
        my @batch = splice @ordered, 0, POSTED_COMMENTS_BATCH;
        my @candidates;
        foreach my $row (@batch) {
            next unless $row->[4] eq 'L';
            my ( $journalid, $nodeid, $jtalkid ) = @$row;
            my $journal = $journals->{$journalid} or next;
            push @candidates, [ $nodeid, LJ::Comment->new( $journal, jtalkid => $jtalkid ) ];
        }
        LJ::Comment->preload_rows;

        my ( @eligible, %by_journal );
        foreach my $candidate (@candidates) {
            my ( $nodeid, $comment ) = @$candidate;
            next unless $comment->valid && $comment->posterid == $author->id;
            next unless $comment->nodetype eq 'L' && $comment->nodeid == $nodeid;
            next if $comment->is_deleted || !$comment->visible_to($author);
            next if $seen{ $comment->singletonkey }++;
            if ($is_minor) {
                my $restriction = DW::Logic::AdultContent->interstitial_type(
                    user    => $author,
                    journal => $comment->journal,
                    entry   => $comment->entry,
                );
                next if ( $restriction // '' ) eq 'explicit_blocked';
            }
            push @eligible, $comment;
            push @{ $by_journal{ $comment->journalid } }, $comment;
        }

        my %text;
        foreach my $journalid ( keys %by_journal ) {
            my $loaded = eval {
                _read_posted_comment_text( $author, $journals->{$journalid},
                    $by_journal{$journalid} );
            };
            return _posted_comments_unavailable($r) unless $loaded;
            $text{$journalid} = $loaded;
        }

        foreach my $comment (@eligible) {
            my $raw   = $text{ $comment->journalid }->{ $comment->jtalkid } or next;
            my $chunk = _dump_entry(
                {
                    journal      => $comment->journal->user,
                    permalink    => $comment->url,
                    datetime     => LJ::time_to_w3c( $comment->unixtime, '+0000' ),
                    subject      => $raw->[0],
                    body         => $raw->[1],
                    icon_keyword => $comment->userpic_kw,
                },
                $opts
            );
            $size += bytes::length($chunk);
            return _posted_comments_too_large( $r, $day ) if $size > POSTED_COMMENTS_BYTES;
            push @output, $chunk;
        }
    }

    my $date = sprintf( '%04d-%02d', $year, $month );
    $date .= sprintf( '-%02d', $day ) if length $day;
    my $file = sprintf( '%s-comments-%s.%s', $author->user, $date, $format );
    $r->header_out( 'Content-Disposition' => "attachment; filename=$file" );
    $r->header_out( 'Cache-Control'       => 'private, no-store' );
    $r->content_type(
        $format eq 'csv' ? 'text/csv; charset=utf-8' : 'application/xml; charset=utf-8' );
    $r->print($_) foreach @output, $suffix;
    return $r->OK;
}

sub _read_posted_comment_text {
    my ( $author, $journal, $comments ) = @_;
    my $primary  = LJ::get_cluster_master($journal) or return;
    my %comments = map { $_->jtalkid => $_ } @$comments;
    my $bind     = join ',', ('?') x keys %comments;
    my $rows     = $primary->selectall_arrayref(
        "SELECT c.jtalkid, c.nodeid, t.subject, t.body FROM talk2 c "
            . "LEFT JOIN talktext2 t ON t.journalid=c.journalid AND t.jtalkid=c.jtalkid "
            . "WHERE c.journalid=? AND c.posterid=? AND c.nodetype='L' AND c.state<>'D' "
            . "AND c.jtalkid IN ($bind)",
        undef, $journal->id, $author->id, keys %comments
    );
    return if !$rows || $primary->err;

    my %text;
    foreach my $row (@$rows) {
        my ( $jtalkid, $nodeid, $subject, $body ) = @$row;
        my $comment = $comments{$jtalkid};
        next   unless $comment->nodeid == $nodeid;
        return unless defined $body;
        $subject //= '';
        LJ::text_uncompress( \$subject );
        LJ::text_uncompress( \$body );
        LJ::item_toutf8( $journal, \$subject, \$body, $comment->props )
            if $comment->prop('unknown8bit');
        $text{$jtalkid} = [ $subject, $body ];
    }
    return \%text;
}

sub _posted_comments_unavailable {
    my ($r) = @_;
    $r->status(503);
    return error_ml('/export/index.tt.error.posted_unavailable');
}

sub _posted_comments_too_large {
    my ( $r, $day ) = @_;
    $r->status(422);
    return error_ml(
        length $day
        ? '/export/index.tt.error.posted_day_limit'
        : '/export/index.tt.error.posted_month_limit'
    );
}

# /export_comments (also /export_comments.bml): XML export of a journal's
# comments, used by jbackup, ljdump and the content importer. Authenticated by
# the session cookie; authas= selects a community. Arguments:
#
#   get=comment_meta  ids, posters and states for jtalkids in
#                     [startid, startid + numitems); numitems defaults to and
#                     is capped at 10000. Returns <maxid>, and <nextid> (the
#                     next startid) while more comments remain.
#   get=comment_body  the comments themselves for the same kind of window;
#                     numitems defaults to and is capped at 1000. props=1 adds
#                     comment properties. There is no <maxid> or <nextid>;
#                     clients step through windows up to comment_meta's maxid.
sub comment_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $args   = $r->get_args;
    my $errors = DW::FormErrors->new;

    # don't let people hit us with silly GET attacks
    return error_ml('error.invalidform') if $r->header_in('Referer') && !$r->did_post;

    my $u    = $rv->{u};
    my $dbcr = LJ::get_cluster_reader($u);
    return error_ml('error.nodb') unless $dbcr;

    my $mode = lc( $args->{get} // '' );
    $errors->add( '', "error.unknownmode" ) unless $mode =~ m/^comment_(?:meta|body)$/;

    return DW::Template->render_template( 'error.tt',
        { errors => $errors, message => LJ::Lang::ml('bml.badcontent.body') } )
        if $errors->exist;

    # begin printing results
    $r->content_type("text/xml; charset=utf-8");
    $r->print(qq{<?xml version="1.0" encoding='utf-8'?>\n<livejournal>\n});

    # startid specified?
    my $maxitems = $mode eq 'comment_meta' ? 10000 : 1000;
    my $numitems = $args->{numitems};
    my $gather   = $maxitems;

    if ( defined $numitems && ( $numitems > 0 ) && ( $numitems <= $maxitems ) ) {
        $gather = $numitems + 0;
    }

    my $startid = $args->{startid} ? $args->{startid} + 0 : 0;
    my $endid   = $startid + $gather;

    # get metadata
    my $rows = $dbcr->selectall_arrayref(
        'SELECT jtalkid, nodeid, parenttalkid, posterid, state, datepost '
            . "FROM talk2 WHERE nodetype = 'L' AND journalid = ? AND "
            . "                 jtalkid >= ? AND jtalkid < ?",
        undef, $u->id, $startid, $endid
    );

    # now let's gather them all together while making a list of posterids
    my %posterids;
    my %comments;
    foreach my $r ( @{ $rows || [] } ) {
        $comments{ $r->[0] } = {
            nodeid       => $r->[1],
            parenttalkid => $r->[2],
            posterid     => $r->[3],
            state        => $r->[4],
            datepost     => $r->[5],
        };
        $posterids{ $r->[3] } = 1 if $r->[3];    # don't include 0 (anonymous)
    }

    my $userid = $u->userid;

    # If the poster is suspended, we treat the comment as if it was deleted.
    # This comment may have children, so it must still seem to exist.
    my $filter = sub {
        my ( $data, $us ) = @_;
        return unless $data->{posterid};
        return if $data->{posterid} == $userid;
        $data->{state} = 'D' if $us->{ $data->{posterid} }->is_suspended;
    };

    # now we have two choices: comments themselves or metadata
    if ( $mode eq 'comment_meta' ) {
        my $us = LJ::load_userids( keys %posterids );

        # meta data is easy :)
        my $max = $dbcr->selectrow_array(
            "SELECT MAX(jtalkid) FROM talk2 WHERE journalid = ? AND nodetype = 'L'",
            undef, $userid );
        $max //= 0;
        $r->print("<maxid>$max</maxid>\n");
        my $nextid = $startid + $gather;
        $r->print("<nextid>$nextid</nextid>\n") unless ( $nextid > $max );

        # now spit out the metadata
        $r->print("<comments>\n");
        while ( my ( $id, $data ) = each %comments ) {
            $filter->( $data, $us );

            my $ret = "<comment id='$id'";
            $ret .= " posterid='$data->{posterid}'" if $data->{posterid};
            $ret .= " state='$data->{state}'"       if $data->{state} ne 'A';
            $ret .= " />\n";
            $r->print($ret);
        }

        $r->print("</comments>\n<usermaps>\n");

        # now spit out usermap
        my $ret = '';
        while ( my ( $id, $user ) = each %$us ) {
            $ret .= "<usermap id='$id' user='$user->{user}' />\n";
        }
        $r->print($ret);
        $r->print("</usermaps>\n");

        # comment data also presented in glorious XML:
    }
    elsif ( $mode eq 'comment_body' ) {
        my @ids = sort { $a <=> $b } keys %comments;

        # Load posters, text and props a batch at a time rather than for the whole
        # window at once, which can be tens of megabytes for long comments.
        $r->print("<comments>\n");
        while ( my @batch = splice( @ids, 0, 250 ) ) {
            my $us = LJ::load_userids(
                grep { $_ && $_ != $userid }
                map  { $comments{$_}->{posterid} } @batch
            );
            $filter->( $comments{$_}, $us ) foreach @batch;

            # deleted comments are printed without text
            my @live  = grep { $comments{$_}->{state} ne 'D' } @batch;
            my $texts = @live ? LJ::get_talktext2( $u, @live ) : {};
            my $props = {};
            LJ::load_talk_props2( $userid, \@live, $props ) if $args->{props} && @live;

            foreach my $id (@batch) {

                # print the data
                my $data = $comments{$id};
                my $ret  = "<comment id='$id' jitemid='$data->{nodeid}'";
                $ret .= " posterid='$data->{posterid}'"     if $data->{posterid};
                $ret .= " state='$data->{state}'"           if $data->{state} ne 'A';
                $ret .= " parentid='$data->{parenttalkid}'" if $data->{parenttalkid};
                if ( $data->{state} eq 'D' ) {
                    $ret .= " />\n";
                }
                else {
                    my ( $subject, $body ) = @{ $texts->{$id} || [] };

                    # only spit out valid UTF8, and make sure it fits in XML, and uncompress it
                    LJ::text_uncompress( \$body );
                    LJ::text_out( \$subject );
                    LJ::text_out( \$body );
                    $subject = LJ::exml($subject);
                    $body    = LJ::exml($body);

                    # setup the date to be GMT and formatted per W3C specs
                    my $date = LJ::mysqldate_to_time( $data->{datepost} );
                    $date = LJ::time_to_w3c( $date, 'Z' );

                    $ret .= ">\n";
                    $ret .= "<subject>$subject</subject>\n" if $subject;
                    $ret .= "<body>$body</body>\n" if $body;
                    $ret .= "<date>$date</date>\n";
                    foreach my $propkey ( keys %{ $props->{$id} || {} } ) {
                        $ret .= "<property name='$propkey'>";
                        $ret .= LJ::exml( $props->{$id}->{$propkey} );
                        $ret .= "</property>\n";
                    }
                    $ret .= "</comment>\n";
                }
                $r->print($ret);
            }
        }
        $r->print("</comments>\n");
    }

    # all done
    $r->print("</livejournal>\n");

    return $r->OK;
}

1;
