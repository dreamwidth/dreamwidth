#!/usr/bin/perl
#
# DW::Widget::QuickUpdate
#
# Quick update form
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::QuickUpdate;

use strict;
use base qw/ LJ::Widget /;
use DW::Template;

sub need_res { qw( stc/css/pages/entry/new.css) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my @accounts = DW::External::Account->get_external_accounts($remote);
    @accounts = grep { $_->xpostbydefault } @accounts;

    my @journallist = ( $remote, $remote->posting_access_list );
    my $sidebar     = LJ::Hooks::run_hook( 'entryforminfo', $remote->user, $remote );
    my @security    = (
        "public"  => LJ::Lang::ml("/entry/form.tt.select.security.public.label"),
        "private" => LJ::Lang::ml("/entry/form.tt.select.security.private.label"),
        "access"  => LJ::Lang::ml("/entry/form.tt.select.security.access.label"),
    );
    my $vars = {
        remote      => $remote,
        journallist => \@journallist,
        security    => \@security,
        sidebar     => $sidebar,
        accounts    => \@accounts,

    };

    return DW::Template->template_string( 'widget/quickupdate.tt', $vars );
}

1;

