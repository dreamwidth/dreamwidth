#!/usr/bin/perl
#
# DW::User::DVersion::Migrate8To9 - Handling dversion 8 to 9 migration
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::User::DVersion::Migrate8To9;

use strict;
use warnings;

require 'ljlib.pl';
use LJ::User;
use Time::HiRes qw( usleep );

my $readonly_bit;

# find readonly cap class, complain if not found
foreach ( keys %LJ::CAP ) {
    if (   $LJ::CAP{$_}->{'_name'} eq "_moveinprogress"
        && $LJ::CAP{$_}->{'readonly'} == 1 )
    {
        $readonly_bit = $_;
        last;
    }
}
unless ( defined $readonly_bit ) {
    die
"Won't move user without %LJ::CAP capability class named '_moveinprogress' with readonly => 1\n";
}

sub do_upgrade {
    my $logpropid  = LJ::get_prop( log  => 'picture_keyword' )->{id};
    my $talkpropid = LJ::get_prop( talk => 'picture_keyword' )->{id};

    my $logpropid_map  = LJ::get_prop( log  => 'picture_mapid' )->{id};
    my $talkpropid_map = LJ::get_prop( talk => 'picture_mapid' )->{id};

    my $BLOCK_INSERT = 25;

    my ($u) = @_;

    return 0 if $u->readonly;

    return 1 if $u->dversion >= 9;

    # we really cannot have the user doing things during this process
    $u->modify_caps( [$readonly_bit], [] );

    # wait a quarter of a second, give any request the user might be doing a chance to stop
    # as the user changing things could lead to slight data loss re. userpic selection
    # on entries and comments
    usleep(250000);

    # do this in an eval so, in case something dies, we don't leave the user locked
    my $rv = 0;

    eval {
        # Unfortunately, we need to iterate over all clusters to get a list
        # of used keywords so we can give proper ids to everything,
        # even removed keywords
        my %keywords;
        my %to_update;
        if ( $u->is_individual ) {
            foreach my $cluster_id (@LJ::CLUSTERS) {
                my $dbcm_o = LJ::get_cluster_master($cluster_id);

                my $entries = $dbcm_o->selectall_arrayref(
                    q{
                    SELECT log2.journalid AS journalid, 
                           log2.jitemid AS jitemid,
                           logprop2.value AS value
                    FROM logprop2 
                    INNER JOIN log2 
                        ON ( logprop2.journalid = log2.journalid 
                            AND logprop2.jitemid = log2.jitemid ) 
                    WHERE posterid = ? 
                        AND propid=?
                    }, undef, $u->id, $logpropid
                );
                die $dbcm_o->errstr if $dbcm_o->err;
                my $comments = $dbcm_o->selectall_arrayref(
                    q{
                    SELECT talkprop2.journalid AS journalid,
                           talkprop2.jtalkid AS jtalkid,
                           talkprop2.value AS value
                    FROM talkprop2
                    INNER JOIN talk2
                        ON ( talkprop2.journalid = talk2.journalid
                            AND talkprop2.jtalkid = talk2.jtalkid )
                    WHERE posterid = ?
                        AND tpropid=?
                    }, undef, $u->id, $talkpropid
                );
                die $dbcm_o->errstr if $dbcm_o->err;

                $to_update{$cluster_id} = {
                    entries  => $entries,
                    comments => $comments,
                };
                $keywords{ $_->[2] }->{count}++ foreach ( @$entries, @$comments );
            }
        }

        my $origmap = $u->selectall_hashref(
            q{
            SELECT kwid, picid FROM userpicmap2 WHERE userid=?
            }, "kwid", undef, $u->id
        );
        die $u->errstr if $u->err;

        my $picmap = $u->selectall_hashref(
            q{
            SELECT picid, state FROM userpic2 WHERE userid=?
            }, "picid", undef, $u->id
        );
        die $u->errstr if $u->err;

        my %outrows;

        my %kwid_map;

        foreach my $k ( keys %keywords ) {
            if ( $k =~ m/^pic#(\d+)$/ ) {
                my $picid = $1;
                next if !exists $picmap->{$picid} || $picmap->{$picid}->{state} eq 'X';
                $keywords{$k}->{kwid}  = undef;
                $keywords{$k}->{picid} = $picid;
                $outrows{$picid}->{0}++;
            }
            else {
                my $kwid = $u->get_keyword_id( $k, 1 );
                $kwid_map{$kwid} = $k;
                my $picid = $origmap->{$kwid}->{picid};
                $keywords{$k}->{kwid}  = $kwid;
                $keywords{$k}->{picid} = $picid;
                $outrows{ $picid || 0 }->{$kwid}++;
            }
        }

        foreach my $r ( values %$origmap ) {
            $outrows{ $r->{picid} }->{ $r->{kwid} }++ if $r->{picid} && $r->{kwid};
        }

        {
            my ( @bind, @vals );

            # flush rows to destination table
            my $flush = sub {
                return unless @bind;

                # insert data
                my $bind = join( ",", @bind );
                $u->do( "REPLACE INTO userpicmap3 (userid,mapid,kwid,picid) VALUES $bind",
                    undef, @vals );
                die $u->errstr if $u->err;

                # reset values
                @bind = ();
                @vals = ();
            };

            foreach my $picid ( sort { $a <=> $b } keys %outrows ) {
                foreach my $kwid ( sort { $a <=> $b } keys %{ $outrows{$picid} } ) {
                    next if $kwid == 0 && $picid == 0;
                    push @bind, "(?,?,?,?)";
                    my $mapid   = LJ::alloc_user_counter( $u, 'Y' );
                    my $keyword = $kwid == 0 ? "pic#$picid" : $kwid_map{$kwid};

        # if $keyword is undef, this isn't used on any entries, so we don't care about the mapid
        # however, if $kwid is undef, this is a pic#xxx keyword, and had to have existed on an entry
                    $keywords{$keyword}->{mapid} = $mapid if defined $keyword;
                    push @vals, ( $u->id, $mapid, $kwid || undef, $picid || undef );
                    $flush->() if @bind > $BLOCK_INSERT;
                }
            }
            $flush->();
        }

        if ( $u->is_individual ) {
            foreach my $cluster_id (@LJ::CLUSTERS) {
                next unless $to_update{$cluster_id};
                my $data = $to_update{$cluster_id};

                my $dbcm_o = LJ::get_cluster_master($cluster_id);

                {
                    my ( @bind, @vals );

                    # flush rows to destination table
                    my $flush = sub {
                        return unless @bind;

                        # insert data
                        my $bind = join( ",", @bind );
                        $dbcm_o->do(
                            "REPLACE INTO logprop2 (journalid,jitemid,propid,value) VALUES $bind",
                            undef, @vals );
                        die $u->errstr if $u->err;

                        # reset values
                        @bind = ();
                        @vals = ();
                    };

                    foreach my $entry ( @{ $data->{entries} } ) {
                        next unless $keywords{ $entry->[2] }->{mapid};
                        push @bind, "(?,?,?,?)";
                        push @vals,
                            (
                            $entry->[0], $entry->[1], $logpropid_map,
                            $keywords{ $entry->[2] }->{mapid}
                            );
                        $flush->() if @bind > $BLOCK_INSERT;
                    }
                    $flush->();

                    foreach my $entry ( @{ $data->{entries} } ) {
                        LJ::MemCache::delete(
                            [ $entry->[0], "logprop:" . $entry->[0] . ":" . $entry->[1] ] );
                    }
                }
                {
                    my ( @bind, @vals );

                    # flush rows to destination table
                    my $flush = sub {
                        return unless @bind;

                        # insert data
                        my $bind = join( ",", @bind );
                        $dbcm_o->do(
                            "REPLACE INTO talkprop2 (journalid,jtalkid,tpropid,value) VALUES $bind",
                            undef, @vals
                        );
                        die $u->errstr if $u->err;

                        # reset values
                        @bind = ();
                        @vals = ();
                    };

                    foreach my $comment ( @{ $data->{comments} } ) {
                        next unless $keywords{ $comment->[2] }->{mapid};
                        push @bind, "(?,?,?,?)";
                        push @vals,
                            (
                            $comment->[0], $comment->[1], $talkpropid_map,
                            $keywords{ $comment->[2] }->{mapid}
                            );
                        $flush->() if @bind > $BLOCK_INSERT;
                    }
                    $flush->();

                    foreach my $comment ( @{ $data->{comments} } ) {
                        LJ::MemCache::delete(
                            [ $comment->[0], "talkprop:" . $comment->[0] . ":" . $comment->[1] ] );
                    }
                }
            }
        }

        $rv = 1;
    };

    my $err = $@;

    # okay, we're done, the user can do things again
    $u->modify_caps( [], [$readonly_bit] );

    die $err if $err;

    return $rv;
}

sub upgrade_to_dversion_9 {

    # If user has been purged, go ahead and update version
    # Otherwise move their data
    my $ok = $_[0]->is_expunged ? 1 : do_upgrade(@_);

    $_[0]->update_self( { 'dversion' => 9 } ) if $ok;

    LJ::Userpic->delete_cache( $_[0] );

    return $ok;
}

*LJ::User::upgrade_to_dversion_9 = \&upgrade_to_dversion_9;
