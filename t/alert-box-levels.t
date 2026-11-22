# t/alert-box-levels.t
#
# Test the alert levels rendered for administrative and community notices.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use HTTP::Request;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request::Standard;
use DW::Template;

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'alertBoxLevels1';

sub alert_classes {
    my ( $template, $vars ) = @_;
    LJ::start_request();
    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.dw.test/' ) );
    my $html = DW::Template->template_string( $template, $vars );
    return [ $html =~ /<(?:div|p)\s+class=["'](alert-box\b[^"']*)["']/g ];
}

my %import = ( id => 1, items => [], other_logs => [] );
my @cases  = (
    [ 'admin/invites/review.tt', {}, getuser => 'missing-user', 'alert-box alert radius' ],
    [
        'communities/members/edit.tt',
        { messages => [], roles_changed => [], user_list => [] },
        messages => [ [ '.msg.invite', { user => 'example', invite_url => '/manage/invites' } ] ],
        'alert-box success',
    ],
    [
        'support/see_request.tt', { sp => { state => 'closed' } },
        private_req => 1,
        'alert-box secondary',
    ],
    [
        'admin/importer/history.tt',
        { imports => [ { %import, queue_complete => 1 } ] },
        imports => [ { %import, queue_complete => 0 } ],
        'alert-box radius',
    ],
    [
        'admin/importer/log.tt', { log => { started => 1, updated => 1 } },
        missing => 1,
        'alert-box radius',
    ],
);

for my $case (@cases) {
    my ( $template, $vars, $flag, $value, $class ) = @$case;
    is_deeply( alert_classes( $template, { %$vars, $flag => $value } ),
        [$class], "$template alert level" );
    is_deeply( alert_classes( $template, {%$vars} ), [], "$template without the alert condition" );
}

done_testing();
