# Hooks for the site scheme(s)
#
# Authors:
#     Janine Smith <janine@netrophic.com>
#     Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Hooks::SiteScheme;

use strict;
use LJ::Hooks;
use DW::SiteScheme;

LJ::Hooks::register_hook(
    'modify_scheme_list',
    sub {
        my ( $schemes, $merge_func ) = @_;

        $merge_func->(
            'celerity-local' => { parent => 'celerity', title    => "Celerity" },
            'dreamwidth'     => { parent => 'global',   internal => 1 },
            'gradation-horizontal-local' =>
                { parent => 'gradation-horizontal', title => "Gradation Horizontal" },
            'gradation-vertical-local' =>
                { parent => 'gradation-vertical', title => "Gradation Vertical" },
            'tropo-common' => { parent => 'common',       internal => 1 },
            'tropo-purple' => { parent => 'tropo-common', title    => "Tropospherical Purple" },
            'tropo-red'    => { parent => 'tropo-common', title    => "Tropospherical Red" },
        );

        @{$schemes} = (
            { scheme => "tropo-red" },
            { scheme => "tropo-purple" },
            {
                scheme => "celerity-local",
                alt    => 'siteskins.celerity.alt',
                desc   => 'siteskins.celerity.desc',
            },
            {
                scheme => "gradation-horizontal-local",
                alt    => 'siteskins.gradation-horizontal.alt',
                desc   => 'siteskins.gradation-horizontal.desc',
            },
            {
                scheme => "gradation-vertical-local",
                alt    => 'siteskins.gradation-vertical.alt',
                desc   => 'siteskins.gradation-vertical.desc',
            },
            { scheme => "lynx" },
        );
    }
);

1;
