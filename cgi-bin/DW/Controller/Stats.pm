#!/usr/bin/perl
#
# DW::Controller::Stats
#
# This controller concerns basic site account statistics.
# The newer, more business-related stats are in SiteStats.pm.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Stats;

use strict;

use DW::Routing;
use DW::Controller;
use DW::Template;

use DW::Countries;

DW::Routing->register_string( '/stats', \&main_handler, app => 1 );

sub main_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $scope = "/stats/main.tt";

    my $dbr = LJ::get_db_reader();
    my $sth;
    my %stat;

    {    # start with basic stat categories, bail out if we don't have these

        $sth = $dbr->prepare(
            "SELECT statcat, statkey, statval FROM stats WHERE statcat IN
             ('userinfo', 'client', 'age', 'gender', 'account', 'size')"
        );
        $sth->execute;
        while ( $_ = $sth->fetchrow_hashref ) {
            $stat{ $_->{'statcat'} }->{ $_->{'statkey'} } = $_->{'statval'};
        }

        return error_ml("$scope.error.nostats") unless %stat;
    }

    my @countries;
    my @states;

    {    # load country and state stats

        my %countries;
        DW::Countries->load( \%countries );
        $sth = $dbr->prepare(
            "SELECT statkey, statval FROM stats WHERE statcat='country'
            ORDER BY statval DESC LIMIT 15"
        );
        $sth->execute;
        while ( my $row = $sth->fetchrow_hashref ) {
            $stat{'country'}->{ $countries{ $row->{statkey} } } = $row->{statval};
        }

        @countries = sort { $stat{'country'}->{$b} <=> $stat{'country'}->{$a} }
            keys %{ $stat{'country'} };

        $sth = $dbr->prepare(
            "SELECT c.item, s.statval FROM stats s, codes c
            WHERE c.type='state' AND s.statcat='stateus' AND s.statkey=c.code
            ORDER BY s.statval DESC LIMIT 15"
        );
        $sth->execute;
        while ( $_ = $sth->fetchrow_hashref ) {
            $stat{'state'}->{ $_->{'item'} } = $_->{'statval'};
        }

        @states = sort { $stat{'state'}->{$b} <=> $stat{'state'}->{$a} }
            keys %{ $stat{'state'} };
    }

    my %accounts_updated = ( P => [], C => [], Y => [] );
    my %accounts_created = ( P => [], C => [], Y => [] );

    {    # load recent usage stats for various account types

        if ( LJ::is_enabled('stats-recentupdates') ) {

            $sth = $dbr->prepare(
                "SELECT u.userid, uu.timeupdate FROM user u, userusage uu WHERE
                u.userid=uu.userid AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 30 DAY)
                AND u.journaltype = ? ORDER BY uu.timeupdate DESC LIMIT 20"
            );

            $sth->execute('P');
            $accounts_updated{P} = $sth->fetchall_arrayref( {} );

            $sth->execute('C');
            $accounts_updated{C} = $sth->fetchall_arrayref( {} );

            $sth->execute('Y');
            $accounts_updated{Y} = $sth->fetchall_arrayref( {} );
        }

        if ( LJ::is_enabled('stats-newjournals') ) {

            $sth = $dbr->prepare(
                "SELECT u.userid, uu.timeupdate FROM user u, userusage uu WHERE
                u.userid=uu.userid AND uu.timeupdate IS NOT NULL AND u.journaltype = ?
                AND u.statusvis != 'S' ORDER BY uu.timecreate DESC LIMIT 20"
            );

            $sth->execute('P');
            $accounts_created{P} = $sth->fetchall_arrayref( {} );

            $sth->execute('C');
            $accounts_created{C} = $sth->fetchall_arrayref( {} );

            $sth->execute('Y');
            $accounts_created{Y} = $sth->fetchall_arrayref( {} );
        }
    }

    my @uids;

    foreach my $a ( values(%accounts_created), values(%accounts_updated) ) {
        push @uids, map { $_->{userid} } @$a;
    }

    my %age;
    my $maxage = 1;

    {    # do math for age-related bar graphs

        my $lowage  = 13;
        my $highage = 119;    # given db floor of 1890 (as of 2009)

        foreach my $key ( keys %{ $stat{'age'} } ) {
            next if $key < $lowage;
            next if $key > $highage;
            $age{$key} = $stat{'age'}->{$key};
            $maxage = $age{$key} if $age{$key} > $maxage;
        }
    }

    my @client_list;
    my %client_details;

    {    # format client data (if enabled)

        if ( LJ::is_enabled('clientversionlog') ) {

            ### sum up clients over different versions
            foreach my $c ( keys %{ $stat{'client'} } ) {
                next unless $c =~ /^(.+?)\//;
                $stat{'clientname'}->{$1} += $stat{'client'}->{$c};
            }

            foreach my $cn (
                sort { $stat{'clientname'}->{$b} <=> $stat{'clientname'}->{$a} }
                keys %{ $stat{'clientname'} }
                )
            {
                last unless $stat{'clientname'}->{$cn} >= 50;
                push @client_list, $cn;

                my @client_versions;

                foreach my $c ( sort grep { /^\Q$cn\E\// } keys %{ $stat{'client'} } ) {
                    my $count = $stat{'client'}->{$c};
                    $c =~ s/^\Q$cn\E\///;
                    push @client_versions, LJ::ehtml($c) . " ($count)";
                }

                $client_details{$cn} = join ", ", @client_versions;
            }
        }
    }

    my %graphs = ( newbyday => 'stats/newbyday.png' );

    my $vars = {
        stat             => \%stat,
        countries        => \@countries,
        states           => \@states,
        accounts_updated => \%accounts_updated,
        accounts_created => \%accounts_created,
        userobj_for      => LJ::load_userids(@uids),
        age              => \%age,
        client_list      => \@client_list,
        client_details   => \%client_details,
        graphs           => \%graphs,
        default_zero     => sub { $_[0] && $_[0] ne '' ? $_[0] + 0 : 0 },
        percentage       => sub { sprintf( "%0.1f", $_[0] * 100 / $_[1] ) },
        scale_bar        => sub { int( 400 * $_[0] / $maxage ) },
    };

    return DW::Template->render_template( 'stats/main.tt', $vars );
}

1;
