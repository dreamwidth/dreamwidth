#!/usr/bin/perl
#
# DW::Captcha
#
# This module handles CAPTCHA throughout the site
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

=head1 NAME

DW::Captcha - This module handles CAPTCHA throughout the site

=head1 SYNOPSIS

=cut

use strict;
use warnings;
package DW::Captcha;

# at some point we may replace this, or try to make this implementation more flexible
# right now, let's just go with this

BEGIN {
    my $rv = eval <<USE;
use Captcha::reCAPTCHA;
1;
USE
    warn "NOTE: Captcha::reCAPTCHA was not found.\n"
        unless $rv;

    our $MODULES_INSTALLED = $rv;
}

# class methods
sub new {
    my ( $class, $type, %opts ) = @_;

    my $self = bless {
        type => $type,
    }, $class;

    $self->init_opts( %opts );

    return $self;
}

sub form_fields { qw( recaptcha_response_field recaptcha_challenge_field ) }
sub public_key  { LJ::conf_test( $LJ::RECAPTCHA{public_key} ) }
sub private_key { LJ::conf_test( $LJ::RECAPTCHA{private_key} ) }

sub site_enabled {
    return 0 unless $DW::Captcha::MODULES_INSTALLED;
    return LJ::is_enabled( 'recaptcha' ) && $LJ::RECAPTCHA{public_key} && $LJ::RECAPTCHA{private_key};
}

# object methods
sub print {
    my $self = $_[0];
    return "" unless $self->enabled;

    my $captcha = Captcha::reCAPTCHA->new;
    my $ret = $captcha->get_options_setter( { theme => 'white' } );

    $ret .= "<div class='captcha'>";

    $ret .= $captcha->get_html(
        public_key(),               # public key
        '',                         # error (optional)
        $LJ::IS_SSL                 # page uses ssl
    );

    $ret .= "<p>" . BML::ml( 'captcha.accessibility.contact', { email => $LJ::SUPPORT_EMAIL } ) . "</p>";
    $ret .= "</div>";

    return $ret;
}

sub validate { 
    my ( $self, %opts ) = @_;
    return unless $self->enabled;

    $self->init_opts( %opts );

    my $err_ref = $opts{err_ref};
    my $result;

    if ( $self->challenge ) {
        my $captcha = Captcha::reCAPTCHA->new;
        $result = $captcha->check_answer(
            private_key(), $ENV{REMOTE_ADDR},
            $self->challenge, $self->response
        );

       return 1 if $result->{is_valid} eq '1';
    }

    $$err_ref = LJ::Lang::ml( 'captcha.invalid' );

    return 0;
}

# enabled can be used as either a class or an object method
sub enabled {

    my $type = ref $_[0] ? $_[0]->type : $_[1];

    return $type
        ? site_enabled() && $LJ::CAPTCHA_FOR{$type}
        : site_enabled();
}

sub init_opts {
    my ( $self, %opts ) = @_;

    $self->{challenge} ||= $opts{recaptcha_challenge_field};
    $self->{response} ||= $opts{recaptcha_response_field};
}

sub type      { return $_[0]->{type} }
sub challenge { return $_[0]->{challenge} }
sub response  { return $_[0]->{response} }

1;
