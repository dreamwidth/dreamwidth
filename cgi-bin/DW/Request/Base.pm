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
use CGI::Util qw( unescape );

use fields (
            'cookies_in',
            'cookies_in_multi',

            'get_args',
        );

sub new {
    my $self = $_[0];
    confess "This is a base class, you can't use it directly."
        unless ref $self;

    $self->{cookies_in} = undef;
    $self->{cookies_in_multi} = undef;

    $self->{get_args} = undef;
}

sub cookie {
    my DW::Request::Base $self = $_[0];

    $self->parse( $self->header_in( 'Cookie' ) ) unless defined $self->{cookies_in};
    my $val = $self->{cookies_in}->{$_[1]} || [];
    return wantarray ? @$val : $val->[0];
}

sub cookie_multi {
    my DW::Request::Base $self = $_[0];

    $self->parse( $self->header_in( 'Cookie' ) ) unless defined $self->{cookies_in_multi};
    return @{ $self->{cookies_in_multi}->{$_[1]} || [] };
}

sub add_cookie {
    my DW::Request::Base $self = shift;
    my %args = ( @_ );

    confess "Must provide name" unless $args{name};
    confess "Must provide value (try delete_cookie if you really mean this)" unless exists $args{value};

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

    return $self->add_cookie( %args );
}

# FIXME: This relies on the behavior parse_args
#   and the \0 seperated arguments. This should be cleaned
#   up at the same point parse_args is.
sub _string_to_multivalue {
    my %gets = LJ::parse_args( $_[1] );

    my @out;
    foreach my $key ( keys %gets ) {
        my @parts = split(/\0/, $gets{$key});
        push @out, map { $key => $_ } @parts;
    }

    return Hash::MultiValue->new( @out );
}

sub get_args {
    my DW::Request $self = $_[0];
    return $self->{get_args} if defined $self->{get_args};

    return $self->{get_args} =
        $self->_string_to_multivalue( $self->query_string );
}

#
# Following sub was copied from CGI::Cookie and modified.
#
# Copyright 1995-1999, Lincoln D. Stein.  All rights reserved.
# It may be used and modified freely, but I do request that this copyright
# notice remain attached to the file.  You may modify this module as you 
# wish, but if you redistribute a modified version, please attach a note
# listing the modifications you have made.
#
sub parse {
    my DW::Request::Base $self = $_[0];
    my %results;
    my %results_multi;

    my @pairs = split( "[;,] ?", defined $_[1] ? $_[1] : '' );
    foreach ( @pairs ) {
        $_ =~ s/\s*(.*?)\s*/$1/;
        my ( $key, $value ) = split( "=", $_, 2 );
        
        # Some foreign cookies are not in name=value format, so ignore
        # them.
        next unless defined( $value );
        my @values = ();
        if ( $value ne '' ) {
          @values = map unescape( $_ ), split( /[&;]/, $value . '&dmy' );
          pop @values;
        }
        $key = unescape( $key );
        $results{$key} ||= \@values;
        push @{ $results_multi{$key} }, \@values;
    }

    $self->{cookies_in} = \%results;
    $self->{cookies_in_multi} = \%results_multi;
}

1;
