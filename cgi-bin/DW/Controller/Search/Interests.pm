#!/usr/bin/perl
#
# DW::Controller::Search::Interests
#
# Interest search, based on code from LiveJournal.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Search::Interests;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use DW::Controller;
use LJ::Constants;

DW::Routing->register_string( '/interests', \&interest_handler, app => 1 );

sub interest_handler {
    my $r = DW::Request->get;
    my $did_post = LJ::did_post();
    my $args = $did_post ? $r->post_args : $r->get_args;
    return error_ml( 'bml.badinput.body' ) unless LJ::text_in( $args );
    return error_ml( 'error.invalidform' )
        if $did_post && ! LJ::check_form_auth( $args->{lj_form_auth} );

    # do mode logic first, to save typing later
    my $mode = '';
    $mode = 'int' if $args->{int} || $args->{intid};
    $mode = 'popular' if $args->{view} && $args->{view} eq "popular";
    if ( $args->{mode} ) {
        $mode = 'add' if $args->{mode} eq "add" && $args->{intid};
        $mode = 'addnew' if $args->{mode} eq "addnew" && $args->{keyword};
        $mode = 'findsim_do' if !$did_post && $args->{mode} eq "findsim_do";
        $mode = 'enmasse'    if !$did_post && $args->{mode} eq "enmasse";
        $mode = 'enmasse_do' if  $did_post && $args->{mode} eq "enmasse_do";
    }

    # check whether authentication is needed or authas is allowed
    # default is to allow anonymous users, except for certain modes
    my $anon = ( $mode eq "add" || $mode eq "addnew" ) ? 0 : 1;
    my $authas = 0;
    ( $anon, $authas ) = ( 0, 1 )
        if $mode eq ( $did_post ? "enmasse_do" : "enmasse" );

    my ( $ok, $rv ) = controller( anonymous => $anon, authas => $authas );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $maxinterests = $remote ? $remote->count_max_interests : 0;
    $rv->{can_use_popular} = LJ::is_enabled( 'interests-popular' );
    $rv->{can_use_findsim} = LJ::is_enabled( 'interests-findsim' )
        && $remote && $remote->can_find_similar;

    # now do argument checking and database work for each mode

    if ( $mode eq 'popular' ) {
        return error_ml( 'interests.popular.disabled' )
            unless $rv->{can_use_popular};
        $rv->{no_text_mode} = 1
            unless $args->{mode} && $args->{mode} eq 'text';

        my $rows = LJ::Stats::get_popular_interests();
        my %interests;
        foreach my $int_array ( @$rows ) {
            my ( $int, $count ) = @$int_array;
            $interests{$int} = { eint  => LJ::ehtml( $int ),
                                 url   => "/interests?int=" . LJ::eurl( $int ),
                                 value => $count };
        }
        $rv->{pop_cloud} = LJ::tag_cloud( \%interests );
        $rv->{pop_ints} = [ sort { $b->{value} <=> $a->{value} } values %interests ]
            if %interests;
        return DW::Template->render_template( 'interests/popular.tt', $rv );
    }

    if ( $mode eq 'add' || $mode eq 'addnew' ) {
        my $rints = $remote->get_interests();
        return error_ml( "interests.add.toomany",
                         { maxinterests => $maxinterests } )
            if scalar( @$rints ) >= $maxinterests;

        my $intid;
        if ( $mode eq "add" ) {
            # adding an existing interest, so we have an intid to work with
            $intid = $args->{intid} + 0;
        } else {
            # adding a new interest
            my @validate = LJ::validate_interest_list( $args->{keyword} );
            $intid = LJ::get_sitekeyword_id( $validate[0] ) if @validate;
        }

        return error_ml( 'error.invalidform' ) unless $intid;

        # force them to either come from the interests page, or have posted the request.
        # if both fail, ask them to confirm with a post form.

        unless ( $did_post || LJ::check_referer( '/interests' ) ) {
            my $int = LJ::get_interest( $intid );
            LJ::text_out( \$int );
            $rv->{need_post} = { int => $int, intid => $intid };
        } else {  # let the user add the interest
            $remote->interest_update( add => [$intid] );
        }
        return DW::Template->render_template( 'interests/add.tt', $rv );
    }

    if ( $mode eq 'findsim_do' ) {
        return error_ml( 'error.tempdisabled' )
            unless LJ::is_enabled( 'interests-findsim' );
        return error_ml( 'interests.findsim_do.account.notallowed' )
            unless $rv->{can_use_findsim};
        my $u = LJ::load_user( $args->{user} )
            or return error_ml( 'error.username_notfound' );
        my $uitable = $u->is_comm ? 'comminterests' : 'userinterests';

        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare( "SELECT i.intid, i.intcount " .
                                 "FROM $uitable ui, interests i " .
                                 "WHERE ui.userid=? AND ui.intid=i.intid" );
        $sth->execute( $u->userid );

        my ( @ints, %intcount, %pt_count, %pt_weight );
        while ( my ( $intid, $count ) = $sth->fetchrow_array ) {
            push @ints, $intid;
            $intcount{$intid} = $count || 1;
        }
        return error_ml( 'interests.findsim_do.notdefined',
                         { user => $u->ljuser_display } )
            unless @ints;

        # the magic's in this limit clause.  that's what makes this work.
        # perfect results?  no.  but who cares if somebody that lists "music"
        # or "reading" doesn't get an extra point towards matching you.
        # we care about more unique interests.

        foreach ( qw( userinterests comminterests ) ) {
            $sth = $dbr->prepare( "SELECT userid FROM $_ WHERE intid=? LIMIT 300" );
            foreach my $int ( @ints ) {
                $sth->execute( $int );
                while ( my $uid = $sth->fetchrow_array ) {
                    next if $uid == $u->userid;
                    $pt_weight{$uid} += ( 1 / log( $intcount{$int} + 1 ) );
                    $pt_count{$uid}++;
                }
            }
        }

        my %magic;  # balanced points
        $magic{$_} = $pt_weight{$_} * 10 + $pt_count{$_}
            foreach keys %pt_count;
        my @matches = sort { $magic{$b} <=> $magic{$a} } keys %magic;
        @matches = @matches[ 0 .. ( $maxinterests - 1 ) ]
            if scalar( @matches ) > $maxinterests;

        # load user objects
        my $users = LJ::load_userids( @matches );

        my $nocircle = $remote && $args->{nocircle};
        my $count = 1;
        my $data = [];
        foreach my $uid ( @matches ) {
            my $match_u = $users->{$uid};
            next unless $match_u && $match_u->is_visible;
            if ( $nocircle ) {
                next if $remote->watches( $match_u );
                next if $remote->trusts( $match_u );
            }
            push @$data, { count => $count++,
                           user  => $match_u->ljuser_display,
                           magic => sprintf( "%.3f", $magic{$uid} ) };
        }

        return error_ml( 'interests.findsim_do.nomatch',
                         { user => $u->ljuser_display } )
            unless @$data;

        $rv->{findsim_u} = $u;
        $rv->{findsim_data} = $data;
        $rv->{nocircle} = $nocircle;
        $rv->{circle_link} =
            LJ::page_change_getargs( nocircle => $nocircle ? '' : 1 );

        return DW::Template->render_template( 'interests/findsim.tt', $rv );
    }

    if ( $mode eq 'enmasse' ) {
        my $u = $rv->{u};
        my $username = $u->user;
        my $altauthas = $remote->user ne $username;
        $rv->{getextra} = $altauthas ? "?authas=$username" : '';

        my $fromu = LJ::load_user( $args->{fromuser} || $username )
            or return error_ml( 'error.username_notfound' );
        $rv->{fromu} = $fromu;

        my %uint;
        my %fromint = %{ $fromu->interests } or
            return error_ml( 'interests.error.nointerests' );
        $rv->{allintids} = join ( ",", values %fromint );

        if ( $u->equals( $fromu ) ) {
            %uint = %fromint;
            $rv->{enmasse_body} = '.enmasse.body.you';
        } else {
            %uint = %{ $u->interests };
            my $other = $altauthas ? 'other_authas' : 'other';
            $rv->{enmasse_body} = ".enmasse.body.$other";
        }

        my @checkdata;
        foreach my $fint ( sort keys %fromint ) {
            push @checkdata, { checkid => "int_$fromint{$fint}",
                               is_checked => $uint{ $fint } ? 1 : 0,
                               int => $fint };
        }
        $rv->{enmasse_data} = \@checkdata;
        return DW::Template->render_template( 'interests/enmasse.tt', $rv );
    }

    if ( $mode eq 'enmasse_do' ) {
        my $u = $rv->{u};

        # $args is actually an object so we want a plain hashref
        my $argints = {};
        foreach my $key ( keys %$args ) {
            $argints->{$key} = $args->{$key} if $key =~ /^int_\d+$/;
        }

        my @fromints = map { $_ + 0 }
                       split /\s*,\s*/, $args->{allintids};
        my $sync = $u->sync_interests( $argints, @fromints );

        my $result_ml = 'interests.results.';
        if ( $sync->{deleted} ) {
            $result_ml .= $sync->{added}   ? 'both' :
                          $sync->{toomany} ? 'del_and_toomany' : 'deleted';
        } else {
            $result_ml .= $sync->{added}   ? 'added' :
                          $sync->{toomany} ? 'toomany' : 'nothing';
        }
        $rv->{enmasse_do_result} = $result_ml;
        $rv->{toomany} = $sync->{toomany} || 0;
        $rv->{fromu} = LJ::load_user( $args->{fromuser} )
            unless !$args->{fromuser} or $u->user eq $args->{fromuser};
        return DW::Template->render_template( 'interests/enmasse_do.tt', $rv );
    }

    if ( $mode eq 'int' ) {
        my $intarg = LJ::utf8_lc ( $args->{int} );
        my $intid = $args->{intid} ? $args->{intid} + 0 :
            LJ::get_sitekeyword_id( $intarg, 0 ) || 0;
        my ( $interest, $intcount ) = LJ::get_interest( $intid );

        my $check_int = $intarg || $interest;
        if ( LJ::Hooks::run_hook( "interest_search_ignore",
                                  query => $check_int, intid => $intid ) ) {
            return error_ml( 'interests.error.ignored' );
        }

        my $e_int = LJ::ehtml( $check_int );
        # determine whether the interest is too long:
        # 1. if the interest already exists, a long interest will result in $check_int and $interest not matching
        # 2. if it didn't already exist, we fall back on just checking the length of $check_int
        if ( ( $interest && $check_int ne $interest ) || length( $check_int ) > LJ::CMAX_SITEKEYWORD ) {
            # if the searched-for interest is too long, we use the short version from here on
            my $e_int_long = $e_int;
            $e_int = LJ::ehtml( $interest ? $interest : substr( $check_int, 0, LJ::CMAX_SITEKEYWORD ) );
            $rv->{warn_toolong} =
                LJ::Lang::ml( 'interests.error.longinterest',
                              { sitename => $LJ::SITENAMESHORT,
                                old_int => $e_int_long, new_int => $e_int,
                                maxlen => LJ::CMAX_SITEKEYWORD } );
        }
        $rv->{e_int} = $e_int;
        $rv->{interest} = $interest;
        $rv->{intid} = $intid;
        $rv->{intcount} = $intcount;

        my $dbr = LJ::get_db_reader();
        my $int_query = sub {
            my $i = shift;  # comminterests or userinterests
            my $LIMIT = 500;
            my $q = "SELECT $i.userid FROM $i, userusage
                     WHERE $i.intid = ? AND $i.userid = userusage.userid
                     ORDER BY userusage.timeupdate DESC LIMIT $LIMIT";
            my $uref = $dbr->selectall_arrayref( $q, undef, $intid );
            return LJ::load_userids( map { $_->[0] } @$uref );
            # can't trust LJ::load_userids to maintain sort order
        };

        my $should_show = sub {
            return $_[0]->should_show_in_search_results( for => $remote );
        };

        # community results
        if ( LJ::is_enabled( 'interests-community' ) ) {
            my $us = $int_query->( "comminterests" );
            my $updated = LJ::get_timeupdate_multi( keys %$us );
            my $def_upd = sub { $updated->{$_[0]->userid} || 0 };
            # let undefined values be zero for sorting purposes
            my @cl = sort { $def_upd->($b) <=> $def_upd->($a) || $a->user cmp $b->user }
                     grep { $_ && $should_show->( $_ ) } values %$us;
            $rv->{int_comms} = { count => scalar @cl, data => [] };
            foreach ( @cl ) {
                my $updated = $updated->{$_->id}
                            ? LJ::diff_ago_text( $updated->{$_->id} )
                            : undef;
                my $prop_theme = $_->prop("comm_theme");
                my $theme = LJ::is_enabled('community_themes') && $prop_theme
                          ? LJ::ehtml( $prop_theme )
                          : undef;
                push @{ $rv->{int_comms}->{data} },
                      { u => $_, updated => $updated, theme => $theme };
            }
        }

        # user results
        my $us = $int_query->( "userinterests" );
        my @ul = grep { $_
                        && ! $_->is_community            # not communities
                        && $should_show->( $_ )          # and should show to the remote user
                      } values %$us;
        my $navbar;
        my $results =
            LJ::user_search_display( users      => \@ul,
                                     timesort   => 1,
                                     perpage    => 50,
                                     curpage    => exists $args->{page} ?
                                                   $args->{page} : 1,
                                     navbar     => \$navbar );

        $rv->{int_users} = { count => scalar( @ul ), navbar => $navbar,
                             results => $results };

        # check to see if the remote user already has the interest
        $rv->{not_interested} = ! $remote->interests->{$interest}
            if $remote && defined $interest;

        return DW::Template->render_template( 'interests/int.tt', $rv );
    }


    # if we got to this point, we need to render the default template
    return DW::Template->render_template( 'interests/index.tt', $rv );
}


1;
