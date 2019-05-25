#!/usr/bin/perl
#
# LJ::Setting::NCTalkLinks
#
# LJ::Setting module for choosing whether or not to add ?nc=XX to the
# end of entry links, forcing the link color back to unread if the
# comment count changes.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# The original version of this program was authored by LiveJournal.com
# and distributed under the terms of the license supplied by LiveJournal Inc,
# which can be found at:
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# This program has since been wholly rewritten by Dreamwidth Studios.
# No parent code remains.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Setting::NCTalkLinks;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub label {
    my $class = shift;
    return $class->ml('setting.nctalklinks.header');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;

    my $nctalklinks = $class->get_arg( $args, "nctalklinks" ) || $u->opt_nctalklinks;

    my $ret = LJ::html_check(
        {
            name     => "${key}nctalklinks",
            id       => "${key}nctalklinks",
            value    => 1,
            selected => $nctalklinks ? 1 : 0,
        }
    );
    $ret .=
        " <label for='${key}nctalklinks'>" . $class->ml('setting.nctalklinks.option') . "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $value = $class->get_arg( $args, "nctalklinks" ) ? "1" : "0";
    $u->opt_nctalklinks($value);

    return 1;
}

1;
