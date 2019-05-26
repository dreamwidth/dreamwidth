#!/usr/bin/perl
#
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

use strict;

package LJ::S2;

sub MonthPage {
    my ( $u, $remote, $opts ) = @_;

    my $get = $opts->{'getargs'};

    my $p = Page( $u, $opts );
    $p->{'_type'}      = "MonthPage";
    $p->{'view'}       = "month";
    $p->{'days'}       = [];
    $p->{timeformat24} = $remote && $remote->use_24hour_time;

    my $ctx = $opts->{'ctx'};

    my $dbcr = LJ::get_cluster_reader($u);

    my $user        = $u->user;
    my $journalbase = $u->journal_base( vhost => $opts->{'vhost'} );

    if ( $u->should_block_robots ) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    my ( $year, $month );
    if ( $opts->{'pathextra'} =~ m!^/(\d\d\d\d)/(\d\d)\b! ) {
        ( $year, $month ) = ( $1, $2 );
    }

    $opts->{'errors'} = [];
    if ( $month < 1   || $month > 12 )  { push @{ $opts->{'errors'} }, "Invalid month: $month"; }
    if ( $year < 1970 || $year > 2038 ) { push @{ $opts->{'errors'} }, "Invalid year: $year"; }
    unless ($dbcr) { push @{ $opts->{'errors'} }, "Database temporarily unavailable"; }
    return if @{ $opts->{'errors'} };

    $p->{'date'} = Date( $year, $month, 0 );

    # load the log items
    my $dateformat = "%Y %m %d %H %i %s %w";    # yyyy mm dd hh mm ss day_of_week
    my $sth;

    my $secwhere = "AND l.security='public'";
    my $viewall  = 0;
    my $viewsome = 0;
    if ($remote) {

        # do they have the viewall priv?
        ( $viewall, $viewsome ) =
            $remote->view_priv_check( $u, $get->{viewall}, 'month' );

        if ( $viewall || $remote->can_manage($u) ) {
            $secwhere = "";    # see everything
        }
        elsif ( $remote->is_individual ) {
            my $gmask = $u->is_community ? $remote->member_of($u) : $u->trustmask($remote);
            $secwhere =
                "AND (l.security='public' OR (l.security='usemask' AND l.allowmask & $gmask))"
                if $gmask;
        }
    }

    $sth =
        $dbcr->prepare( "SELECT l.jitemid, l.posterid, l.anum, l.day, "
            . "       DATE_FORMAT(l.eventtime, '$dateformat') AS 'alldatepart', "
            . "       l.replycount, l.security, l.allowmask "
            . "FROM log2 l "
            . "WHERE l.journalid=? AND l.year=? AND l.month=? "
            . "$secwhere LIMIT 2000" );
    $sth->execute( $u->{userid}, $year, $month );

    my @items;
    push @items, $_ while $_ = $sth->fetchrow_hashref;
    @items = sort { $a->{'alldatepart'} cmp $b->{'alldatepart'} } @items;

    my %pu;    # poster users;
    foreach (@items) {
        $pu{ $_->{posterid} } = undef;
    }
    LJ::load_userids_multiple( [ map { $_, \$pu{$_} } keys %pu ], [$u] );

    my %day_entries;    # <day> -> [ Entry+ ]

    my $opt_text_subjects = S2::get_property_value( $ctx, "page_month_textsubjects" );

    # we only want the subjects, not the body
    my $entry_opts = { %{ $opts || {} }, no_entry_body => 1 };

ENTRY:
    foreach my $item (@items) {
        my ( $posterid, $itemid, $anum ) =
            map { $item->{$_} } qw(posterid jitemid anum);
        my $day = $item->{'day'};

        my $ditemid   = $itemid * 256 + $anum;
        my $entry_obj = LJ::Entry->new( $u, ditemid => $ditemid );

        # don't show posts from suspended users or suspended posts
        next unless $pu{$posterid};
        next ENTRY if $pu{$posterid}->is_suspended && !$viewsome;
        next ENTRY if $entry_obj && $entry_obj->is_suspended_for($remote);

        # create the S2 entry
        my $entry = Entry_from_entryobj( $u, $entry_obj, $entry_opts );

        push @{ $day_entries{$day} }, $entry;
    }

    my $days_month = LJ::days_in_month( $month, $year );
    for my $day ( 1 .. $days_month ) {
        my $entries   = $day_entries{$day} || [];
        my $month_day = {
            '_type'       => 'MonthDay',
            'date'        => Date( $year, $month, $day ),
            'day'         => $day,
            'has_entries' => scalar @$entries > 0,
            'num_entries' => scalar @$entries,
            'url'         => $journalbase . sprintf( "/%04d/%02d/%02d/", $year, $month, $day ),
            'entries'     => $entries,
        };
        push @{ $p->{'days'} }, $month_day;
    }

    # populate redirector
    my $vhost = $opts->{'vhost'};
    $vhost =~ s/:.*//;
    $p->{'redir'} = {
        '_type' => "Redirector",
        'user'  => $u->{'user'},
        'vhost' => $vhost,
        'type'  => 'monthview',
        'url'   => "$LJ::SITEROOT/go",
    };

    # figure out what months have been posted into
    my $nowval = $year * 12 + $month;

    $p->{'months'} = [];

    my $days   = $u->get_daycounts($remote) || [];
    my $lastmo = '';
    foreach my $day (@$days) {
        my ( $oy, $om ) = ( $day->[0], $day->[1] );
        my $mo = "$oy-$om";
        next if $mo eq $lastmo;
        $lastmo = $mo;

        my $date = Date( $oy, $om, 0 );
        my $url  = $journalbase . sprintf( "/%04d/%02d/", $oy, $om );
        push @{ $p->{'months'} },
            {
            '_type'     => "MonthEntryInfo",
            'date'      => $date,
            'url'       => $url,
            'redir_key' => sprintf( "%04d%02d", $oy, $om ),
            };

        my $val = $oy * 12 + $om;
        if ( $val < $nowval ) {
            $p->{'prev_url'}  = $url;
            $p->{'prev_date'} = $date;
        }
        if ( $val > $nowval && !$p->{'next_date'} ) {
            $p->{'next_url'}  = $url;
            $p->{'next_date'} = $date;
        }
    }

    $p->{head_content} .= qq{<link rel="prev" href="$p->{prev_url}" />\n} if $p->{prev_url};
    $p->{head_content} .= qq{<link rel="next" href="$p->{next_url}" />\n} if $p->{next_url};

    return $p;
}

1;
