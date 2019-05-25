#!/usr/bin/perl
#
# DW::Captcha::reCAPTCHA
#
# This module handles integration with the reCAPTCHA service
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

=head1 NAME

DW::Captcha::reCAPTCHA - This module handles integration with the reCAPTCHA service

=head1 SYNOPSIS

=cut

use strict;

package DW::Captcha::reCAPTCHA;

# avoid base pragma - causes circular requirements
require DW::Captcha;
our @ISA = qw( DW::Captcha );

BEGIN {
    my $rv = eval <<USE;
use Captcha::reCAPTCHA;
1;
USE
    warn "NOTE: Captcha::reCAPTCHA was not found.\n"
        unless $rv;

    our $MODULES_INSTALLED = $rv;
}

# implemented as overrides for the base class

# class methods
sub name { return "recaptcha" }

# object methods
sub form_fields { qw( recaptcha_response_field recaptcha_challenge_field ) }

sub _implementation_enabled {
    return 0 unless $DW::Captcha::reCAPTCHA::MODULES_INSTALLED;
    return LJ::is_enabled( 'captcha', 'recaptcha' ) && _public_key() && _private_key() ? 1 : 0;
}

sub _print {
    my $captcha = Captcha::reCAPTCHA->new;
    return $captcha->get_options_setter( { theme => 'white' } ) . $captcha->get_html(
        _public_key(),    # public key
        '',               # error (optional)
        $LJ::IS_SSL       # page uses ssl
    );
}

sub _validate {
    my $self = $_[0];

    my $captcha = Captcha::reCAPTCHA->new;
    my $result  = $captcha->check_answer( _private_key(), $ENV{REMOTE_ADDR},
        $self->challenge, $self->response );

    return 1 if $result->{is_valid} eq '1';
}

sub _init_opts {
    my ( $self, %opts ) = @_;

    $self->{challenge} ||= $opts{recaptcha_challenge_field};
    $self->{response}  ||= $opts{recaptcha_response_field};
}

# recaptcha-specific methods
sub _public_key  { LJ::conf_test( $LJ::RECAPTCHA{public_key} ) }
sub _private_key { LJ::conf_test( $LJ::RECAPTCHA{private_key} ) }

1;
