#!/usr/bin/perl
#
# DW::Request::Base
#
# Methods that are the same over most or all DW::Request modules
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Base;

use strict;
use Carp qw/ confess cluck /;
use CGI::Cookie;

use fields (
            'cookies_in',
        );

sub new {
    my $self = $_[0];
    confess "This is a base class, you can't use it directly."
        unless ref $self;

    $self->{cookies_in} = undef;
}

sub cookie {
    my DW::Request::Base $self = $_[0];

    $self->{cookies_in} ||= { CGI::Cookie->parse( $self->header_in( 'Cookie' ) ) };
    return unless exists $self->{cookies_in}->{$_[1]};
    return $self->{cookies_in}->{$_[1]}->value;
}

sub add_cookie {
    my DW::Request::Base $self = shift;
    my %args = ( @_ );

    confess "Must provide name" unless $args{name};
    confess "Must provide value (try delete_cookie if you really mean this)" unless exists $args{value};

    $args{domain} ||= ".$LJ::DOMAIN";

    # extraneous parenthesis inside map {} needed to force BLOCK mode map
    my $cookie = CGI::Cookie->new( map { ( "-$_" => $args{$_} ) } keys %args );
    $self->err_header_out_add( 'Set-Cookie' => $cookie );
    return $cookie;
}

sub delete_cookie {
    my DW::Request::Base $self = shift;
    my %args = ( @_ );

    confess "Must provide name" unless $args{name};

    $args{value}    = '';
    $args{expires}  = "-1d";
    $args{domain} ||= ".$LJ::DOMAIN";

    return $self->add_cookie( %args );
}

1;
