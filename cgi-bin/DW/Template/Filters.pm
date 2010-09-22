#!/usr/bin/perl
#
# DW::Template::Filters
#
# Filters for the Dreamwidth Template Toolkit plugin
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Template::Filters;
use strict;

=head1 NAME

DW::Template::Plugin - Template Toolkit plugin for Dreamwidth

=head1 METHODS

=cut

=head2 ml

Apply a ML string.

    [% '.foo' | ml(arg = 'bar') %]

=cut

# Separated out of DW::Template::Plugin to avoid accidental use as a method.
sub ml {
    # save the last argument as the hashref, hopefully
    my $args = $_[-1];
    $args = {} unless $args && ref $args eq 'HASH';

    # we have to return a sub here since we are a dynamic filter
    return sub {
        my ( $code ) = @_;

        $code = DW::Request->get->note( 'ml_scope' ) . $code
            if rindex( $code, '.', 0 ) == 0;

        my $lang = decide_language();
        return $code if $lang eq 'debug';
        return LJ::Lang::get_text( $lang, $code, undef, $args );
    };
}

=head2 js

Escape any JS output

=cut
sub js {
    return sub {
        return LJ::ejs_string( $_[0] );
    }
}

sub decide_language {
    my $r = DW::Request->get;
    return $r->note( 'ml_lang' ) if $r->note( 'ml_lang' );
    
    my $lang = _decide_language();
    
    $r->note( ml_lang => $lang );
    return $lang;
}

sub _decide_language {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    # GET param 'uselang' takes priority
    my $uselang = $args->{uselang};
    return $uselang
        if $uselang eq 'debug' || LJ::Lang::get_lang( $uselang );

    # next is their cookie preference
    #FIXME: COOKIE!
    #if ( $r->cookie('langpref') =~ m!^(\w{2,10})/(\d+)$! ) {
    #    if (exists $env->{"Langs-$1"}) {
    #        # FIXME: Probably should actually do this!!!
    #        # make sure the document says it was changed at least as new as when
    #        # the user last set their current language, else their browser might
    #        # show a cached (wrong language) version.
    #        return $1;
    #    }
    #}

    # FIXME: next is their browser's preference

    # next is the default language
    return $LJ::DEFAULT_LANG || $LJ::LANGS[0];

    # lastly, english.
    return 'en';
}

1;
