#!/usr/bin/perl
#
# t/widget-resources.t
#
# Widget resources must follow a Foundation page's active resource group.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Widget;

{

    package LJ::Widget::ResourceTest;
    our @ISA = ('LJ::Widget');
    sub need_res    { qw(test.js) }
    sub render_body { return 'widget body' }
    sub js          { return 'initWidget: function () {}' }
}

sub in_foundation {
    my ($file) = @_;
    return grep { $_->[0] eq 'foundation' && $_->[1] eq $file }
        map { @$_ } grep { $_ } @LJ::NEEDED_RES;
}

local @LJ::NEEDED_RES;
local %LJ::NEEDED_RES;
local $LJ::ACTIVE_RES_GROUP = 'foundation';

no warnings 'redefine';
local *LJ::Auth::ajax_auth_token = sub { return 'token'; };

LJ::Widget::ResourceTest->render;
ok(
    in_foundation('js/widgets/ResourceTest/test.js'),
    'widget JavaScript is available to Foundation pages'
);

LJ::Widget::ResourceTest->new->wrapped_js;
ok( in_foundation('js/ljwidget.js'), 'widget runtime is available to Foundation pages' );

done_testing;
