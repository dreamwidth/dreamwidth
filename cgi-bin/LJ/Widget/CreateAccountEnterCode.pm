#!/usr/bin/perl
#
# LJ::Widget::CreateAccountEnterCode
#
# This widget contains the form for giving your account creation code.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::CreateAccountEnterCode;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;

    return "" unless $LJ::USE_ACCT_CODES;

    my $get = $opts{get};

    my $code = $get->{code};
    my $errors;

    my $error_msg = sub {
        my ( $key, $pre, $post ) = @_;
        my $msg = $errors->{$key};
        return unless $msg;
        return "$pre $msg $post";
    };

    # if we're in this widget with a code defined, then it's invalid
    # rate limit code input; only allow one code every five seconds
    if ( $code ) {
        my $ip = LJ::get_remote_ip();
        if ( LJ::MemCache::get( "invite_code_try_ip:$ip" ) ) {
            LJ::MemCache::set( "invite_code_try_ip:$ip", 1, 5 );
            return "<p>" . $class->ml( 'widget.createaccountentercode.error.toofast' ) . "</p>";
        }
        LJ::MemCache::set( "invite_code_try_ip:$ip", 1, 5 );
        $errors->{code} = $class->ml( 'widget.createaccountentercode.error.invalidcode' );
    }

    my $ret;

    $ret .= "<p>" . $class->ml( 'widget.createaccountentercode.info' ) . "</p>";

    $ret .= "<form method='get' action='$LJ::SITEROOT/create.bml'>";
    $ret .= "<?standout " . $class->ml( 'widget.createaccountentercode.code' ) . " ";
    $ret .= LJ::html_text( {
        name => 'code',
        value => LJ::ehtml( $code ),
        size => 21,
        maxlength => 20,
    } );
    $ret .= " " . LJ::html_submit( $class->ml( 'widget.createaccountentercode.btn.proceed' ) );
    $ret .= $error_msg->( 'code', '<br /><span class="formitemFlag">', '</span>' );
    $ret .= " standout?>";
    $ret .= LJ::html_hidden( ssl => $get->{ssl} ) if $get->{ssl};
    $ret .= "</form>";

    if ( LJ::is_enabled( 'payments' ) ) {
        $ret .= "<p style='margin-top: 10px;'>";
        $ret .= $class->ml( 'widget.createaccountentercode.pay', { aopts => "href='$LJ::SITEROOT/shop/account?for=new'", sitename => $LJ::SITENAMESHORT } );
        $ret .= " " . $class->ml( 'widget.createaccountentercode.comm', { aopts => "href='$LJ::SITEROOT/community/create.bml'" } );
        $ret .= "</p>";
    }

    return $ret;
}

1;
