#!/usr/bin/perl
#
# DW::Widget::AccountStatistics
#
# User's account statistics, similar to those on the profile page.
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

package DW::Widget::AccountStatistics;

use strict;
use base qw/ LJ::Widget /;
use DW::Template;
use LJ::Memories;

sub should_render { 1; }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $tags_count     = scalar keys %{ $remote->tags || {} };
    my $memories_count = LJ::Memories::count( $remote->id ) || 0;

    my $accttype = DW::Pay::get_account_type_name($remote);
    my $accttype_string;
    if ($accttype) {
        my $expire_time = DW::Pay::get_account_expiration_time($remote);
        $accttype_string =
            $expire_time > 0
            ? BML::ml( 'widget.accountstatistics.expires_on',
            { type => $accttype, date => DateTime->from_epoch( epoch => $expire_time )->date } )
            : $accttype;
    }
    my $vars = {
        remote          => $remote,
        commafy         => \&LJ::commafy,
        mysql_time      => \&LJ::mysql_time,
        tags_count      => $tags_count,
        memories_count  => $memories_count,
        accttype_string => $accttype_string
    };

    return DW::Template->template_string( 'widget/accountstatistics.tt', $vars );
}

1;

