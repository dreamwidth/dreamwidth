#!/usr/bin/perl
#
# DW::Captcha::textCAPTCHA
#
# This module handles integration with the textCAPTCHA service
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

DW::Captcha::textCAPTCHA - This module handles integration with the textCAPTCHA service

=head1 SYNOPSIS

=cut

use strict;

package DW::Captcha::textCAPTCHA;
use base 'DW::Captcha';

use XML::Simple;
use Digest::MD5 ();


# implemented as overrides for the base class


# class methods
sub name { return "textcaptcha" }

# object methods
sub form_fields { qw( textcaptcha_challenge textcaptcha_response textcaptcha_response_noscript textcaptcha_chalauth ) }
sub _implementation_enabled {
    return LJ::is_enabled( 'captcha', 'textcaptcha' ) && _api_key() ? 1 : 0;
}

# this prints out the js/iframe to load the captcha (but not the captcha itself)
sub _print {
    my $self = $_[0];

    # form_auth remains the same throughout the lifetime of the request
    # so we can just call this here instead of passing it in from the external form
    my $auth = LJ::form_auth( 1 );

    # we can't use need_res, alas, because we're printing this inline
    # after the <head> has already been printed
    # FIXME: remove check when we get rid of the old library
    my $loading_text = LJ::Lang::ml( "captcha.loading" );
    my $captcha_load = $LJ::ACTIVE_RES_GROUP && $LJ::ACTIVE_RES_GROUP eq "jquery"
        ? qq!
<script type="text/javascript">
jQuery(function(jq){
    jq("#textcaptcha_container").html("$loading_text")
        .load(jq.endpoint("captcha") + "/$auth");
});
</script>
        ! : qq!
<script type="text/javascript">
    \$("textcaptcha_container").innerHTML = "$loading_text";
    HTTPReq.getJSON({
        "url": LiveJournal.getAjaxUrl("captcha") + "/$auth.json",
        "method": "GET",
        "onError": LiveJournal.ajaxError,
        "onData": function(data) {\$("textcaptcha_container").innerHTML = data.captcha}
    })
</script>
    !;

    my $response_label = LJ::Lang::ml( "/textcaptcha-response.tt.response.user.label" );

    # putting it in noscript so that we don't load it the page unnecessarily if we actually have JS
    return qq{
<div id="textcaptcha_container" aria-live="assertive" style="line-height: 1.2em">
    $captcha_load
<noscript><iframe src="$LJ::SITEROOT/captcha/text/$auth" style="width:100%;height:4em" id="textcaptcha_fallback"></iframe>
<label for="textcaptcha_response_noscript">$response_label</label> <input type="text" maxlength="255" autocomplete="off" value="" name="textcaptcha_response_noscript" class="text" id="textcaptcha_response_noscript" size="50" />
</noscript>
</div>};
}

sub _validate {
    my $self = $_[0];
    return DW::Captcha::textCAPTCHA::Logic::check_answer( $self->challenge, $self->response, $self->form_auth, $self->captcha_auth );
}

sub _init_opts {
    my ( $self, %opts ) = @_;

    # rather than having a lot of ifs/elses here to extract multiple keys
    # when we're pulling via BML vs via a controller, etc
    # let's just pull directly from the request
    my $r = DW::Request->get;
    my $post_args = $r->post_args if $r;

    if ( $post_args ) {
        if ( my $response_noscript = $post_args->{textcaptcha_response_noscript} ) {
            my %parsed = DW::Captcha::textCAPTCHA::Logic::from_form_string( $response_noscript );
            $self->{$_} ||= $parsed{$_} foreach qw( challenge response form_auth captcha_auth );
        } else {
            # allow multiple values
            $self->{challenge} ||= [ $post_args->get_all( "textcaptcha_challenge" ) ];

            # just allow the user to submit one
            $self->{response} ||= $post_args->{textcaptcha_response};

            # assume we need the form auth
            $self->{form_auth} ||= $post_args->{lj_form_auth};

            $self->{captcha_auth} ||= $post_args->{textcaptcha_chalauth};
        }
    }
}

=head1 C<< textCAPTCHA-specific methods >>

=cut

# textcaptcha-specific methods
sub _api_key { LJ::conf_test( $LJ::TEXTCAPTCHA{api_key} ) }

=head2 C<< $captcha->form_auth >>

Generic form auth. Ties this captcha to a specific form instance.

=cut

=head2 C<< $captcha->captcha_auth >>

Additional auth for this captcha. Enforces time limit and single use.

=cut

sub form_auth { return $_[0]->{form_auth} }
sub captcha_auth { return $_[0]->{captcha_auth} }

package DW::Captcha::textCAPTCHA::Logic;

# this is an internal class which shouldn't be called directly by anything else
# (except maybe tests)

sub fetch {
    my ( $class ) = $_[0];

    my $ua = LJ::get_useragent( role => 'textcaptcha', timeout => $LJ::TEXTCAPTCHA{timeout} );
    $ua->agent("$LJ::SITENAME ($LJ::ADMIN_EMAIL; captcha request)");
    my $res = $ua->get( "http://api.textcaptcha.com/" . DW::Captcha::textCAPTCHA::_api_key() );
    return $res && $res->is_success ? $res->content : "";
}

# arguments:
# * xml string containing the captcha question as a plain string
#   and answer, or answers, as an MD5 hash
# * the form auth which we can use to tie this captcha to a particular instance

# returns a hashref containing data suitable for use within the form:
# * the question to display
# * answers (salted)
# * captcha auth
sub form_data {
    my ( $captcha_data_string, $auth ) = @_;
    my $captcha = eval { XML::Simple::XMLin( $captcha_data_string, ForceArray => [ 'answer' ] ); };

    # get the timestamp
    my $secret = LJ::get_secret( (split( /:/, $auth ))[1] );
    my @salted_answers = map { Digest::MD5::md5_hex( $auth . $secret . $_ ) } @{$captcha->{answer}};

    return {
        question => $captcha->{question},
        answers => \@salted_answers,
        chal    => LJ::challenge_generate( 900 ),  # 15 minute token
    };
}

# arguments:
# * valid responses to the captcha
# * the user's response
# * form auth
# * captcha auth
sub check_answer {
    my ( $form_responses, $user_response, $form_auth, $captcha_auth ) = @_;

    # all forms we use captcha with should have had a corresponding lj_form_auth
    # but just in case we miss a spot (though we really shouldn't) let's cut this short
    # also cut short if we don't provide the captcha-specific auth
    return 0 unless $form_auth && $captcha_auth;

    my $chal_opts = {};
    return 0 unless LJ::challenge_check( $captcha_auth, $chal_opts );

    my $secret = LJ::get_secret( ( split( /:/, $form_auth ))[1] );

    my $user_answer = Digest::MD5::md5_hex( LJ::trim( lc $user_response ) );
    my $check_answer = Digest::MD5::md5_hex( $form_auth . $secret . $user_answer );

    foreach ( @$form_responses ) {
        return 1 if $_ eq $check_answer;
    }

    return 0;
}

# concatenate all relevant values into one string
sub to_form_string {
    my $self = $_[0];

    return join( "::",
        (   $self->form_auth,
            $self->captcha_auth,
            $self->response,
            join( "::", @{$self->challenge||[]} )
        )
    );
}

# return a hash
sub from_form_string {
    my ( $string ) = @_;

    my ( $form_auth, $captcha_auth, $response, @challenges ) = split "::", $string;
    return (
        form_auth       => $form_auth,
        captcha_auth    => $captcha_auth,
        response        => $response,
        challenge       => \@challenges
    );
}

1;
