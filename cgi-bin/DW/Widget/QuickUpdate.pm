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

sub need_res { qw( stc/css/pages/entry/new.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my @accounts = DW::External::Account->get_external_accounts($remote);
    @accounts = grep { $_->xpostbydefault } @accounts;

    my @journallist = map {
        {
            value => $_->user,
            text  => $_->user,
            data  => { minsecurity => minsec_for_user($_), iscomm => 1 }
        }
    } $remote->posting_access_list;

    my $journal_minsec = $remote && $remote->prop('newpost_minsecurity');

#FIXME: this is because the setting can be the old 'friends' level from LJ. If we ever fix that, this can be removed.
    $journal_minsec = 'access' if $journal_minsec =~ 'friends';

    push @journallist,
        {
        value => $remote->{'user'},
        text  => $remote->{'user'},
        data  => { minsecurity => $journal_minsec, iscomm => 0 }
        };
    @journallist = sort { $a->{'value'} cmp $b->{'value'} } @journallist;

    my $sidebar  = LJ::Hooks::run_hook( 'entryforminfo', $remote->user, $remote );
    my @security = (
        { value => "public", text => LJ::Lang::ml("/entry/form.tt.select.security.public.label") },
        {
            value => "access",
            text  => LJ::Lang::ml("/entry/form.tt.select.security.access.label"),
            data  => { commlabel => LJ::Lang::ml("/entry/form.tt.select.security.members.label") }
        },
        {
            value => "private",
            text  => LJ::Lang::ml("/entry/form.tt.select.security.private.label"),
            data  => { commlabel => LJ::Lang::ml("/entry/form.tt.select.security.admin.label") }
        },
    );

    my $vars = {
        remote      => $remote,
        journallist => \@journallist,
        security    => \@security,
        sidebar     => $sidebar,
        accounts    => \@accounts,
        minsec      => $journal_minsec,

    };

    return DW::Template->template_string( 'widget/quickupdate.tt', $vars );
}

sub minsec_for_user {
    my $user = LJ::load_user(shift);
    if ( !$user ) {
        return undef;
    }
    return $user->prop('newpost_minsecurity');
}

1;

