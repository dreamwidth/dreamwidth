# t/watchtrust-read-writes.t
#
# Watch/trust changes must be visible in the current request before a database
# reader has replicated the write, including immediate access-filter updates.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use DW::Cache;

{

    package WatchTrustLaggingReader;

    sub selectrow_array {
        my ( $self, $sql, $attrs, @bind ) = @_;
        my $pair = join ':', @bind;
        if ( $sql =~ /^SELECT groupmask FROM wt_edges WHERE / && exists $self->{stale}{$pair} ) {
            $self->{reads}{$pair}++;
            return $self->{stale}{$pair};
        }
        return $self->{reader}->selectrow_array( $sql, $attrs, @bind );
    }

    sub err { return 0 }

    our $AUTOLOAD;

    sub AUTOLOAD {
        my $self = shift;
        ( my $method = $AUTOLOAD ) =~ s/.*:://;
        return $self->{reader}->$method(@_);
    }
    sub DESTROY { }
}

{

    package WatchTrustRevokingWriter;

    sub do {
        my ( $self, $sql, @args ) = @_;
        $self->{revoke}->() if $sql =~ /^UPDATE wt_edges SET groupmask = groupmask & /;
        return $self->{writer}->do( $sql, @args );
    }

    our $AUTOLOAD;

    sub AUTOLOAD {
        my $self = shift;
        ( my $method = $AUTOLOAD ) =~ s/.*:://;
        return $self->{writer}->$method(@_);
    }
    sub DESTROY { }
}

my $owner = temp_user();
my $peer  = temp_user();
my $other = temp_user();
my $dbh   = LJ::get_db_writer();
my $pair  = $owner->id . ':' . $peer->id;
my $watch = 1 << 61;

sub clear_pair_cache {
    DW::Cache->request->clear_ns('trustmask');
    foreach my $target ( $peer, $other ) {
        LJ::MemCache::delete( [ $owner->id, 'trustmask:' . $owner->id . ':' . $target->id ] );
    }
}

sub reset_pair {
    $dbh->do( 'DELETE FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
        undef, $owner->id, $peer->id );
    die $dbh->errstr if $dbh->err;
    clear_pair_cache();
}

sub saved_mask {
    return $dbh->selectrow_array(
        'SELECT groupmask FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
        undef, $owner->id, $peer->id );
}

sub with_lagging_reader {
    my ( $mask, $code ) = @_;
    my $original = \&LJ::get_db_reader;
    my $reader   = bless {
        reader => $original->(),
        stale  => { $pair => $mask },
        reads  => {},
        },
        'WatchTrustLaggingReader';
    no warnings 'redefine';
    local *LJ::get_db_reader = sub {
        return $reader if caller eq 'DW::User::Edges::WatchTrust::Loader';
        return $original->(@_);
    };
    $code->($reader);
}

subtest 'grant followed immediately by access-filter update' => sub {
    reset_pair();
    with_lagging_reader(
        0,
        sub {
            my $reader = shift;
            ok( !$owner->trusts($peer),  'prime the negative lookup before granting' );
            ok( $reader->{reads}{$pair}, 'the negative lookup really used the stale reader' );
            ok( $owner->add_edge( $peer, trust => { nonotify => 1 } ), 'grant succeeds' );
            ok( $owner->trusts($peer), 'grant is visible in the same request' );
            is( $owner->trustmask($peer), 1, 'new grant has the default access mask' );
            my $mask = eval { $owner->trustmask( $peer, 21 ) };
            is( $@,    '', 'immediate filter update does not reject the newly trusted edge' );
            is( $mask, 21, 'updated mask is returned' );
            is( saved_mask(), 21, 'writer has the selected access filters' );
            ok( !$owner->trusts($other), 'grant does not leak to another pair' );
            ok( $owner->trusts($owner),  'self trust still works' );
        }
    );
};

subtest 'watch updates preserve trust and hide the watch bit from callers' => sub {
    reset_pair();
    with_lagging_reader(
        0,
        sub {
            ok(
                $owner->add_edge(
                    $peer,
                    trust => { mask     => 21, nonotify => 1 },
                    watch => { nonotify => 1 }
                ),
                'add both edges'
            );
            ok( $owner->watches($peer), 'watch is immediately visible' );
            ok( $owner->trusts($peer),  'trust is immediately visible' );
            is( $owner->trustmask($peer), 21,          'public mask excludes the watch bit' );
            is( saved_mask(),             $watch | 21, 'writer stores both kinds of edge' );
            ok( $owner->add_edge( $peer, watch => { nonotify => 1 } ), 'update watch alone' );
            is( $owner->trustmask($peer), 21,          'watch update keeps access filters' );
            is( saved_mask(),             $watch | 21, 'writer keeps the existing trust mask' );
        }
    );
};

subtest 'remove watch then trust while the reader still has both' => sub {
    reset_pair();
    $owner->add_edge(
        $peer,
        trust => { mask     => 21, nonotify => 1 },
        watch => { nonotify => 1 }
    );
    clear_pair_cache();
    with_lagging_reader(
        $watch | 21,
        sub {
            ok( $owner->watches($peer) && $owner->trusts($peer), 'stale reader has both edges' );
            ok( $owner->remove_edge( $peer, watch => { nonotify => 1 } ), 'remove watch' );
            ok( !$owner->watches($peer), 'removed watch stays absent in this request' );
            ok( $owner->trusts($peer),   'trust remains' );
            is( $owner->trustmask($peer), 21, 'remaining access filters are unchanged' );
            is( saved_mask(),             21, 'writer has only trust' );
            ok( $owner->remove_edge( $peer, trust => { nonotify => 1 } ), 'remove trust' );
            ok( !$owner->trusts($peer) && !$owner->watches($peer), 'both edges are absent' );
            is( saved_mask(), undef, 'writer row is deleted' );
            eval { $owner->trustmask( $peer, 21 ) };
            like(
                $@,
                qr/attempted to set trustmask on non-trusted edge/,
                'setter still rejects a non-trusted edge'
            );
        }
    );
};

