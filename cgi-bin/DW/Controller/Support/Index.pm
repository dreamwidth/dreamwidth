#!/usr/bin/perl
#
# DW::Controller::Support::Index
#
# This controller is for the Support Index page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Index;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/index', \&index_handler, app => 1 );

sub index_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    my $vars = {};
    
    my $currentproblems = LJ::load_include( "support-currentproblems" );
    LJ::CleanHTML::clean_event( \$currentproblems, {} );    
    $vars->{currentproblems} = $currentproblems;
    
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
    my $sth = $dbr->prepare( "SELECT statkey FROM stats WHERE statcat='pop_faq' ORDER BY statval DESC LIMIT 10" );
    $sth->execute;    

    while ( my $f = $sth->fetchrow_hashref ) {
        $f = LJ::Faq->load( $f->{statkey}, lang => LJ::Lang::get_effective_lang() );
        $f->render_in_place( {user => $user, url => $user_url} );
        my $q = $f->question_html;
        push @{ $vars->{f} }, {
            q => $q,
            faqid => $f->faqid
        };
    }
   
    return DW::Template->render_template( 'support/index.tt', $vars );
    
}
    
1;
