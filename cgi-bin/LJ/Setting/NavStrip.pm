#!/usr/bin/perl
#
# LJ::Setting::NavStrip - Settings for navigation strip display
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Setting::NavStrip;
use base 'LJ::Setting';
use strict;
use warnings;

=head1 NAME

LJ::Setting::NavStrip - Settings for navigation strip display

=head1 SYNOPSIS

  Add it to the proper category under /manage/settings/index.bml

=cut

sub should_render {
    my ( $class, $u ) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    return "navstrip";
}

sub label {
    my $class = shift;

    return $class->ml('setting.navstrip.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my @pageoptions = LJ::Hooks::run_hook('page_control_strip_options');
    return undef unless @pageoptions;

    my %pagemask = map { $pageoptions[$_] => 1 << $_ } 0 .. $#pageoptions;

    # choose where to display/see it

    my $val = $class->get_arg( $args, "navstrip" );
    my $navstrip;
    $navstrip |= $_ + 0 foreach split( /\0/, $val );

    my $display = $navstrip || $u->control_strip_display;

    my $ret = $class->ml('setting.navstrip.option');
    foreach my $pageoption (@pageoptions) {
        my $for_html = $pageoption;
        $for_html =~ tr/\./_/;

        $ret .= LJ::html_check(
            {
                name     => "${key}navstrip",
                id       => "${key}navstrip_${for_html}",
                selected => $display & $pagemask{$pageoption} ? 1 : 0,
                value    => $pagemask{$pageoption},
            }
        );

        $ret .=
              " <label for='${key}navstrip_${for_html}'>"
            . $class->ml("setting.navstrip.option.$pageoption")
            . "</label>";
    }

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "navstrip" );

    my $navstrip;
    $navstrip |= $_ + 0 foreach split( /\0/, $val );
    $navstrip ||= 'none';

    $u->set_prop( control_strip_display => $navstrip );

    return 1;
}

=head1 BUGS

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;

