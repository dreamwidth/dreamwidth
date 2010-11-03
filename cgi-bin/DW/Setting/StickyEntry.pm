#!/usr/bin/perl
#
# DW::Setting::StickyEntry - set which entry should be used as a sticky entry on top of the journal
#
# Authors:
#      Rebecca Freiburg <beckyvi@gmail.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Setting::StickyEntry;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    $_[1] ? 1 : 0;
}

sub label {
    $_[0]->ml( 'setting.stickyentry.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    $ret .= LJ::html_text({
        name  => "${key}stickyid",
        id    => "${key}stickyid",
        class => "text",
        value => $errs ? $class->get_arg( $args, "stickyid" ) : $u->sticky_entry,
        size  => 30,
        maxlength => 100,
    });

    my $errdiv = $class->errdiv( $errs, "stickyid" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $sticky = $class->get_arg( $args, "stickyid" ) || '';
    $sticky = LJ::text_trim( $sticky, 0, 100 );
    unless ( $u->sticky_entry ( $sticky ) ) {
        $class->errors( "stickyid" => $class->ml( 'setting.stickyentry.error.invalid' ) ) ;
    }
    return 1;
}


1;
