# t/proto-edit-tags.t
#
# Test tag lists passed to postevent and editevent as arrayrefs, which is how
# the REST API sends them.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use LJ::Entry;
use LJ::Protocol;
use LJ::Test qw(temp_user);

my $u = temp_user();

sub req {
    my ( $mode, %args ) = @_;
    my $err = 0;
    my $res =
        LJ::Protocol::do_request( $mode,
        { ver => $LJ::PROTOCOL_VER, username => $u->user, tz => 'guess', %args },
        \$err, { noauth => 1 } );
    return ( $res, $err );
}

sub entry {
    LJ::Entry->reset_singletons;
    LJ::start_request();
    return LJ::Entry->new( $u, jitemid => $_[0] );
}

sub tags {
    my $entry = entry( $_[0] );
    return [ sort $entry->tags ];
}

my ( $res, $err ) = req( 'postevent', event => 'x', props => { taglist => [ 'one', 'two' ] } );
is( $err, 0, 'postevent with arrayref tags succeeds' );
my $id = $res->{itemid};
is_deeply( tags($id), [ 'one', 'two' ], 'postevent applies arrayref tags' );

( $res, $err ) =
    req( 'editevent', itemid => $id, event => 'y', props => { taglist => [ 'one', 'three' ] } );
is( $err, 0, 'editevent with arrayref tags succeeds' );
is_deeply( tags($id), [ 'one', 'three' ], 'editevent applies arrayref tags' );
unlike( entry($id)->prop('taglist') // '', qr/ARRAY\(/, 'taglist prop is not a stringified ref' );

( $res, $err ) = req(
    'editevent',
    itemid   => $id,
    event    => 'z',
    security => 'private',
    props    => { taglist => ['four'] }
);
is( $err, 0, 'editevent with arrayref tags and a security change succeeds' );
is_deeply( tags($id), ['four'], 'tags applied alongside the security change' );

( $res, $err ) = req( 'editevent', itemid => $id, event => 'z2', props => { taglist => [] } );
is( $err, 0, 'editevent with an empty arrayref succeeds' );
is_deeply( tags($id), [], 'empty arrayref clears tags' );

# Invalid tags must be rejected the same way whether given as a string or a list.
( $res, $err ) = req( 'editevent', itemid => $id, event => 'bad', props => { taglist => '<b>' } );
is( $err, 211, 'editevent rejects an invalid tag string' );

( $res, $err ) =
    req( 'editevent', itemid => $id, event => 'bad', props => { taglist => ['<b>'] } );
is( $err, 211, 'editevent rejects an invalid tag in an arrayref' );

( $res, $err ) = req( 'postevent', event => 'bad', props => { taglist => ['<b>'] } );
is( $err, 211, 'postevent rejects an invalid tag in an arrayref' );

is( entry($id)->event_raw, 'z2', 'rejected edit did not change the entry' );

done_testing;
