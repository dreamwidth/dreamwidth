# t/feed-merge.t
#
# Test reading filter recovery and saves during syndicated feed merges.
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
use Storable qw( nfreeze thaw );

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::User::ContentFilters::Filter;
use LJ::Console;
use LJ::Feed;
use LJ::Tags;
use LJ::Test qw( temp_feed temp_user );

local $LJ::T_NO_COMMAND_PRINT = 1;

subtest 'a contested filter does not interrupt the merge' => sub {
    my $source   = temp_feed();
    my $target   = temp_feed();
    my $first    = temp_user();
    my @watchers = ( $first, temp_user( cluster => $first->clusterid ) );
    my %filterid;
    foreach my $watcher (@watchers) {
        $watcher->add_edge( $source, watch => { nonotify => 1 } );
        $filterid{ $watcher->id } = $watcher->create_content_filter( name => 'Feeds' );
        $watcher->content_filters( id => $filterid{ $watcher->id } )
            ->add_row( userid => $source->id );
    }

    $watchers[0]->grant_priv('syn_edit');
    LJ::set_remote( $watchers[0] );

    my $writer = LJ::get_cluster_master( $watchers[0] );
    my ( $contested, $output );
    my $writes = 0;
    {
        local $writer->{Callbacks} = {
            do => sub {
                my ( $handle, $sql, $attr, $data, $owner, $filter, $raw ) = @_;
                return unless $sql =~ /^UPDATE content_filter_data\b/;
                $contested //= $owner;
                return unless $owner == $contested;

                my $current = thaw($raw);
                $current->{ $source->id }{adultcontent} = ++$writes % 2 ? 'sfw' : 'nonexplicit';
                local $handle->{Callbacks};
                $handle->do(
                    'UPDATE content_filter_data SET data = ? WHERE userid = ? AND filterid = ?',
                    undef, nfreeze($current), $owner, $filter )
                    or die $handle->errstr;
                return;
            },
        };
        $output =
            LJ::Console->run_commands_text( 'syn_merge '
                . $source->user . ' to '
                . $target->user
                . " using $LJ::SITEROOT/feed.rss" );
    }

    is( $writes, 3, 'Three real competing writes exhaust the retry budget' );
    like( $output, qr/^success: Merged/m, 'The console reports the completed merge' );
    like(
        $output,
        qr/Warning:.*filter $filterid{$contested} for user $contested/m,
        'The console identifies the contested filter and owner in a warning'
    );

    foreach my $watcher (@watchers) {
        my $data = persisted_filter( $watcher, $filterid{ $watcher->id } );
        ok( $watcher->watches($target) && !$watcher->watches($source), 'The watch was moved' );
        if ( $watcher->id == $contested ) {
            is( $data->{ $source->id }{adultcontent}, 'sfw', 'The last competing edit survived' );
        }
        else {
            is_deeply( [ keys %$data ], [ $target->id ], 'The subsequent filter was migrated' );
        }
    }

    my $audit =
        LJ::get_db_writer()
        ->selectcol_arrayref(
        q{SELECT userid FROM statushistory WHERE shtype = 'synd_merge' AND userid IN (?, ?)},
        undef, $source->id, $target->id );
    is_deeply(
        [ sort { $a <=> $b } @$audit ],
        [ sort { $a <=> $b } $source->id, $target->id ],
        'Both feeds have a merge audit entry despite the contested filter'
    );
};

subtest 'a save with pre-merge members follows feed redirects' => sub {
    my $source  = temp_feed();
    my $target  = temp_feed();
    my $watcher = temp_user();
    $watcher->add_edge( $source, watch => { nonotify => 1 } );

    my $source_tag = LJ::Tags::create_usertag( $source, 'source' )->{source};
    my $target_tag = LJ::Tags::create_usertag( $target, 'target, another' )->{another};
    my $filterid = $watcher->create_content_filter( name => 'Feeds' );
    my $filter   = $watcher->content_filters( id => $filterid );
    $filter->add_row( userid => $source->id, tags => [$source_tag], tagmode => 'none_of' );
    $filter->add_row( userid => $target->id, tags => [$target_tag], tagmode => 'all_of' );
    my $stale = DW::User::ContentFilters::Filter->new( ownerid => $watcher->id, id => $filterid );
    ok( $stale->contains_userid( $source->id ), 'The separate filter object loaded before merge' );

    my ( $ok, $message ) = LJ::Feed::merge_feed(
        from => $source,
        to   => $target,
        url  => "$LJ::SITEROOT/feed.rss#stale"
    );
    ok( $ok, 'The merge completed' ) or diag $message;
    $stale->data->{ $source->id }{adultcontent} = 'sfw';
    ok( $stale->_save, 'The stale save completed' );

    my $data = persisted_filter( $watcher, $filterid );
    is_deeply( [ keys %$data ], [ $target->id ], 'The save did not restore the merged-away feed' );
    is( $data->{ $target->id }{adultcontent}, 'sfw', 'The save kept the portable source setting' );
    is_deeply(
        [ @{ $data->{ $target->id } }{qw(tags tagmode)} ],
        [ [$target_tag], 'all_of' ],
        'The save kept the surviving feed tags and mode'
    );
};

