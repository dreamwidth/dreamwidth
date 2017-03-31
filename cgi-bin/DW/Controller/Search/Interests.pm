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
use LJ::Global::Constants;

DW::Routing->register_string( '/interests', \&interest_handler, app => 1 );

sub interest_handler {
    my $r = DW::Request->get;
    my $did_post = $r->did_post;
    my $args = $did_post ? $r->post_args : $r->get_args;
    return error_ml( 'bml.badinput.body1' ) unless LJ::text_in( $args );
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

        my @intids;
        if ( $mode eq "add" ) {
            # adding an existing interest, so we have an intid to work with
            @intids = ( $args->{intid} + 0 );
        } else {
            # adding a new interest
            my @keywords = LJ::interest_string_to_list( $args->{keyword} );
            my @validate = LJ::validate_interest_list( @keywords );
            @intids = map { LJ::get_sitekeyword_id( $_ ) } @validate;
        }

        @intids = grep { $_ } @intids;  # ignore any zeroes
        return error_ml( 'error.invalidform' ) unless @intids;

        # force them to either come from the interests page, or have posted the request.
        # if both fail, ask them to confirm with a post form.
        # (only uses first interest; edge case not worth the trouble to fix)

        unless ( $did_post || LJ::check_referer( '/interests' ) ) {
            my $int = LJ::get_interest( $intids[0] );
            LJ::text_out( \$int );
            $rv->{need_post} = { int => $int, intid => $intids[0] };
        } else {  # let the user add the interest
            $remote->interest_update( add => \@intids );
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
        my $count = { P => 0, C => 0, I => 0 };
        my $data = { P => [], C => [], I => [] };
        foreach my $uid ( @matches ) {
            my $match_u = $users->{$uid};
            next unless $match_u && $match_u->is_visible;
            if ( $nocircle ) {
                next if $remote->watches( $match_u );
                next if $match_u->is_person && $remote->trusts( $match_u );
                next if $match_u->is_comm && $remote->member_of( $match_u );
            }
            my $j = $match_u->journaltype;
            push @{ $data->{$j} },
                    { count => ++$count->{$j},
                      user  => $match_u->ljuser_display,
                      magic => sprintf( "%.3f", $magic{$uid} ) };
        }

        return error_ml( 'interests.findsim_do.nomatch',
                         { user => $u->ljuser_display } )
            unless grep { $_ } values %$count;

        $rv->{findsim_u} = $u;
        $rv->{findsim_count} = $count;
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
        my $trunc_check = sub {
            my ( $check_int, $interest ) = @_;
            my $e_int = LJ::ehtml( $check_int );

            # Determine whether the interest is too long:
            # 1. If the interest already exists, a long interest will result
            #    in $check_int and $interest not matching.
            # 2. If it didn't already exist, we fall back on just checking
            #    the length of $check_int.

            if ( ( $interest && $check_int ne $interest ) ||
                   length( $check_int ) > LJ::CMAX_SITEKEYWORD ) {

                # The searched-for interest is too long, so use the short version.
                my $e_int_long = $e_int;
                $e_int = LJ::ehtml( $interest ? $interest :
                                    substr( $check_int, 0, LJ::CMAX_SITEKEYWORD ) );

                $rv->{warn_toolong} = ( $rv->{warn_toolong} ?
                                        $rv->{warn_toolong} . "<br />" : '' ) .
                    LJ::Lang::ml( 'interests.error.longinterest',
                                  { sitename => $LJ::SITENAMESHORT,
                                    old_int => $e_int_long, new_int => $e_int,
                                    maxlen => LJ::CMAX_SITEKEYWORD } );
            }

            return $e_int;
        };

        my ( @intids, @intargs );
        if ( $args->{intid} ) {
            @intids = ( $args->{intid} + 0 );
        } else {
            @intargs = LJ::interest_string_to_list( $args->{int} );
            @intids = map { LJ::get_sitekeyword_id( $_, 0 ) || 0 } @intargs;
        }

        my $max_search = 3;
        if ( scalar @intids > $max_search ) {
            return error_ml( 'interests.error.toomany', { num => $max_search } );
        }

        my ( @intdata, @no_users, @not_interested );
        my $index = 0;  # for referencing @intargs
        my $remote_interests = $remote ? $remote->interests : {};

        foreach my $intid ( @intids ) {
            my $intarg = @intargs ? $intargs[$index++] : '';
            my ( $interest, $intcount ) = LJ::get_interest( $intid );
            my $check_int = $intarg || $interest;

            if ( LJ::Hooks::run_hook( "interest_search_ignore",
                                      query => $check_int,
                                      intid => $intid ) ) {
                return error_ml( 'interests.error.ignored' );
            }

            my $e_int = $trunc_check->( $check_int, $interest );
            push @intdata, $e_int;
            push @no_users, $e_int unless $intcount;

            $rv->{allcount} = $intcount if scalar @intids == 1;

            # check to see if the remote user already has the interest
            push @not_interested, { int => $e_int, intid => $intid }
                if defined $interest && ! $remote_interests->{$interest};
        }

        $rv->{interest} = join ', ', @intdata;
        $rv->{query_count} = scalar @intdata;
        $rv->{no_users} = join ', ', @no_users;
        $rv->{no_users_count} = scalar @no_users;
        $rv->{not_interested} = \@not_interested;

        # if any one interest is unused, the search can't succeed
        undef @intids if @no_users;

        # filtering by account type
        my @type_args = ( 'none', 'P', 'C', 'I' );
        push @type_args, 'F' if $remote;  # no circle if not logged in
        $rv->{type_list} = \@type_args;

        my $type = $args->{type};
        $type = 'none' unless $type && $type =~ /^[PCIF]$/;
        $type = 'none' if $type eq 'F' && ! $remote;  # just in case

        # constructor for filter links
        $rv->{type_link} = sub {
            return '' if $type eq $_[0];  # no link for active selection
            my $typearg = $_[0] eq 'none' ? '' : $_[0];
            return LJ::page_change_getargs( type => $typearg );
        };

        # determine which account types we need to search for
        my $type_opts = {};
        my %opt_map = ( C => 'nousers', P => 'nocomms',
                        I => 'nocomms', F => 'circle' );
        $type_opts = { $opt_map{$type} => 1 } if defined $opt_map{$type};

        my @uids = LJ::users_with_all_ints( \@intids, $type_opts );

        # determine the count of the full set for comparison
        # (already set to intcount, unless we have multiple ints)
        if ( $opt_map{$type} ) {
            $rv->{allcount} ||= scalar LJ::users_with_all_ints( \@intids );
            $rv->{allcount} //= 0;  # scalar(undef) isn't zero
        } else {
            # we just did the full search; count the existing list
            $rv->{allcount} ||= scalar @uids;
        }

        # limit results to 500 most recently updated journals
        if ( scalar @uids > 500 ) {
            my $dbr = LJ::get_db_reader();
            my $qs = join ',', map { '?' } @uids;
            my $uref = $dbr->selectall_arrayref(
                "SELECT userid FROM userusage WHERE userid IN ($qs)
                 ORDER BY timeupdate DESC LIMIT 500", undef, @uids );
            die $dbr->errstr if $dbr->err;
            @uids = map { $_->[0] } @$uref;
        }

        my $us = LJ::load_userids( @uids );

        # prepare to filter and sort the results into @ul

        my $typefilter = sub {
            $rv->{comm_count}++ if $_[0]->is_community;
            return 1 if $type eq 'none';
            return 1 if $type eq 'F';  # already filtered
            return $_[0]->journaltype eq $type;
        };

        my $should_show = sub {
            return $_[0]->should_show_in_search_results( for => $remote );
        };

        my $updated = LJ::get_timeupdate_multi( keys %$us );
        my $def_upd = sub { $updated->{$_[0]->userid} || 0 };
        # let undefined values be zero for sorting purposes

        my @ul = sort { $def_upd->($b) <=> $def_upd->($a) || $a->user cmp $b->user }
                 grep { $_ && $typefilter->( $_ ) && $should_show->( $_ ) }
                 values %$us;
        $rv->{type_count} = scalar @ul if $rv->{allcount} != scalar @ul;
        $rv->{comm_count} = 1 if $type_opts->{nocomms};  # doesn't count

        if ( @ul ) {
            # pagination
            my $curpage = $args->{page} || 1;
            my %items = LJ::paging( \@ul, $curpage, 30 );
            my @data;

            # subset of users to display on this page
            foreach my $u ( @{ $items{items} } ) {
                my $desc = LJ::ehtml( $u->prop( 'journaltitle' ) );
                my $label = LJ::Lang::ml( 'search.user.journaltitle' );

                # community promo desc overrides journal title
                if ( $u->is_comm && LJ::is_enabled( 'community_themes' ) &&
                        ( my $prop_theme = $u->prop( "comm_theme" ) ) ) {
                    $label = LJ::Lang::ml( 'search.user.commdesc' );
                    $desc = LJ::ehtml( $prop_theme );
                }

                my $userpic = $u->userpic;
                $userpic = $userpic ? $userpic->imgtag_lite : '';

                my $updated = $updated->{$u->id}
                            ? LJ::diff_ago_text( $updated->{$u->id} )
                            : undef;
                push @data, { u => $u, updated => $updated, icon => $userpic,
                              desc => $desc, desclabel => $label };
            }

            $rv->{navbar} = LJ::paging_bar( $items{page}, $items{pages} );
            $rv->{data} = \@data;
        }

        return DW::Template->render_template( 'interests/int.tt', $rv );
    }


    # if we got to this point, we need to render the default template
    return DW::Template->render_template( 'interests/index.tt', $rv );
}


1;
