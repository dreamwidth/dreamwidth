#!/usr/bin/perl
#
# DW::Setting::ProfileEmail
#
# LJ::Setting module for specifying a displayed email.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ProfileEmail;
use base 'LJ::Setting';
use strict;
use warnings;
use LJ::Global::Constants;

sub should_render {
    my ( $class, $u ) = @_;
    return 1;
}

sub label {
    my $class = shift;
    return $class->ml( 'setting.profileemail.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    $ret .= LJ::html_text({
        name      => "${key}email",
        id        => "${key}email",
        class     => "text",
        value     => $errs ? $class->get_arg( $args, "email" ) : $u->profile_email,
        size      => 70,
        maxlength => 255,
    });

    my $errdiv = $class->errdiv( $errs, "email" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $email = $class->get_arg( $args, "email" );
    $email = LJ::trim( $email || "" );

    # ensure a valid email address is given.
    my @errors;
    if ( $email ) {
        # force_spelling because /manage/profile can't present unsaved edits
        # back to you (nor hold them out of sight), so there's no opportunity
        # to show an override checkbox
        LJ::check_email( $email, \@errors, { force_spelling => 1 } );
    }

    if ( @errors ) {
        $class->errors( "email" => join( '<br />', @errors ) ) ;
    } else {
        $u->profile_email( $email );
    }

    return 1;
}

1;
