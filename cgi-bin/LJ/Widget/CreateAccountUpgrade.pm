#!/usr/bin/perl
#
# LJ::Widget::CreateAccountUpgrade
#
# This widget contains information about why a user should get a paid account
# and how they can get one.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::CreateAccountUpgrade;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $ret;
    $ret .= "<h2>" . $class->ml('widget.createaccountupgrade.title') . "</h2>";
    $ret .= "<p class='intro'>"
        . $class->ml( 'widget.createaccountupgrade.text',
        { sitename => $LJ::SITENAMESHORT, aopts => "href='$LJ::HELPURL{paidaccountinfo}'" } )
        . "</p>";
    $ret .= $class->start_form;
    $ret .= $class->html_submit( submit => $class->ml('widget.createaccountupgrade.btn.purchase') );
    $ret .= $class->end_form;
    $ret .=
          "<p style='margin-top: 10px;'><a href='$LJ::SITEROOT/create/confirm'>"
        . $class->ml('widget.createaccountupgrade.nextstep')
        . "</a></p>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    return BML::redirect("$LJ::SITEROOT/shop/account?for=self");
}

1;
