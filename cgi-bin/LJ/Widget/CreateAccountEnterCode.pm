#!/usr/bin/perl
#
# LJ::Widget::CreateAccountEnterCode
#
# This widget contains the form for giving your account creation code.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::CreateAccountEnterCode;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use DW::InviteCodes;

sub need_res { qw( stc/widgets/createaccountentercode.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    # we can still use invite codes to create new paid accounts
    # so display this in case they hit the rate limit, even without USE_ACCT_CODES
    return "<p>" . $class->ml( 'widget.createaccountentercode.error.toofast' ) . "</p>"
        unless $opts{rate_ok};

    return "" unless $LJ::USE_ACCT_CODES;

    my $get = $opts{get};

    my $code = $get->{code};
    my $errors;

    my $error_msg = sub {
        my ( $key, $pre, $post ) = @_;
        my $msg = $errors->{$key};
        return '' unless $msg;
        return "$pre $msg $post";
    };

    # if we're in this widget with a code defined, then it's invalid
    $errors->{code} = $class->ml( 'widget.createaccountentercode.error.invalidcode' )
        if $code;

    my $ret;

    $ret .= "<p>" . $class->ml( 'widget.createaccountentercode.info' ) . "</p>";

    $ret .= "<form method='get' action='$LJ::SITEROOT/create'>";
    $ret .= "<div class='highlight-box' id='code_box'>" . $class->ml( 'widget.createaccountentercode.code' ) . " ";
    $ret .= LJ::html_text( {
        name => 'code',
        value => LJ::ehtml( $code ),
        size => 21,
        maxlength => 20,
    } );
    $ret .= " " . LJ::html_submit( $class->ml( 'widget.createaccountentercode.btn.proceed' ) );
    $ret .= $error_msg->( 'code', '<br /><span class="formitemFlag">', '</span>' );
    $ret .= "</div>";
    $ret .= LJ::html_hidden( ssl => $get->{ssl} ) if $get->{ssl};
    $ret .= "</form>";

    $ret .= "<p style='margin-top: 10px;'>";

    $ret .= $class->ml( 'widget.createaccountentercode.getcode' );
    if ( LJ::is_enabled( 'payments' ) ) {
        $ret .= " " . $class->ml( 'widget.createaccountentercode.pay2', { aopts => "href='$LJ::SITEROOT/shop/account?for=new'", sitename => $LJ::SITENAMESHORT } );
    }
    my $remote = LJ::get_remote(); 
    $ret .= " " . $class->ml( 'widget.createaccountentercode.comm', { aopts => "href='$LJ::SITEROOT/communities/new'" } );
    $ret .= " " . $class->ml( 'widget.createaccountentercode.comm.loggedout2', { aopts => "href='$LJ::SITEROOT/communities/new'" } ) unless $remote;
        
    $ret .= "</p>";

    return $ret;
}

1;
