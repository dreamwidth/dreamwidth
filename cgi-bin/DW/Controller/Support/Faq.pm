#!/usr/bin/perl
#
# DW::Controller::Support::Faq
#
# This controller is for the Support FAQ page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Faq;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/faq', \&faq_handler, app => 1 );
DW::Routing->register_string( '/support/faqpop', \&faqpop_handler, app => 1 );

sub faq_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    my $vars = {};
    
    my $dbr = LJ::get_db_reader(); 
    my $sth;
    my %faqcat; 
    my %faqq;
    my $ret = "";    
    
    $sth = $dbr->prepare( "SELECT faqcat, faqcatname, catorder FROM faqcat ".
                         "WHERE faqcat<>'int-abuse'" );

    $sth->execute;                         
                         
    while ( $_ = $sth->fetchrow_hashref ) {
        $faqcat{$_->{faqcat}} = $_;
    }    
    
    # Get remote username and journal URL, or example user's username and journal URL
    if ( $remote ) {
        $user = $remote->user;
        $user_url = $remote->journal_base;
    } else {
        my $u = LJ::load_user( $LJ::EXAMPLE_USER_ACCOUNT );
        $user = $u ? $u->user : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    foreach my $f ( LJ::Faq->load_all ) {
        $f->render_in_place( {user => $user, url => $user_url} );
        $faqq{$f->faqid} = $f;
    }
    
    foreach my $faqcat ( sort { $faqcat{$a}->{catorder} <=>
                                $faqcat{$b}->{catorder} } keys %faqcat )
    {
        my $countfaqs = 0;
        foreach ( grep { $faqq{$_}->faqcat eq $faqcat } keys %faqq ) {
            $countfaqs++;
        }
        next unless $countfaqs;
        push @{ $vars->{faqcats} }, {
            faqcat => $faqcat, 
            faqcatname => $faqcat{$faqcat}->{faqcatname},
        };          
        foreach my $faqid ( sort { $faqq{$a}->sortorder <=> $faqq{$b}->sortorder } grep { $faqq{$_}->faqcat eq $faqcat } keys %faqq )
        {
            my $q = $faqq{$faqid}->question_html;
            next unless $q;
            $q =~ s/^\s+//; $q =~ s/\s+$//;
            $q =~ s!\n!<br />!g;
            push @{ $vars->{questions}->{$faqcat}->{faqqs} }, {
                q => $q,
                faqid => $faqid };
        }
    }
    
    return DW::Template->render_template( 'support/faq.tt', $vars );

}

sub faqpop_handler {
    my $r = DW::Request->get;
    my $get = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;
    
    my $vars = {};    

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    # Get remote username and journal URL, or example user's username and journal URL
    if ( $remote ) {
        $user = $remote->user;
        $user_url = $remote->journal_base;
    } else {
        my $u = LJ::load_user( $LJ::EXAMPLE_USER_ACCOUNT );
        $user = $u ? $u->user : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare( "SELECT statkey, statval FROM stats WHERE statcat='pop_faq' ORDER BY statval DESC LIMIT 50" );
    $sth->execute;

    while (my $s = $sth->fetchrow_hashref) {
        my $f = LJ::Faq->load( $s->{statkey} );
        $f->render_in_place( {user => $user, url => $user_url} );
        my $q = $f->question_html;
        $q =~ s/^\s+//; 
        $q =~ s/\s+$//;
        $q =~ s!\n!<br />!g;
        push @{ $vars->{faqs} }, {
            question => $q,
            statval => $s->{statval},
            faqid => $f->faqid
        };
    }

    return DW::Template->render_template( 'support/faqpop.tt', $vars );

}

1;
