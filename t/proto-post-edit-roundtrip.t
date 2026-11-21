# t/proto-post-edit-roundtrip.t
#
# Test TODO post editing revisions?
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test;
use LJ::Protocol;

my $u       = temp_user();
my $newpass = "pass" . rand();
$u->set_password($newpass);
ok( $u->check_password($newpass), "password matches" );

my $res;

$res = do_req(
    "postevent",
    'tz'                 => 'guess',
    'subject'            => "new test post",
    'prop_current_mood'  => "happy",
    'prop_current_music' => "music",
    'event'              => "this is my post.  btw, my password is $newpass!",
);

is( $res->{success}, "OK", "made a post" )
    or die "failed to make post";

my $url    = $res->{url};
my $itemid = $res->{itemid};

my $gres = do_req(
    "getevents",
    'selecttype' => 'one',
    'itemid'     => $itemid,
);

is( $gres->{success}, "OK", "got items" );

my $eres = do_req(
    "editevent",
    itemid           => $itemid,
    event            => "new version of post.  password still $newpass.",
    subject          => "editted subject",
    prop_opt_noemail => 1
);

is( $eres->{success}, "OK", "did event" );

$gres = do_req_deep(
    "getevents",
    'selecttype' => 'one',
    'itemid'     => $itemid,
);

is( ref $gres->{events}, "ARRAY", "got item list back (in deep API mode)" )
    or die;
is( scalar @{ $gres->{events} }, 1, "just one item" )
    or die;
my $it = $gres->{events}[0];
is( $it->{itemid},        $itemid, "is correct itemid" );
is( $it->{props}{revnum}, 1,       "is 1st revision" );

# now let's edit it again, setting all the props we got back
{
    my %props;
    foreach my $p ( keys %{ $it->{props} } ) {

        # revnum and revtime can't be manually specified; skip these
        next if $p eq "revnum";
        next if $p eq "revtime";
        $props{"prop_$p"} = $it->{props}{$p};
    }

    $eres = do_req(
        "editevent",
        itemid  => $itemid,
        event   => "new version2 of post.  password still $newpass.",
        subject => "editted subject2",
        %props,
    );
    is( $eres->{success}, "OK", "did event, setting a bunch of round-tripped props" );
}

# should be rev2 now
$gres = do_req_deep(
    "getevents",
    'selecttype' => 'one',
    'itemid'     => $itemid,
);

$it = $gres->{events}[0];
is( $it->{props}{revnum}, 2, "is 2nd revision now" );

subtest 'Community slugs are stored on the journal cluster' => sub {
    plan skip_all => 'Requires two test clusters' unless @LJ::CLUSTERS >= 2;

    my ( $poster_cluster, $journal_cluster ) = @LJ::CLUSTERS;
    my $poster = temp_user( cluster => $poster_cluster );
    my $community;
    {
        local $LJ::DEFAULT_CLUSTER = [$journal_cluster];
        $community = temp_comm();
    }
    isnt( $poster->clusterid, $community->clusterid,
        'Poster and community use different clusters' );
    $poster->update_self( { status => 'A' } );
    ok( $poster->join_community( $community, 0, 1 ), 'Poster joins with posting access' );

    my $request = sub {
        my ( $mode, %args ) = @_;
        LJ::Entry->reset_singletons;
        my $error;
        my $response = LJ::Protocol::do_request(
            $mode,
            {
                ver        => $LJ::PROTOCOL_VER,
                username   => $poster->user,
                usejournal => $community->user,
                tz         => 'guess',
                security   => 'public',
                allowmask  => 0,
                subject    => 'Community slug test',
                event      => 'Community entry content',
                %args,
            },
            \$error,
            { noauth => 1 },
        );
        BAIL_OUT( "$mode failed: " . LJ::Protocol::error_message($error) ) unless $response;
        return $response;
    };

    my $slug_itemid = sub {
        my ($slug) = @_;
        my $entry = LJ::Entry->new( $community, slug => $slug );
        return $entry ? $entry->jitemid : undef;
    };

    my $posted   = $request->( 'postevent', slug => 'original-slug' );
    my $entry_id = $posted->{itemid};
    ok( $entry_id, 'Posted a community entry' );
    like( $posted->{url}, qr{/original-slug\.html$}, 'Posting returns the slug URL' );
    is( $slug_itemid->('original-slug'), $entry_id, 'Original slug resolves to the entry' );

    my $edited = $request->( 'editevent', itemid => $entry_id, slug => 'updated-slug' );
    like( $edited->{url}, qr{/updated-slug\.html$}, 'Editing returns the new slug URL' );
    is( $slug_itemid->('updated-slug'),  $entry_id, 'Updated slug resolves to the entry' );
    is( $slug_itemid->('original-slug'), undef,     'Changing the slug removes the old lookup' );

    my ($misplaced) =
        $poster->selectrow_array( 'SELECT slug FROM logslugs WHERE journalid = ? AND jitemid = ?',
        undef, $community->id, $entry_id );
    is( $misplaced, undef, 'No slug row is written to the poster cluster' );

    $request->( 'editevent', itemid => $entry_id, subject => 'Edit without a slug field' );
    is( $slug_itemid->('updated-slug'), $entry_id, 'Omitting the slug leaves it unchanged' );

    my $duplicate = $request->( 'postevent', slug => 'updated-slug', event => 'Another entry' );
    like( $duplicate->{message}, qr/already been used/, 'Duplicate slug reports a conflict' );
    is( $slug_itemid->('updated-slug'),
        $entry_id, 'Duplicate slug still points to its first entry' );

    my $cleared = $request->( 'editevent', itemid => $entry_id, slug => '' );
    like( $cleared->{url}, qr{/\d+\.html$}, 'Clearing the slug restores the numeric URL' );
    is( $slug_itemid->('updated-slug'), undef, 'Clearing the slug removes its lookup' );
};

#use Data::Dumper;
#print Dumper($gres);

sub do_req {
    my ( $mode, %args ) = @_;
    $args{mode}     = $mode;
    $args{ver}      = 1;          # supports unicode
    $args{user}     = $u->user;
    $args{password} = $newpass;

    my %res;
    my $flags = {};
    LJ::do_request( \%args, \%res, $flags );

    return \%res;
}

sub do_req_deep {
    my ( $mode, %args ) = @_;
    $args{ver}      = 1;          # supports unicode
    $args{username} = $u->user;
    $args{password} = $newpass;

    my $flags = {};
    my $err;
    return LJ::Protocol::do_request( $mode, \%args, \$err, $flags );
}

