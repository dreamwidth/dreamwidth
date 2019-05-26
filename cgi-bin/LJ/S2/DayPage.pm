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

sub DayPage {
    my ( $u, $remote, $opts ) = @_;

    my $p = Page( $u, $opts );
    $p->{'_type'}   = "DayPage";
    $p->{'view'}    = "day";
    $p->{'entries'} = [];

    my $user        = $u->user;
    my $journalbase = $u->journal_base( vhost => $opts->{'vhost'} );

    if ( $u->should_block_robots ) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    # include JS for quick reply, icon browser, and ajax cut tag
    my $handle_with_siteviews = $opts->{handle_with_siteviews_ref}
        && ${ $opts->{handle_with_siteviews_ref} };
    LJ::Talk::init_s2journal_js(
        iconbrowser => $remote && $remote->can_use_userpic_select,
        siteskin    => $handle_with_siteviews,
        lastn       => 1
    );

    my $collapsed   = BML::ml('widget.cuttag.collapsed');
    my $expanded    = BML::ml('widget.cuttag.expanded');
    my $collapseAll = BML::ml('widget.cuttag.collapseAll');
    my $expandAll   = BML::ml('widget.cuttag.expandAll');
    $p->{'head_content'} .= qq[
  <script type='text/javascript'>
  expanded = '$expanded';
  collapsed = '$collapsed';
  collapseAll = '$collapseAll';
  expandAll = '$expandAll';
  </script>
    ];

    my $get = $opts->{'getargs'};

    my $month  = $get->{'month'};
    my $day    = $get->{'day'};
    my $year   = $get->{'year'};
    my @errors = ();

    if ( $opts->{'pathextra'} =~ m!^/(\d\d\d\d)/(\d\d)/(\d\d)\b! ) {
        ( $month, $day, $year ) = ( $2, $3, $1 );
    }

    $opts->{'errors'} = [];
    if ( $year  !~ /^\d+$/ ) { push @{ $opts->{'errors'} }, "Corrupt or non-existant year."; }
    if ( $month !~ /^\d+$/ ) { push @{ $opts->{'errors'} }, "Corrupt or non-existant month."; }
    if ( $day   !~ /^\d+$/ ) { push @{ $opts->{'errors'} }, "Corrupt or non-existant day."; }
    if ( $month < 1 || $month > 12 || int($month) != $month ) {
        push @{ $opts->{'errors'} }, "Invalid month.";
    }
    if ( $year < 1970 || $year > 2038 || int($year) != $year ) {
        push @{ $opts->{'errors'} }, "Invalid year: $year";
    }
    if ( $day < 1 || $day > 31 || int($day) != $day ) {
        push @{ $opts->{'errors'} }, "Invalid day.";
    }
    if ( scalar( @{ $opts->{'errors'} } ) == 0 && $day > LJ::days_in_month( $month, $year ) ) {
        push @{ $opts->{'errors'} }, "That month doesn't have that many days.";
    }
    return if @{ $opts->{'errors'} };

    $p->{'date'} = Date( $year, $month, $day );

    my $secwhere = "AND security='public'";
    my $viewall  = 0;
    my $viewsome = 0;                         # see public posts from suspended users
    if ($remote) {

        # do they have the viewall priv?
        ( $viewall, $viewsome ) =
            $remote->view_priv_check( $u, $get->{viewall}, 'day' );

        if ( $viewall || $remote->equals($u) || $remote->can_manage($u) ) {
            $secwhere = "";                   # see everything
        }
        elsif ( $remote->is_individual ) {
            my $gmask = $u->is_community ? $remote->member_of($u) : $u->trustmask($remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    my $dbcr = LJ::get_cluster_reader($u);
    unless ($dbcr) {
        push @{ $opts->{'errors'} }, "Database temporarily unavailable";
        return;
    }

    # load the log items
    my $dateformat = "%Y %m %d %H %i %s %w";    # yyyy mm dd hh mm ss day_of_week
    my $sth =
        $dbcr->prepare( "SELECT jitemid AS itemid, posterid, security, allowmask, "
            . "DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum, "
            . "DATE_FORMAT(logtime, \"$dateformat\") AS 'system_alldatepart' "
            . "FROM log2 "
            . "WHERE journalid=$u->{'userid'} AND year=$year AND month=$month AND day=$day $secwhere "
            . "ORDER BY eventtime, logtime LIMIT 2000" );
    $sth->execute;

    my @items;
    push @items, $_ while $_ = $sth->fetchrow_hashref;

    $opts->{cut_disable} = ( $remote && $remote->prop('opt_cut_disable_journal') );

ENTRY:
    foreach my $item (@items) {
        my ( $posterid, $itemid, $anum ) =
            map { $item->{$_} } qw(posterid itemid anum);

        my $ditemid   = $itemid * 256 + $anum;
        my $entry_obj = LJ::Entry->new( $u, ditemid => $ditemid );

        # don't show posts from suspended users or suspended posts
        next ENTRY if $entry_obj && $entry_obj->poster->is_suspended && !$viewsome;
        next ENTRY if $entry_obj && $entry_obj->is_suspended_for($remote);

        # create S2 Entry object
        my $entry = Entry_from_entryobj( $u, $entry_obj, $opts );

        # add S2 Entry object to page
        push @{ $p->{entries} }, $entry;
        LJ::Hooks::run_hook( 'notify_event_displayed', $entry_obj );
    }

    if ( @{ $p->{'entries'} } ) {
        $p->{'has_entries'}                = 1;
        $p->{'entries'}->[0]->{'new_day'}  = 1;
        $p->{'entries'}->[-1]->{'end_day'} = 1;
    }

    # find near days
    my ( $prev, $next );
    my $here = sprintf( "%04d%02d%02d", $year, $month, $day );    # we are here now
    foreach ( @{ $u->get_daycounts($remote) } ) {
        $_ = sprintf( "%04d%02d%02d", (@$_)[ 0 .. 2 ] );          # map each date as YYYYMMDD number
        if ( $_ < $here && ( !$prev || $_ > $prev ) )
        {    # remember in $prev less then $here last date
            $prev = $_;
        }
        elsif ( $_ > $here && ( !$next || $_ < $next ) )
        {    # remember in $next greater then $here first date
            $next = $_;
        }
    }

    # create Date objects for ($prev, $next) pair
    my ( $pdate, $ndate ) =
        map { defined $_ && /^(\d\d\d\d)(\d\d)(\d\d)\b/ ? Date( $1, $2, $3 ) : Null('Date') }
        ( $prev, $next );

    # insert slashes into $prev and $next
    map { defined $_ && s!^(\d\d\d\d)(\d\d)(\d\d)\b!$1/$2/$3! } ( $prev, $next );

    $p->{'prev_url'}  = defined $prev ? ("$u->{'_journalbase'}/$prev") : '';
    $p->{'prev_date'} = $pdate;
    $p->{'next_url'}  = defined $next ? ("$u->{'_journalbase'}/$next") : '';
    $p->{'next_date'} = $ndate;

    $p->{head_content} .= qq{<link rel="prev" href="$p->{prev_url}" />\n} if $p->{prev_url};
    $p->{head_content} .= qq{<link rel="next" href="$p->{next_url}" />\n} if $p->{next_url};

    return $p;
}

1;
