#!/usr/bin/perl
#
# DW::Controller::Support::Help
#
# The support board (/support/help): the queue of support requests, filterable
# by state (open/closed/green/you-replied) and category, sortable, with a
# mass-action form (close / close-with-points / move) for users who can close
# requests in the selected category. The mass-action form posts to
# /support/actmulti.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Support::Help;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Support;

DW::Routing->register_string( '/support/help', \&help_handler, app => 1 );

sub help_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $scope  = '/support/help.tt';
    my $get    = $r->get_args;
    my $remote = $rv->{remote};
    my $dbr    = LJ::get_db_reader();

    LJ::Support::init_remote($remote);
    my $cats = LJ::Support::load_cats();

    my $state = $get->{state};
    $state = 'open' unless $state && $state =~ /^(?:open|closed|green|youreplied)$/;

    my $filtercat = $get->{cat};
    $filtercat = "" unless $filtercat && $filtercat =~ /^[\w\-,]+$/;
    my $fcat     = LJ::Support::get_cat_by_key( $cats, $filtercat );
    my $can_read = LJ::Support::can_read_cat( $fcat, $remote );

    # can the viewer close requests in this category/view?
    my $can_close = 0;
    if ( $remote && $state =~ /(?:green|open)/ && $filtercat && $filtercat !~ /^_/ ) {
        $can_close = 1 if $remote->has_priv( 'supportclose', $filtercat );
        $can_close = 1 if $fcat->{public_read} && $remote->has_priv( 'supportclose', '' );
    }

    # heading + intro vary by state; only the "open" view shows the count line
    my $append = 0;
    if ( $state eq 'closed' ) {
        $rv->{heading}  = 'closed';
        $rv->{clickurl} = "href=\"$LJ::SITEROOT/support/help?cat=$filtercat\"";
    }
    elsif ( $state eq 'youreplied' ) {
        return error_ml("$scope.state.youreplied.rem.text") unless $remote;
        $rv->{heading} = 'youreplied';
    }
    else {
        $rv->{heading}   = 'else';
        $rv->{statelink} = "href=\"$LJ::SITEROOT/support/help?state=closed&amp;cat=$filtercat\"";
        $append          = 1;
    }

    my @support_log;
    my $rct       = 0;
    my $abstracts = 0;

    if (   $filtercat
        && $LJ::SUPPORT_ABSTRACTS{$filtercat}
        && $fcat
        && $can_read
        && $state ne 'youreplied' )
    {
        # show the first 200 chars of each request as an abstract
        my $sql =
            $state eq 'closed'
            ? "SELECT s.*, SUBSTRING(sl.message, 1, 200) AS 'message' FROM support s, supportlog sl"
            . " WHERE s.state='closed' AND s.spid = sl.spid AND sl.type = 'req'"
            . " AND s.timeclosed > (UNIX_TIMESTAMP() - (3600*168)) AND s.spcatid = ?"
            : "SELECT s.*, SUBSTRING(sl.message, 1, 200) AS 'message' FROM support s, supportlog sl"
            . " WHERE s.state='open' AND s.spid = sl.spid AND sl.type = 'req' AND s.spcatid = ?";
        my $sth = $dbr->prepare($sql);
        $sth->execute( $fcat->{spcatid} );
        push @support_log, $_ while $_ = $sth->fetchrow_hashref;
        $rct       = scalar @support_log;
        $abstracts = 1;
    }
    else {
        my $filterwhere = '';

        if ( $filtercat eq '_nonpublic' ) {
            $filterwhere = " AND s.spcatid IN (0";
            foreach my $cat ( values %$cats ) {
                $filterwhere .= ", " . ( $cat->{spcatid} + 0 )
                    if !$cat->{public_read} && LJ::Support::can_read_cat( $cat, $remote );
            }
            $filterwhere .= ")";
        }
        elsif ( $filtercat eq '_nonprivate' ) {
            $filterwhere = " AND s.spcatid IN (0";
            foreach my $cat ( values %$cats ) {
                $filterwhere .= ", " . ( $cat->{spcatid} + 0 ) if $cat->{public_read};
            }
            $filterwhere .= ")";
        }
        elsif ( $filtercat =~ /,/ ) {
            my %filtercats = map { $_ => 1 } split( ",", $filtercat );
            $filterwhere = " AND s.spcatid IN (0";
            foreach my $cat ( values %$cats ) {
                next unless $filtercats{ $cat->{catkey} };
                $filterwhere .= ", " . ( $cat->{spcatid} + 0 )
                    if LJ::Support::can_read_cat( $cat, $remote );
            }
            $filterwhere .= ")";
        }
        else {
            if ($can_read) {
                $filterwhere = " AND s.spcatid=" . ( $fcat->{spcatid} + 0 );
            }
            else {
                $filtercat = "";
            }
        }

        my $sth;
        if ( $state eq 'closed' ) {
            $sth = $dbr->prepare( "SELECT s.* FROM support s WHERE s.state='closed'"
                    . " AND s.timeclosed>UNIX_TIMESTAMP()-(3600*168) $filterwhere" );
        }
        elsif ( $state eq 'youreplied' ) {
            $sth = $dbr->prepare(
                      "SELECT s.* FROM support s, support_youreplied yr WHERE yr.userid="
                    . ( $remote->userid + 0 )
                    . " AND s.spid=yr.spid $filterwhere"
                    . " AND (s.state='open' OR (s.state='closed' AND s.timeclosed>UNIX_TIMESTAMP()-(3600*168)))"
            );
        }
        else {
            $sth = $dbr->prepare("SELECT s.* FROM support s WHERE s.state='open' $filterwhere");
        }
        $sth->execute;

        # the you-replied query can return a request more than once; dedup here
        # rather than pay for a DISTINCT temp table
        my %spids_seen;
        while ( my $sprow = $sth->fetchrow_hashref ) {
            next if $spids_seen{ $sprow->{spid} };
            $spids_seen{ $sprow->{spid} } = 1;
            push @support_log, $sprow;
            $rct++;
        }
    }

    my $sort = lc( $get->{sort} || '' );
    $sort = 'date' unless grep { $_ eq $sort } qw( id summary area recent );

    # the count line on the open view
    if ($append) {
        my ( $gct, $snhct, $aacct ) = ( 0, 0, 0 );
        foreach (@support_log) {
            if ( $_->{timelasthelp} > $_->{timetouched} + 5 ) {
                $aacct++;
            }
            elsif ( $_->{timelasthelp} && $_->{timetouched} > $_->{timelasthelp} + 5 ) {
                $snhct++;
            }
            else {
                $gct++;
            }
        }
        $rv->{counts} = { gct => $gct, snhct => $snhct, aacct => $aacct, rct => $rct };
    }

    my $can_view_nonpublic_modtime = $remote
        && ( $remote->has_priv('supportviewinternal') || $remote->has_priv('supporthelp') );

    # timemodified is bumped by ICs/screened answers, so it's only an accurate
    # "last active" signal for staff who can see those
    my $time_active = sub {
        return $_[0]->{timemodified}
            if $can_view_nonpublic_modtime && $_[0]->{timemodified};
        my $touched  = $_[0]->{timetouched};
        my $lasthelp = $_[0]->{timelasthelp};
        return $lasthelp > $touched ? $lasthelp : $touched;
    };

    if ( $sort eq 'id' ) {
        @support_log = sort { $a->{spid} <=> $b->{spid} } @support_log;
    }
    elsif ( $sort eq 'date' ) {
        @support_log = sort { $b->{timecreate} <=> $a->{timecreate} } @support_log;
    }
    elsif ( $sort eq 'summary' ) {
        @support_log = sort { $a->{subject} cmp $b->{subject} } @support_log;
    }
    elsif ( $sort eq 'area' ) {
        @support_log =
            sort { $cats->{ $a->{spcatid} }->{catname} cmp $cats->{ $b->{spcatid} }->{catname} }
            @support_log;
    }
    elsif ( $sort eq 'recent' ) {
        @support_log = sort { $time_active->($b) <=> $time_active->($a) } @support_log;
    }

    # state dropdown
    my @state_opts = ( '' => '.state.open', closed => '.state.closed', green => '.state.green' );
    push @state_opts, ( youreplied => '.statr.youreplied' ) if $remote;
    my @state_options;
    while (@state_opts) {
        my ( $skey, $slabel ) = splice( @state_opts, 0, 2 );
        push @state_options,
            {
            value    => $skey,
            label    => LJ::Lang::ml("$scope$slabel"),
            selected => ( $state eq $skey ? 1 : 0 ),
            };
    }
    $rv->{state_options} = \@state_options;

    # category dropdown
    my @filter_cats = LJ::Support::filter_cats( $remote, $cats );
    if ( $remote && $remote->has_priv("supportread") ) {
        unshift @filter_cats, { catkey => '_nonpublic',  catname => '(Private)' };
        unshift @filter_cats, { catkey => '_nonprivate', catname => '(Public)' };
    }
    my @cat_options =
        ( { value => '', label => '(' . LJ::Lang::ml("$scope.cat.all") . ')', selected => 1 } );
    foreach my $cat (@filter_cats) {
        push @cat_options,
            {
            value    => $cat->{catkey},
            label    => $cat->{catname},
            selected => ( $filtercat eq $cat->{catkey} ? 1 : 0 ),
            };
    }
    $cat_options[0]->{selected} = 0 if $filtercat ne '';
    $rv->{cat_options} = \@cat_options;

    # sortable column headers
    my @headers = (
        id      => 'ID#',
        summary => "$scope.th.summary",
        area    => "$scope.th.problemarea",
        date    => "$scope.th.posted",
        recent  => "$scope.th.recent",
    );
    my @header_list;
    while (@headers) {
        my ( $stype, $key ) = splice( @headers, 0, 2 );
        push @header_list,
            {
            sorttype   => $stype,
            desc       => ( $stype eq 'id' ? 'ID#' : LJ::Lang::ml($key) ),
            is_current => ( $sort eq $stype ? 1 : 0 ),
            };
    }
    $rv->{headers} = \@header_list;

    # one display row per readable request
    my %marked   = map { $_ => 1 } split( ',', $get->{mark} || '' );
    my $closeall = $get->{closeall} ? 1 : 0;

    my @rows;
    foreach my $sp (@support_log) {
        LJ::Support::fill_request_with_cat( $sp, $cats );
        next unless LJ::Support::can_read( $sp, $remote );

        my $status =
            $sp->{state} eq "closed"
            ? "closed"
            : LJ::Support::open_request_status( $sp->{timetouched}, $sp->{timelasthelp} );

        my $barbg;
        if    ( $status eq "open" )   { $barbg = "green"; }
        elsif ( $status eq "closed" ) { $barbg = "red"; }
        elsif ( $status eq "awaiting close" ) {
            $status = "answered<br/>awaiting close";
            $barbg  = "yellow";
        }
        elsif ( $status eq "still needs help" ) {
            $status = "answered<br/><strong>still needs help</strong>";
            $barbg  = "green";
        }

        my $original_barbg = $barbg;
        $barbg = 'clicked'
            if ( $closeall && $original_barbg eq 'yellow' ) || $marked{ $sp->{spid} };

        next if $state eq "green" && $barbg ne "green";

        # decode RFC2047-encoded subjects
        eval {
            if ( $sp->{subject} =~ /^=\?(utf-8)?/i ) {
                require MIME::Words;
                my @subj_data = MIME::Words::decode_mimewords( $sp->{subject} );
                if ( scalar @subj_data ) {
                    $sp->{subject} =
                        !$1
                        ? Unicode::MapUTF8::to_utf8(
                        { -string => $subj_data[0][0], -charset => $subj_data[0][1] } )
                        : $subj_data[0][0];
                }
            }
        };

        my $des = '';
        if ($abstracts) {
            my $temp = LJ::text_trim( $sp->{message}, 0, 100 );
            my $msg =
                $temp ne $sp->{message}
                ? LJ::ehtml($temp) . " ..."
                : LJ::ehtml( $sp->{message} ) . " <b>&#x00b6;</b>";
            $des = "<br /><i>$msg</i>";
        }

        my $time_display = sub {
            return LJ::mysql_time( $_[0] ) if $get->{rawdates};
            return LJ::ago_text( ( time() - $_[0] ) || 1 );
        };

        unless ( $status eq "closed" ) {
            my $points = LJ::Support::calc_points( $sp, time() - $sp->{timecreate} );
            $status .= "<br />($points point" . ( $points > 1 ? "s" : "" ) . ")";
        }

        push @rows,
            {
            spid           => $sp->{spid},
            summary        => LJ::ehtml( $sp->{subject} ),
            des            => $des,
            probarea       => $sp->{_cat}->{catname},
            age            => $time_display->( $sp->{timecreate} ),
            untouched      => $time_display->( $time_active->($sp) ),
            status         => $status,
            barbg          => $barbg,
            original_barbg => $original_barbg,
            };
    }
    $rv->{rows} = \@rows;

    LJ::need_res( { priority => $LJ::OLD_RES_PRIORITY }, 'stc/support.css' );

    $rv->{robot_meta_tags} = LJ::robot_meta_tags();
    $rv->{can_close}       = $can_close;
    $rv->{abstracts}       = $abstracts;
    $rv->{rct}             = $rct;
    $rv->{state}           = $state;
    $rv->{filtercat}       = $filtercat;
    $rv->{sort}            = $sort;
    $rv->{uri}             = "$LJ::SITEROOT/support/help?cat=$filtercat&state=$state";
    $rv->{closeall_link}   = "$rv->{uri}&sort=$sort&closeall=" . ( $get->{closeall} ? 0 : 1 )
        if $can_close;

    # mass-action form payload (only when there's something closeable)
    if ( $can_close && $rct ) {
        $rv->{ids}             = join( ':', map { $_->{spid} } @support_log );
        $rv->{spcatid}         = $fcat->{spcatid};
        $rv->{ret}             = "/support/help?state=$state&cat=$filtercat&time=" . time() . "%s";
        $rv->{movecat_options} = [
            '', '(no change)',
            map { $_->{spcatid}, "---> $_->{catname}" } LJ::Support::sorted_cats($cats)
        ];
    }

    $rv->{notifylink} = LJ::Lang::ml( "$scope.notifylink", { url     => 'href="./changenotify"' } );
    $rv->{backlink}   = LJ::Lang::ml( "$scope.backlink",   { backurl => 'href="./"' } );

    return DW::Template->render_template( 'support/help.tt', $rv );
}

1;
