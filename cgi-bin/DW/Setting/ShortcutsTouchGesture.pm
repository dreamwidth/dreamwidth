#!/usr/bin/perl
#
# DW::Setting::ShortcutsTouchGesture
#
# Base module for touch gestures
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ShortcutsTouchGesture;
use base 'LJ::Setting';
use strict;
use warnings;

sub error_check {
    my ($class, $u, $args) = @_;
    my $event = $class->get_arg( $args, $class->prop_key . "event" );
    my $finger = $class->get_arg( $args, $class->prop_key . "finger" );
    my $direction = $class->get_arg( $args, $class->prop_key . "direction" );

    my @event_options = $class->event_options;
    my @finger_options = $class->finger_options;
    my @direction_options = $class->direction_options;
    unless ( grep /^$event$/,  @event_options ) {
        $class->errors( $class->prop_key => "Invalid event" );
    }
    unless ( grep /^$finger$/, @finger_options) {
        $class->errors( $class->prop_key => "Invalid finger count" );
    }
    unless ( grep /^$direction$/, @direction_options ) {
        $class->errors( $class->prop_key => "Invalid direction" );
    }
    
    return 1;
}

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub event_options {
    my $class = shift;
    return (
        "swipe"  => $class->ml( 'setting.shortcuts_touch.option.select.swipe' ),
        "disabled" => $class->ml( 'setting.shortcuts_touch.option.select.disabled' )
        );
}

sub finger_options  {
    my $class = shift;
    
    return (
        "1"  => $class->ml( 'setting.shortcuts_touch.option.select.finger.1' ),
        "2" => $class->ml( 'setting.shortcuts_touch.option.select.finger.2' ),
        );
}

sub direction_options {
    my $class = shift;
    return (
        "up"  => $class->ml( 'setting.shortcuts_touch.option.select.direction.up' ),
        "down"  => $class->ml( 'setting.shortcuts_touch.option.select.direction.down' ),
        "left"  => $class->ml( 'setting.shortcuts_touch.option.select.direction.left' ),
        "right"  => $class->ml( 'setting.shortcuts_touch.option.select.direction.right' ),
        );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $curval = $class->get_arg( $args, $class->prop_key ) || $u->prop( $class->prop_name );

    my $event = "swipe";
    my $finger = "2";
    my $direction = "up";

    if ( $curval ) {
        ( $event, $finger, $direction ) = split ( ",", $curval );
    }
    
    my @event_options = $class->event_options;

    my @finger_options = $class->finger_options;

    my @direction_options = $class->direction_options;
    
    my $ret;

    $ret .= LJ::html_select( {
        name => "${key}" . $class->prop_key . "event",
        id => "${key}" . $class->prop_key . "event",
        selected => $event,
    }, @event_options );
    

    $ret .= LJ::html_select( {
        name => "${key}" . $class->prop_key . "finger",
        id => "${key}" . $class->prop_key . "finger",
        selected => $finger,
    }, @finger_options );
    
    $ret .= LJ::html_select( {
        name => "${key}" . $class->prop_key . "direction",
        id => "${key}" . $class->prop_key . "direction",
        selected => $direction,
    }, @direction_options );
    
    my $errdiv = $class->errdiv( $errs, $class->prop_key );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $event = $class->get_arg( $args, $class->prop_key . "event" );
    my $fingers = $class->get_arg( $args, $class->prop_key . "finger" );
    my $direction = $class->get_arg( $args, $class->prop_key . "direction" );
    my $val = $event . "," . $fingers . "," . $direction;
    $u->set_prop( $class->prop_name => $val );

    return 1;
}

1;
