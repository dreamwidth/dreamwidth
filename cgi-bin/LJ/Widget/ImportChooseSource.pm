#!/usr/bin/perl
#
# LJ::Widget::ImportChooseSource
#
# Renders the form for a user to choose a source to import from.
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

package LJ::Widget::ImportChooseSource;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Logic::Importer;

sub need_res { qw( stc/importer.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return "" unless LJ::isu( $u );

    return $class->ml( 'widget.importchoosesource.disabled1' )
        unless LJ::is_enabled('importing');

    my @services;

    for my $service ( (
        {
            name => 'livejournal',
            url => 'livejournal.com',
            display_name => 'LiveJournal',
        },
        {
            name => 'insanejournal',
            url => 'insanejournal.com',
            display_name => 'InsaneJournal',
        },
        {
            name => 'dreamwidth',
            url => 'dreamwidth.org',
            display_name => 'Dreamwidth',
        },
    ) ){
        # only dev servers can import from Dreamwidth for testing
        next if ( $service->{name} eq 'dreamwidth' ) && ! $LJ::IS_DEV_SERVER;
        push @services, $service
            if LJ::is_enabled( "external_sites", { sitename => $service->{display_name}, domain => $service->{url} } );
    }

    my $ret;

    $ret .= "<h2 class='gradient'>" . $class->ml( 'widget.importchoosesource.header' ) . "</h2>";
    $ret .= "<p><strong>" . $class->ml( 'widget.importchoosesource.warning' ) . "</strong></p>"
        if $opts{import_in_progress};
    $ret .= "<p>" . $class->ml( 'widget.importchoosesource.intro', { sitename => $LJ::SITENAMESHORT } ) . "</p>";

    $ret .= $class->start_form;
    $ret .= "<div class='sites'>";
    $ret .= "<strong>" . $class->ml( 'widget.importchoosesource.service' ) . "</strong>";
    foreach my $service ( @services ) {
        $ret .= "<div class='siteoption'>";
        $ret .= $class->html_check(
            type => 'radio',
            name => 'hostname',
            value => $service->{url},
            id => $service->{name},
        );
        $ret .= "<label for='$service->{name}'>$service->{display_name}</label>";
        $ret .= "</div>";
    }
    $ret .= "</div>";

    $ret .= "<div class='credentials'>";
    $ret .= "<div class='i-username'>";
    $ret .= "<label for='username'>" . $class->ml( 'widget.importchoosesource.username' ) . "</label>";
    $ret .= $class->html_text( name => 'username', maxlength => 255 );
    $ret .= "</div>";
    $ret .= "<div class='i-password'>";
    $ret .= "<label for='password'>" . $class->ml( 'widget.importchoosesource.password' ) . "</label>";
    $ret .= $class->html_text( type => 'password', name => 'password' );
    $ret .= "</div>";
    if ( $u->is_community ) {
        $ret .= "<div class='i-usejournal'>";
        $ret .= "<label for='usejournal'>" . $class->ml( 'widget.importchoosesource.usejournal' ) . "</label>";
        $ret .= $class->html_text( name => 'usejournal', maxlength => 255 );
        $ret .= "</div>";
    }
    $ret .= "</div>";

    $ret .= $class->html_submit( submit => $class->ml( 'widget.importchoosesource.btn.continue' ) );
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return ( notloggedin => 1 ) unless LJ::isu( $u );

    my $hn = $post->{hostname};
    return ( ret => $class->ml( 'widget.importchoosesource.error.nohostname' ) )
        unless $hn;

    # be sure to sanitize the username
    my $un = LJ::trim( lc $post->{username} );
    $un =~ s/-/_/g;

    # be sure to sanitize the usejournal, and require one if they're importing to
    # a community
    my $uj;
    if ( $u->is_community ) {
        $uj = LJ::trim( lc $post->{usejournal} );
        $uj =~ s/-/_/g;
        return ( ret => 'Sorry, you must enter a community name for the remote site.' )
            unless $uj;
    }

    my $pw = LJ::trim( $post->{password} );
    return ( ret => $class->ml( 'widget.importchoosesource.error.nocredentials' ) )
        unless $un && $pw;

    if ( my $error = DW::Logic::Importer->set_import_data_for_user( $u, hostname => $hn, username => $un, password => $pw, usejournal => $uj ) ) {
        return ( ret => $error );
    }

    return ( ret => LJ::Widget::ImportChooseData->render );
}

1;
