#!/usr/bin/perl
#
# DW::Setting::EmailAlias
#
# LJ::Setting module for choosing whether or not to disable email
# forwarding via the site alias for a given user, as governed by the
# "no_mail_alias" user property.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::EmailAlias;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->can_have_email_alias;
}

sub label {
    my $class = shift;
    return $class->ml('setting.emailalias.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $emailalias = $class->get_arg( $args, "emailalias" ) || !$u->prop("no_mail_alias");

    my $ret = LJ::html_check(
        {
            name     => "${key}emailalias",
            id       => "${key}emailalias",
            value    => 1,
            selected => $emailalias ? 1 : 0,
        }
    );

    $ret .= " <label for='${key}emailalias'>";
    $ret .= $class->ml( 'setting.emailalias.option',
        { user => $u->username, domain => $LJ::USER_DOMAIN } );
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "emailalias" );
    $u->set_prop( "no_mail_alias" => !$val );

    # our selection value is the opposite of what no_mail_alias expects
    $val ? $u->update_email_alias : $u->delete_email_alias;

    return 1;
}

1;
