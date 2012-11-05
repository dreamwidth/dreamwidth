#!/usr/bin/perl
#
# DW::Setting::TxtMsgSetup
#
# LJ::Setting module for specifying a cell provider and phone number
# that allows people to send a user text messages via the site.
# Refactored and repackaged from /manage/profile.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::TxtMsgSetup;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->can_use_textmessaging;
}

sub label {
    my $class = shift;
    return $class->ml( 'setting.txtmsgsetup.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $tminfo = LJ::TextMessage->tm_info( $u, remap_result => 1 );
    LJ::text_out( \$_ ) foreach values %$tminfo;

    my $ret = '';

    unless ( $args && $args->{vis_only} ) {
        unless ( $args && $args->{info_only} ) {
            $ret .= " <label for='${key}txtmsg_number'>";
            $ret .= $class->ml( 'setting.txtmsgsetup.phone' );
            $ret .= "</label>";
        }

        my $number = $class->get_arg( $args, "txtmsg_number" ) || $tminfo->{number};

        $ret .= LJ::html_text( { name => "${key}txtmsg_number",
                                 id   => "${key}txtmsg_number",
                                 title => $class->ml( 'setting.txtmsgsetup.phone' ),
                                 value => $number,
                                 size => 15, maxlength => 40 } );

        my $provider = $class->get_arg( $args, "txtmsg_provider" ) || $tminfo->{provider};
        my @opts = ( "", $class->ml( 'setting.txtmsgsetup.select.provider' ) );
        foreach my $p ( LJ::TextMessage::providers() ) {
            my $info = LJ::TextMessage::provider_info( $p );
            push @opts, ( $p, $info->{name} );
        }

        $ret .= LJ::html_select( { name => "${key}txtmsg_provider",
                                   id   => "${key}txtmsg_provider",
                                   style => 'width: 25em; margin: 0 0.5em;',
                                   selected => $provider },
                                 @opts );

        $ret .= " <label for='${key}txtmsg_provider'>";
        $ret .= $class->ml( 'setting.txtmsgsetup.details', { aopts => "href='$LJ::SITEROOT/tools/textmessage?mode=details'" } );
        $ret .= "</label>";

        my $n_errs = $class->errdiv( $errs, "txtmsg_number" );
        $ret .= "<br />$n_errs" if $n_errs;
        my $p_errs = $class->errdiv( $errs, "txtmsg_provider" );
        $ret .= "<br />$p_errs" if $p_errs;
        $ret .= "<br />";
    }
    return $ret if $args && $args->{info_only};

    unless ( $args && $args->{vis_only} ) {
        $ret .= "<label for='${key}txtmsg_security'>";
        $ret .= $class->ml( 'setting.txtmsgsetup.vis' );
        $ret .= "</label> ";
    }

    $tminfo->{security} = 'none'
        if $u->{'txtmsg_status'} =~ /^(?:off|none)$/;
    my $security = $class->get_arg( $args, "txtmsg_security" ) || $tminfo->{security};

    my @opts = $u->is_community ? 
    (
        all => $class->ml( "setting.usermessaging.opt.a" ),
        reg => $class->ml( "setting.usermessaging.opt.y" ),
        friends => $class->ml( "setting.usermessaging.opt.members" ),
        none    => $class->ml( "setting.usermessaging.opt.admins" ),
    )
    :
    (
        all => $class->ml( "setting.usermessaging.opt.a" ),
        reg => $class->ml( "setting.usermessaging.opt.y" ),
        friends => $class->ml( "setting.usermessaging.opt.f" ),
        none    => $class->ml( "setting.usermessaging.opt.n" ),
    );

    $ret .= LJ::html_select( { name => "${key}txtmsg_security",
                               id   => "${key}txtmsg_security",
                               title => $class->ml( 'setting.txtmsgsetup.vis' ),
                               selected => $security },
                             @opts );

    my $errdiv = $class->errdiv( $errs, "txtmsg_security" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;

    # validate security setting
    my $security = $class->get_arg( $args, "txtmsg_security" );
    $class->errors( txtmsg_security => $class->ml( 'setting.txtmsgsetup.error.security' ) )
        if $security && $security !~ /^(?:all|reg|friends|none)$/;

    # only validate info if security is enforced
    my $number = $class->get_arg( $args, "txtmsg_number" );
    my $provider = $class->get_arg( $args, "txtmsg_provider" );

    # only do further error checking if the user didn't delete both the number and the provider
    if ( $security && $security ne 'none' ) {
        if ( $provider || $number ) {
            # check for something that looks like a phone number
            $class->errors( txtmsg_number => $class->ml( 'setting.txtmsgsetup.error.number' ) )
                    unless ( $number && $number =~ /^[-+0-9]{9,}$/ );
            # check for valid provider
            my %valid = map { $_ => 1 } LJ::TextMessage::providers();
            $class->errors( txtmsg_provider => $class->ml( 'setting.txtmsgsetup.error.provider' ) )
                    unless ( $provider && $valid{$provider} );
        }
    } else {  # warn them that new info won't be saved
        my $tminfo = LJ::TextMessage->tm_info( $u, remap_result => 1 );
        $class->errors( txtmsg_number => $class->ml( 'setting.txtmsgsetup.error.notsecured' ) )
            if $number && $number ne $tminfo->{number};
        $class->errors( txtmsg_provider => $class->ml( 'setting.txtmsgsetup.error.notsecured' ) )
            if $provider && $provider ne $tminfo->{provider};
    }

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $number = $class->get_arg( $args, "txtmsg_number" );
    my $provider = $class->get_arg( $args, "txtmsg_provider" );
    my $security = $class->get_arg( $args, "txtmsg_security" );

    my $tminfo = LJ::TextMessage->tm_info( $u, remap_result => 1 );
    my $cleared = ( $tminfo->{provider} && ! $provider ) ||
                  ( $tminfo->{number} && ! $number );

    my $txtmsg_status = $cleared || ( $security && $security eq 'none' )
                        ? "off" : "on";

    $u->update_self( { txtmsg_status => $txtmsg_status } );

    my $dbh = LJ::get_db_writer();

    if ( $cleared ) {
        # clear out existing info
        $dbh->do( "DELETE FROM txtmsg WHERE userid=?", undef, $u->userid );

    } elsif ( $txtmsg_status eq "on" ) {
        $dbh->do( "REPLACE INTO txtmsg (userid, provider, number, security)"
                . " VALUES (?, ?, ?, ?)", undef,
                  $u->userid, $provider, $number, $security );
    }

    # clear text message security caches
    delete $u->{_txtmsgsecurity};
    $u->memc_delete( "txtmsgsecurity" );

    return 1;
}

1;
