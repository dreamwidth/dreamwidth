#!/usr/bin/perl
#
# DW::Controller::Tools
#
#
# Authors:
#      RSH <ruth.s.hatch@gmail.com
#
# Copyright (c) 2009-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Tools;
use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::BetaFeatures;

DW::Routing->register_string( '/tools/comment_crosslinks',           \&crosslinks_handler,         app  => 1 );

sub crosslinks_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $u             = $rv->{u};

	my $dbcr = LJ::get_cluster_reader($u) or die;

	my $props = $dbcr->selectall_arrayref(
		q{
select
    l.jitemid * 256 + l.anum as 'ditemid',
    t.jtalkid * 256 + l.anum as 'dtalkid',
    tp.value
from
    log2 l
       inner join talk2 t on (t.journalid = l.journalid and l.jitemid = t.nodeid and t.nodetype = 'L')
       inner join talkprop2 tp on (tp.journalid = t.journalid and t.jtalkid = tp.jtalkid)
where
    tp.tpropid = 13 and tp.journalid = ?
		}, undef, $u->id );

	my $base = $u->journal_base;

    my $vars = { 'base' => $base, 'props' => $props, 'authas_html' => $rv->{authas_html}  };
    return DW::Template->render_template( 'tools/comment_crosslinks.tt', $vars );
}


1;