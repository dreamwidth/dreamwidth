#
# Use this hook to upgrade insecure CSS resources, indicated
# by url() functions in CSS, using the https_url function.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::ProxyCSSLinks;

use strict;
use LJ::Hooks;
use LJ::CleanHTML;

LJ::Hooks::register_hook( 'css_cleaner_transform', sub {
    my $textref = $_[0];
    return unless ref $textref && $$textref;  # nothing to do

    my $ssl_url = sub {
        my ( $url, $q ) = @_;
        $q ||= '"';  # provide double quotes if none specified
        $url = LJ::CleanHTML::https_url( $url );
        return "url($q$url$q)";
    };

    $$textref =~ s/\burl\(\s*(['"]?)(.*?)\1\s*\)/$ssl_url->($2,$1)/geis;
} );

1;
