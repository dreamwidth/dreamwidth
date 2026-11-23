#!/usr/bin/perl
#
# DW::Captcha::hCaptcha
#
# This module handles integration with the hCaptcha service
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

=head1 NAME

DW::Captcha::hCaptcha - This module handles integration with the hCaptcha service

=head1 SYNOPSIS

=cut

use strict;

package DW::Captcha::hCaptcha;

use LJ::JSON;
use LWP::UserAgent;

# avoid base pragma - causes circular requirements
require DW::Captcha;
our @ISA = qw( DW::Captcha );

# implemented as overrides for the base class

# class methods
sub name { return "hcaptcha" }

# object methods
sub form_fields { qw( h-captcha-response ) }

sub _implementation_enabled {
    return
           LJ::is_enabled( 'captcha', 'hcaptcha' )
        && $LJ::CAPTCHA_HCAPTCHA_SITEKEY
        && $LJ::CAPTCHA_HCAPTCHA_SECRET ? 1 : 0;
}

sub _print {
    my $sitekey = LJ::ehtml($LJ::CAPTCHA_HCAPTCHA_SITEKEY);
    return qq{<script src="https://js.hcaptcha.com/1/api.js" async defer></script>}
        . qq{<div class="h-captcha" data-sitekey="$sitekey"></div>};
}

sub _validate {
    my $self     = $_[0];
    my $response = $self->response
        or return 0;

    # Hit up hCaptcha and ask nicely if this response is any good
    my $ua = LWP::UserAgent->new;
    $ua->agent('Dreamwidth Captcha API <accounts@dreamwidth.org>');

    my $res = $ua->post(
        'https://hcaptcha.com/siteverify',
        {
            response => $response,
            secret   => $LJ::CAPTCHA_HCAPTCHA_SECRET,
            sitekey  => $LJ::CAPTCHA_HCAPTCHA_SITEKEY,
            remoteip => LJ::get_remote_ip(),
        },
    );
    return 0 unless $res->is_success;

    my $obj = eval { from_json( $res->decoded_content ) };
    return $obj && $obj->{success} ? 1 : 0;
}

sub _init_opts {
    my ( $self, %opts ) = @_;

    # Parent class checks for a challenge, but hCaptcha doesn't use this field
    $self->{challenge} = 1;
    $self->{response} ||= $opts{'h-captcha-response'};
}

1;