subtest 'remove trust then watch while the reader still has both' => sub {
    reset_pair();
    $owner->add_edge(
        $peer,
        trust => { mask     => 21, nonotify => 1 },
        watch => { nonotify => 1 }
    );
    clear_pair_cache();
    with_lagging_reader(
        $watch | 21,
        sub {
            ok( $owner->trusts($peer), 'stale reader still trusts the peer' );
            ok( $owner->remove_edge( $peer, trust => { nonotify => 1 } ), 'remove trust' );
            ok( !$owner->trusts($peer), 'revoked trust is immediately absent' );
            ok( $owner->watches($peer), 'watch remains' );
            is( $owner->trustmask($peer), 0,      'remaining watch grants no access filters' );
            is( saved_mask(),             $watch, 'writer has only watch' );
            ok( $owner->remove_edge( $peer, watch => { nonotify => 1 } ), 'remove watch' );
            ok( !$owner->watches($peer), 'last edge is immediately absent' );
            is( saved_mask(), undef, 'writer row is deleted' );
        }
    );
};

subtest 'removing watch does not restore revoked access' => sub {
    reset_pair();
    $owner->add_edge(
        $peer,
        trust => { mask     => 21, nonotify => 1 },
        watch => { nonotify => 1 }
    );
    ok( $owner->remove_edge( $peer, trust => { nonotify => 1 } ), 'revoke access' );
    is( saved_mask(), $watch, 'writer has only watch' );
    clear_pair_cache();

    with_lagging_reader(
        $watch | 21,
        sub {
            my $reader = shift;
            ok( $owner->trusts($peer),   'stale reader still shows revoked access' );
            ok( $reader->{reads}{$pair}, 'the stale reader supplied the old mask' );
            ok( $owner->remove_edge( $peer, watch => { nonotify => 1 } ), 'remove watch' );
            is( saved_mask(), undef, 'writer no longer has an edge' );
            ok( !$owner->trusts($peer), 'revoked access stays absent in this request' );
        }
    );
};

subtest 'deleting a trust group refreshes the request mask' => sub {
    reset_pair();
    my $deleted = $owner->create_trust_group( groupname => 'Deleted group' );
    my $kept    = $owner->create_trust_group( groupname => 'Kept group' );
    my $remaining_trust = 1 | ( 1 << $kept );
    my $old_trust       = $remaining_trust | ( 1 << $deleted );
    $owner->add_edge(
        $peer,
        trust => { mask     => $old_trust, nonotify => 1 },
        watch => { nonotify => 1 }
    );
    clear_pair_cache();

    with_lagging_reader(
        $watch | $old_trust,
        sub {
            is( $owner->trustmask($peer), $old_trust, 'prime the mask before deletion' );
            ok( $owner->delete_trust_group( id => $deleted ), 'delete the trust group' );
            is( saved_mask(), $watch | $remaining_trust, 'writer cleared only the deleted bit' );
            is( $owner->trustmask($peer),
                $remaining_trust, 'request no longer grants the deleted group' );
            ok( $owner->watches($peer), 'watch remains visible in the request' );
        }
    );
};

subtest 'deleting a trust group preserves a concurrent revocation' => sub {
    reset_pair();
    my $deleted   = $owner->create_trust_group( groupname => 'Concurrently deleted group' );
    my $old_trust = 1 | ( 1 << $deleted );
    ok( $owner->add_edge( $peer, trust => { mask => $old_trust, nonotify => 1 } ), 'grant access' );
    clear_pair_cache();

    with_lagging_reader(
        $old_trust,
        sub {
            is( $owner->trustmask($peer), $old_trust, 'prime the mask before revocation' );
            my $original = \&LJ::get_db_writer;
            my $writer   = bless {
                writer => $dbh,
                revoke => sub {
                    my $rows =
                        $dbh->do( 'DELETE FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
                        undef, $owner->id, $peer->id );
                    is( $rows, 1, 'revoke access just before the group update' );
                },
                },
                'WatchTrustRevokingWriter';
            {
                no warnings 'redefine';
                local *LJ::get_db_writer = sub {
                    return $writer if caller eq 'DW::User';
                    return $original->(@_);
                };
                ok( $owner->delete_trust_group( id => $deleted ), 'delete the trust group' );
            }

            is( DW::Cache->request->get( 'trustmask', $pair ), 0, 'cache the absent edge as zero' );
            eval { $owner->trustmask( $peer, 1 ) };
            like( $@, qr/non-trusted edge/, 'refuse to save access filters for the revoked edge' );
            is( saved_mask(), undef, 'the revoked edge stays deleted' );
        }
    );
};

subtest 'write-through ends with the request' => sub {
    reset_pair();
    with_lagging_reader(
        0,
        sub {
            my $reader = shift;
            ok( $owner->add_edge( $peer, trust => { mask => 21, nonotify => 1 } ), 'grant access' );
            ok( $owner->trusts($peer), 'this request sees its own write' );
            DW::Cache->request->clear();
            ok( !$owner->trusts($peer),  'next request reads the deliberately lagging replica' );
            ok( $reader->{reads}{$pair}, 'request reset causes a real reader lookup' );
            is( saved_mask(), 21, 'request reset does not change the writer row' );
        }
    );
};

reset_pair();
done_testing();