subtest 'a feed save only holds its owner lock' => sub {
    my $feed    = temp_feed();
    my $first   = temp_user();
    my $second  = temp_user( cluster => $first->clusterid );
    my @filters = map { $_->content_filters( id => $_->create_content_filter( name => 'Feeds' ) ) }
        ( $first, $second );
    my $writer = LJ::get_cluster_master($first);
    my $master = LJ::get_db_writer();
    my ( $saved, $error, %held );
    {
        local $writer->{Callbacks} = {
            do => sub {
                my ( $handle, $sql, $attr, $owner ) = @_;
                return unless $sql =~ /^REPLACE\b.*\bINTO content_filter_data\b/;
                $held{$owner} = $master->selectrow_array( 'SELECT IS_USED_LOCK(?)',
                    undef, "dwl:content_filter_feed_merge:$owner" );
                return unless $owner == $first->id;

                $saved = eval { $filters[1]->add_row( userid => $feed->id ) };
                $error = $@;
                return;
            },
        };
        ok( $filters[0]->add_row( userid => $feed->id ), 'The first save completed' );
    }

    ok( $saved, 'The second owner can save while the first is still writing' )
        or diag( $error || 'The nested save did not complete' );
    ok( $held{ $first->id } && $held{ $second->id }, 'Each write holds its own database lock' );
    if ($saved) {
        my $data = persisted_filter( $second, $filters[1]->id );
        ok( exists $data->{ $feed->id }, 'The second owner persisted the feed' );
    }
};

