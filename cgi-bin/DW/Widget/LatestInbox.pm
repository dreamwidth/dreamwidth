#!/usr/bin/perl
#
# DW::Widget::LatestInbox
#
# Latest inbox messages
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

package DW::Widget::LatestInbox;

use strict;
use base qw/ LJ::Widget /;

sub need_res {
    qw( stc/widgets/latestinbox.css );
}

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return "";
    my $vars = { limit => $opts{limit} || 5 };

    # get the user's inbox
    my $error;
    my $inbox = $remote->notification_inbox
        or $error = LJ::error_list(
        $class->ml( 'inbox.error.couldnt_retrieve_inbox', { 'user' => $remote->{user} } ) );

    if ($error) {
        $vars->{error} = $error;
    }
    else {
        my @inbox_items = reverse $inbox->all_items;
        $vars->{inbox_items} = \@inbox_items;
    }

    my $ret = DW::Template->template_string( 'widget/latestinbox.tt', $vars );
    LJ::warn_for_perl_utf8($ret);
    return $ret;
}

1;

