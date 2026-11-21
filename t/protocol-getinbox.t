# t/protocol-getinbox.t
#
# Test notification types returned by LJ::Protocol::getinbox.
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

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Event::AddedToCircle;
use LJ::Event::XPostSuccess;
use LJ::Protocol;
use LJ::Test qw( temp_user );

my $user         = temp_user();
my $other        = temp_user();
my $inbox        = $user->notification_inbox;
my $circle_event = LJ::Event::AddedToCircle->new( $user, $other, 2 );
my $xpost_event  = LJ::Event::XPostSuccess->new( $user, 1, 1 );
my $circle_qid   = $inbox->enqueue( event => $circle_event )->qid;
my $xpost_qid    = $inbox->enqueue( event => $xpost_event )->qid;

my $getinbox = sub {
    my (%args) = @_;
    my $err = 0;
    return LJ::Protocol::do_request( 'getinbox', { ver => 1, username => $user->user, %args },
        \$err, { noauth => 1 } );
};

my $unfiltered = $getinbox->();
my %items      = map { $_->{qid} => $_ } @{ $unfiltered->{items} || [] };
is( scalar keys %items,          2, 'getinbox returns both queued notifications' );
is( $items{$circle_qid}->{type}, 1, 'a recognized event keeps its legacy protocol code' );
is( $items{$xpost_qid}->{type},  0, 'an event without a legacy code uses type zero' );
is( $items{$xpost_qid}->{typename}, 'XPostSuccess', 'the response identifies that event by name' );
is_deeply( $getinbox->( gettype => 1 ), $unfiltered, 'a legacy filter does not hide other events' );
is_deeply( $getinbox->( gettype => 12 ), $unfiltered, 'a retired filter does not empty the inbox' );
