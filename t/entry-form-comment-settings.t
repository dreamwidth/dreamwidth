# t/entry-form-comment-settings.t
#
# Test that editing a community entry preserves who disabled its comments.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Protocol;
use LJ::Test qw(temp_user temp_comm);
use LJ::Web;

my $poster = temp_user();
my $comm   = temp_comm();

my @cases = (
    {
        name     => 'unchanged administrator setting',
        initial  => [ 0, 1, 0 ],
        selected => 'nocomments_maintainer',
        expected => [ 0, 1, 0 ],
    },
    {
        name     => 'unchanged administrator setting with email disabled',
        initial  => [ 0, 1, 1 ],
        selected => 'nocomments_maintainer',
        expected => [ 0, 1, 1 ],
    },
    {
        name     => 'poster disables comments',
        initial  => [ 0, 0, 0 ],
        selected => 'nocomments',
        expected => [ 1, 0, 0 ],
    },
    {
        name     => 'unchanged poster setting',
        initial  => [ 1, 0, 0 ],
        selected => 'nocomments',
        expected => [ 1, 0, 0 ],
    },
    {
        name     => 'poster and administrator both disabled comments',
        initial  => [ 1, 1, 0 ],
        selected => 'nocomments',
        expected => [ 1, 1, 0 ],
    },
    {
        name     => 'poster explicitly enables comments',
        initial  => [ 0, 1, 1 ],
        selected => '',
        expected => [ 0, 0, 0 ],
    },
    {
        name     => 'poster explicitly enables comments without email',
        initial  => [ 0, 1, 0 ],
        selected => 'noemail',
        expected => [ 0, 0, 1 ],
    },
);

my @props = qw(opt_nocomments opt_nocomments_maintainer opt_noemail);
foreach my $case (@cases) {
    subtest $case->{name} => sub {
        my $entry = $poster->t_post_fake_entry(
            usejournal      => $comm->user,
            usejournal_okay => 1,
        );
        my %initial;
        @initial{@props} = @{ $case->{initial} };
        LJ::set_logprop( $comm, $entry->jitemid, \%initial );

        my %request = (
            mode       => 'editevent',
            ver        => $LJ::PROTOCOL_VER,
            user       => $poster->user,
            usejournal => $comm->user,
            itemid     => $entry->jitemid,
        );
        LJ::entry_form_decode(
            \%request,
            {
                subject          => 'Edited without changing comment settings',
                event            => 'An unrelated change to the entry text.',
                security         => 'public',
                comment_settings => $case->{selected},
            }
        );

        my %response;
        LJ::do_request( \%request, \%response, { noauth => 1 } );
        is( $response{success}, 'OK', 'legacy form edit succeeds' )
            or diag( $response{errmsg} || 'no protocol error supplied' );

        my %stored;
        LJ::load_log_props2( $comm, [ $entry->jitemid ], \%stored );
        is_deeply( [ map { $stored{ $entry->jitemid }{$_} ? 1 : 0 } @props ],
            $case->{expected},
            'stored poster, administrator and email preferences remain distinct' );
    };
}

done_testing();