subtest 'a migration follows redirects published by overlapping merges' => sub {
    my ( $source, $intermediate, $next, $target ) = map { temp_feed() } 1 .. 4;
    my $watcher  = temp_user();
    my $filterid = $watcher->create_content_filter( name => 'Feeds' );
    $watcher->add_edge( $source, watch => { nonotify => 1 } );
    $watcher->content_filters( id => $filterid )
        ->add_row( userid => $source->id, adultcontent => 'sfw' );

    my $writer    = LJ::get_db_writer();
    my $source_id = $source->id;
    my $overlapped;
    {
        local $writer->{Callbacks} = {
            do => sub {
                my ( $handle, $sql ) = @_;
                return unless $sql =~ /^INSERT INTO statushistory\b.*VALUES \($source_id,/;

                $overlapped = 1;
                local $handle->{Callbacks};
                check_merge( $intermediate, $next );
                check_merge( $next,         $target );
                return;
            },
        };
        check_merge( $source, $intermediate );
    }

    ok( $overlapped, 'The later redirects were published before migrating the source filter' );
    my $data = persisted_filter( $watcher, $filterid );
    is_deeply(
        $data,
        { $target->id => { adultcontent => 'sfw' } },
        'The source settings were migrated through both redirects to the final feed'
    );
};

subtest 'a merge picks up watchers transferred after its initial check' => sub {
    my ( $source, $intermediate, $target ) = map { temp_feed() } 1 .. 3;
    my $watcher  = temp_user();
    my $filterid = $watcher->create_content_filter( name => 'Feeds' );
    $watcher->add_edge( $source, watch => { nonotify => 1 } );
    $watcher->content_filters( id => $filterid )->add_row( userid => $source->id );

    my $writer = LJ::get_db_writer();
    my $overlapped;
    {
        local $writer->{Callbacks} = {
            selectrow_array => sub {
                my ( $handle, $sql, $attr, $userid ) = @_;
                return if $overlapped || $sql !~ /^SELECT synurl FROM syndicated\b/;
                return unless $userid == $intermediate->id;

                $overlapped = 1;
                local $handle->{Callbacks};
                check_merge( $source, $intermediate );
                is_deeply(
                    [ keys %{ persisted_filter( $watcher, $filterid ) } ],
                    [ $intermediate->id ],
                    'The first merge persisted the intermediate feed'
                );
                return;
            },
        };
        check_merge( $intermediate, $target );
    }

    ok( $overlapped, 'The first merge finished after the later merge checked for watchers' );
    my $data = persisted_filter( $watcher, $filterid );
    is_deeply(
        [ keys %$data ],
        [ $target->id ],
        'The second merge migrated the transferred watcher'
    );
};

subtest 'a compare-and-swap retry uses a newly published redirect' => sub {
    my ( $source, $intermediate, $target ) = map { temp_feed() } 1 .. 3;
    my $watcher  = temp_user();
    my $filterid = $watcher->create_content_filter( name => 'Feeds' );
    $watcher->add_edge( $source, watch => { nonotify => 1 } );
    $watcher->content_filters( id => $filterid )->add_row( userid => $source->id );

    my $writer = LJ::get_cluster_master($watcher);
    my $published;
    {
        local $writer->{Callbacks} = {
            do => sub {
                my ( $handle, $sql, $attr, $data, $uid, $fid, $raw ) = @_;
                return if $published || $sql !~ /^UPDATE content_filter_data\b/;
                return unless $uid == $watcher->id && $fid == $filterid;

                $published = $intermediate->set_prop( renamedto => $target->user )
                    && $intermediate->update_self( { journaltype => 'R', statusvis => 'R' } );
                my $current = thaw($raw);
                $current->{ $source->id }{adultcontent} = 'nonexplicit';
                local $handle->{Callbacks};
                $handle->do(
                    'UPDATE content_filter_data SET data = ? WHERE userid = ? AND filterid = ?',
                    undef, nfreeze($current), $uid, $fid )
                    or die $handle->errstr;
                return;
            },
        };
        check_merge( $source, $intermediate );
    }

    ok( $published, 'The destination redirected during the first write attempt' );
    is_deeply(
        persisted_filter( $watcher, $filterid ),
        { $target->id => { adultcontent => 'nonexplicit' } },
        'The retry used the live destination and retained the competing edit'
    );
};

subtest 'a failed status update clears the unpublished redirect' => sub {
    my $source    = temp_feed();
    my $target    = temp_feed();
    my $writer    = LJ::get_db_writer();
    my $source_id = $source->id;
    my $failed_update;
    my ( $ok, $message );
    {
        local $writer->{RaiseError} = 0;
        local $writer->{PrintError} = 0;
        local $writer->{Callbacks}  = {
            do => sub {
                return unless $_[1] =~ /^UPDATE user SET .* WHERE userid=$source_id$/;
                $failed_update = $_[1] =~ s/\bstatusvis\b/invalid_statusvis_column/;
                return;
            },
        };
        ( $ok, $message ) =
            LJ::Feed::merge_feed( from => $source, to => $target, url => "$LJ::SITEROOT/feed.rss" );
    }

    ok( $failed_update, 'The status update was sent with an invalid column' );
    ok( !$ok,           'The merge reported failure' );
    like(
        $message,
        qr/Unable to mark the feed as redirected/,
        'The status update error is reported'
    );
    my $status = $writer->selectrow_array( 'SELECT statusvis FROM user WHERE userid = ?',
        undef, $source_id );
    is( $status, 'V', 'The source remains visible in the database' );
    $source->uncache_prop('renamedto');
    my $redirect = LJ::DB::require_master( sub { $source->prop('renamedto') } );
    is( $redirect, undef, 'No redirect remains on the writer' );
};

sub check_merge {
    my ( $source, $target )  = @_;
    my ( $ok,     $message ) = LJ::Feed::merge_feed(
        from => $source,
        to   => $target,
        url  => "$LJ::SITEROOT/feed.rss#" . $target->user
    );
    ok( $ok, 'Merged ' . $source->user . ' into ' . $target->user ) or diag $message;
}

sub persisted_filter {
    my ( $watcher, $filterid ) = @_;
    my $raw = $watcher->writer->selectrow_array(
        'SELECT data FROM content_filter_data WHERE userid = ? AND filterid = ?',
        undef, $watcher->id, $filterid );
    return thaw($raw);
}

done_testing();
