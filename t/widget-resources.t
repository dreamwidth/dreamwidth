# Widget resources must follow a Foundation page's active resource group.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
use strict;
use warnings;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Widget;

{

    package LJ::Widget::ResourceTest;
    our @ISA = ('LJ::Widget');
    sub need_res    { qw(test.js stc/widgets/resourcetest.css) }
    sub render_body { return 'widget body' }
    sub js          { return 'initWidget: function () {}' }
}

sub resources {
    return map { @$_ } grep { $_ } @LJ::NEEDED_RES;
}

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP = 'foundation';

    LJ::Widget::ResourceTest->render;
    my @resources = resources();
    ok(
        grep( $_->[0] eq 'foundation' && $_->[1] eq 'js/widgets/ResourceTest/test.js', @resources ),
        'widget JavaScript is available to Foundation pages'
    );
    ok( grep( $_->[0] eq 'all' && $_->[1] eq 'stc/widgets/resourcetest.css', @resources ),
        'widget CSS remains available to all resource groups' );

    no warnings 'redefine';
    local *LJ::Auth::ajax_auth_token = sub { return 'token'; };
    my $setup = LJ::Widget::ResourceTest->new->wrapped_js;
    @resources = resources();
    ok( grep( $_->[0] eq 'foundation' && $_->[1] eq 'js/ljwidget.js', @resources ),
        'widget runtime is available to Foundation pages' );
    foreach
        my $dependency (qw(js/6alib/core.js js/6alib/dom.js js/6alib/httpreq.js js/livejournal.js))
    {
        ok(
            grep( $_->[0] eq 'foundation' && $_->[1] eq $dependency, @resources ),
            "$dependency loads before the widget runtime in Foundation"
        );
    }
    like( $setup, qr/LJWidgetInitQueue/,        'setup waits for body-loaded widget runtime' );
    like( $setup, qr/var \$ = DOM\.getElement/, 'legacy widget lookup is locally scoped' );
}

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP;

    LJ::Widget::ResourceTest->render;
    my @resources = resources();
    ok( grep( $_->[0] eq 'default' && $_->[1] eq 'js/widgets/ResourceTest/test.js', @resources ),
        'legacy callers retain the default JavaScript resource group' );
}

done_testing;
