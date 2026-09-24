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

DW::Template::Filters - Filters for the Dreamwidth Template Toolkit plugin

=head1 METHODS

=cut

=head2 ml

Apply a ML string.

    [% '.foo' | ml(arg = 'bar') %]

=cut

sub ml {

    # save the last argument as the hashref, hopefully
    my $args = $_[-1];
    $args = {} unless $args && ref $args eq 'HASH';

    # we have to return a sub here since we are a dynamic filter
    return sub {
        my ($code) = @_;

        # Keep the native request-local context authoritative.  Preserve the
        # old uselang override, but otherwise honor a BML/custom getter context.
        my $r       = DW::Request->get;
        my $uselang = $r->get_args->{uselang} || '';
        if ( $uselang eq 'debug' || LJ::Lang::get_lang($uselang) ) {
            LJ::Lang::set_request_context( lang => $uselang );
        }
        elsif ( !LJ::Lang::request_context() ) {
            LJ::Lang::set_request_context( lang => decide_language() );
        }

        # The TT filter historically resolves relative keys before honoring
        # uselang=debug. LJ::Lang::ml intentionally keeps its direct debug
        # contract (returning the supplied key), so preserve this here.
        if ( ( LJ::Lang::request_context()->{lang} || '' ) eq 'debug'
            && rindex( $code, '.', 0 ) == 0 )
        {
            my $scope = $r->note('ml_scope');
            return $scope . $code if defined $scope;
        }

        return LJ::Lang::ml( $code, $args );
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
    return $r->note('ml_lang') if $r->note('ml_lang');

    my $lang = _decide_language();

    $r->note( ml_lang => $lang );
    return $lang;
}

sub _decide_language {
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    # GET param 'uselang' takes priority
    my $uselang = $args->{uselang} || "";
    return $uselang
        if $uselang eq 'debug' || LJ::Lang::get_lang($uselang);

    # FIXME: next is their browser's preference

    # next is the default language
    return $LJ::DEFAULT_LANG || $LJ::LANGS[0];

    # lastly, english.
    return 'en';
}

sub time_to_http {
    return LJ::time_to_http( $_[0] );
}

1;
