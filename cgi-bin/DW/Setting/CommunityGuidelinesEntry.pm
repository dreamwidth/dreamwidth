#!/usr/bin/perl
#
# DW::Setting::CommunityGuidelinesEntry
#
# DW::Setting module that lets you input the URL of an entry that contains the posting guidelines for the community
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::CommunityGuidelinesEntry;
use base 'LJ::Setting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;
    return $u->is_community;
}

sub prop_name { "posting_guidelines_entry" }
sub label     { $_[0]->ml('setting.communityguidelinesentry.label') }

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    my $e = $u->get_posting_guidelines_entry;
    $ret .= LJ::html_text(
        {
            name  => "${key}communityguidelinesentry",
            id    => "${key}communityguidelinesentry",
            class => "text",
            value => $errs ? $class->get_arg( $args, "communityguidelinesentry" )
            : $e ? $e->url
            : '',
            size        => 50,
            maxlength   => 100,
            placeholder => _example_url(),
        }
    );

    my $errdiv = $class->errdiv( $errs, "communityguidelinesentry" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "communityguidelinesentry" );

    my $postingguidelines_loc = $u->posting_guidelines_location;
    if ( $postingguidelines_loc eq "E" ) {
        my $e = $u->posting_guidelines_entry($val);
        $class->errors(
            "communityguidelinesentry" => LJ::Lang::ml(
                'setting.communityguidelinesentry.invalid',
                {
                    example_url => _example_url(),
                    example_id  => "1234",
                }
            )
        ) unless $e;
    }

    return 1;
}

sub _example_url { "https://exampleusername.$LJ::DOMAIN/1234.html" }
1;
