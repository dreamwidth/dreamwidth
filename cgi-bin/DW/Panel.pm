#!/usr/bin/perl
#
# DW::Panel - Generic movable container which wraps around an object of
# class LJ::Widget, and remembers state and position.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Panel;

=head1 NAME

DW::Panel - Generic movable container which wraps around an object of 
class LJ::Widget, and remembers state and position.

=head1 SYNOPSIS

  use DW::Panel;

  my $panels = DW::Panel->init( u => $remote );  
  $panels->render_primary;
  $panels->render_secondary;

=cut

use strict;
use warnings;

use fields qw( primary secondary );

=head1 API

=head2 C<< $class->init( [ u => $u] ) >>
Class method; initializes the panels with their settings, etc, for this user.
=cut

sub init {
    my ( $class, %opts ) = @_;

    # my $dbh = LJ::get_db_reader();

    my $u = $opts{u} || LJ::get_remote();
    return unless $u;

    my $ret = fields::new($class);

    # TODO: store/retrieve user settings from database
    # possible settings: display or not, position, possibly per-widget config
    $ret->{primary} =
        [ "DW::Widget::LatestNews", "DW::Widget::QuickUpdate", "DW::Widget::LatestInbox", ];

    $ret->{secondary} = [
        "DW::Widget::SiteSearch",      "DW::Widget::ReadingList",
        "LJ::Widget::FriendBirthdays", "DW::Widget::AccountStatistics",
        "DW::Widget::UserTagCloud",    "DW::Widget::CommunityManagement",
        "LJ::Widget::CurrentTheme",
    ];

    return $ret;
}

=head2 C<< $object->render_primary >>
Render the widgets that belong in the primary column
=cut

sub render_primary {
    my $self = shift;

    my $ret;
    foreach my $widget ( @{ $self->{primary} } ) {
        $ret .= DW::Panel->_render($widget);
    }

    return $ret;
}

=head2 C<< $object->render_secondary >>
Render the widgets that belong in the secondary column
=cut

sub render_secondary {
    my $self = shift;

    my $ret;
    foreach my $widget ( @{ $self->{secondary} } ) {
        $ret .= DW::Panel->_render($widget);
    }

    return $ret;
}

=head2 C<< $object->_render( widgetname ) >>
Render the widget and its container.
=cut

sub _render {
    my ( $object, $widget ) = @_;

    eval "use $widget; 1" or return "";

    my $widget_body = $widget->render;
    return "" unless $widget_body;

    my $css_subclass = lc $widget->subclass;

    # TODO: this can contain the non-js controls to enable customization of display
    return "<div class='panel' id='panel-$css_subclass' >$widget_body</div>";
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
