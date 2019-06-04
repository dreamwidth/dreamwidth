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

package LJ::Test;
require Exporter;
use strict;
use Carp qw(croak);

use DW::Routing;
use DW::Request::Standard;
use HTTP::Request;

use DBI;
use LJ::ModuleCheck;
our @ISA    = qw(Exporter);
our @EXPORT = qw(memcache_stress with_fake_memcache temp_user temp_comm temp_feed routing_request);

my @temp_userids;    # to be destroyed later

END {
    return if $LJ::_T_NO_TEMP_USER_DESTROY;

    # clean up temporary usernames
    foreach my $uid (@temp_userids) {
        my $u = LJ::load_userid($uid) or next;
        $u->delete_and_purge_completely;
    }
}

$LJ::_T_FAKESCHWARTZ = 1 unless $LJ::_T_NOFAKESCHWARTZ;
my $theschwartz = undef;

sub theschwartz {
    return $theschwartz if $theschwartz;

    my $fakedb = "$LJ::HOME/t-theschwartz.sqlite";
    unlink $fakedb, "$fakedb-journal";
    my $fakedsn = "dbi:SQLite:dbname=$fakedb";

    my $load_sql = sub {
        my ($file) = @_;
        open my $fh, $file or die "Can't open $file: $!";
        my $sql = do { local $/; <$fh> };
        close $fh;
        split /;\s*/, $sql;
    };

    my $dbh = DBI->connect( $fakedsn, '', '', { RaiseError => 1, PrintError => 0 } );
    my @sql = $load_sql->("$LJ::HOME/t/data/schema-sqlite.sql");
    for my $sql (@sql) {
        $dbh->do($sql);
    }
    $dbh->disconnect;

    return $theschwartz = TheSchwartz->new(
        databases => [
            {
                dsn  => $fakedsn,
                user => '',
                pass => '',
            }
        ]
    );
}

sub temp_user {
    shift() if defined( $_[0] ) and $_[0] eq __PACKAGE__;
    my %args        = @_;
    my $underscore  = delete $args{'underscore'};
    my $journaltype = delete $args{'journaltype'} || "P";
    my $cluster     = delete $args{cluster};
    croak('unknown args') if %args;

    my $pfx = $underscore ? "_" : "t_";
    while (1) {
        my $username = $pfx . LJ::rand_chars( 15 - length $pfx );
        my $u        = LJ::User->create(
            user        => $username,
            name        => "test account $username",
            email       => "test\@$LJ::DOMAIN",
            journaltype => $journaltype,
            cluster     => $cluster,
        );
        next unless $u;
        push @temp_userids, $u->id;
        return $u;
    }
}

sub temp_comm {
    shift() if defined( $_[0] ) and $_[0] eq __PACKAGE__;

    # make a normal user
    my $u = temp_user();

    # update journaltype
    $u->update_self( { journaltype => 'C' } );

    # communities always have a row in 'community'
    my $dbh = LJ::get_db_writer();
    $dbh->do( "INSERT INTO community SET userid=?", undef, $u->{userid} );
    die $dbh->errstr if $dbh->err;

    return $u;
}

sub temp_feed {
    shift() if defined( $_[0] ) and $_[0] eq __PACKAGE__;

    # make a normal user
    my $u = temp_user();

    # update journaltype
    $u->update_self( { journaltype => 'Y' } );

    # communities always have a row in 'syndicated'
    my $dbh = LJ::get_db_writer();
    $dbh->do( "INSERT INTO syndicated (userid, synurl, checknext) VALUES (?,?,NOW())",
        undef, $u->id, "$LJ::SITEROOT/fakerss.xml#" . $u->user );

    die $dbh->errstr if $dbh->err;

    return $u;
}

sub with_fake_memcache (&) {
    my $cb        = shift;
    my $pre_mem   = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::FakeMemCache->new();
    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}

sub memcache_stress (&) {
    my $cb        = shift;
    my $pre_mem   = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::FakeMemCache->new();

    # run the callback once with no memcache server existing
    {
        local @LJ::MEMCACHE_SERVERS = ();
        LJ::MemCache::init();
        $cb->();
    }

    # now set a memcache server, but a new empty one, and run it twice
    # so the second invocation presumably has stuff in the cache
    # from the first one
    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}

# this is a quick check for whether memcache is functioning correctly
# using a bogus wsse_auth key - add fails when not working as configured
sub check_memcache {
    return 1 unless @LJ::MEMCACHE_SERVERS;    # OK if not set

    my $secs = time;
    return LJ::MemCache::add( "wsse_auth:xxx:$secs", 1, 1 );
}

sub routing_request {
    my ( $uri, %opts ) = @_;

    my $method       = $opts{method} || 'GET';
    my %routing_data = %{ $opts{routing_data} || {} };

    LJ::start_request();

    my $req = HTTP::Request->new( $method => $uri );

    if ( $opts{content} ) {
        $req->content( $opts{content} );
        $req->header( 'Content-Length', length( $opts{content} ) );
    }

    $opts{setup_http_request}->($req) if $opts{setup_http_request};

    # Just in case, but this shouldn't get set in a non-web context
    DW::Request->reset;
    my $r = DW::Request::Standard->new($req);

    $opts{setup_dw_request}->($r) if $opts{setup_dw_request};

    my $rv = DW::Routing->call(%routing_data);
    $r->status($rv) unless $rv eq $r->OK;

    return $r;
}

package LJ::Test::FakeMemCache;

# duck-typing at its finest!
# this is a fake Cache::Memcached object which implements the
# memcached server locally in-process, for testing.  kinda,
# except it has no LRU or expiration times.

sub new {
    my ($class) = @_;
    return bless { 'data' => {}, }, $class;
}

sub add {
    my ( $self, $fkey, $val, $exptime ) = @_;
    my $key = _key($fkey);
    return 0 if exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub replace {
    my ( $self, $fkey, $val, $exptime ) = @_;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub incr {
    my ( $self, $fkey, $optval ) = @_;
    $optval ||= 1;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} += $optval;
    return 1;
}

sub decr {
    my ( $self, $fkey, $optval ) = @_;
    $optval ||= 1;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} -= $optval;
    return 1;
}

sub set {
    my ( $self, $fkey, $val, $exptime ) = @_;
    my $key = _key($fkey);
    $self->{data}{$key} = $val;
    return 1;
}

sub delete {
    my ( $self, $fkey ) = @_;
    my $key = _key($fkey);
    delete $self->{data}{$key};
    return 1;
}

sub get {
    my ( $self, $fkey ) = @_;
    my $key = _key($fkey);
    return $self->{data}{$key};
}

sub get_multi {
    my $self = shift;
    my $ret  = {};
    foreach my $fkey (@_) {
        my $key = _key($fkey);
        $ret->{$key} = $self->{data}{$key} if exists $self->{data}{$key};
    }
    return $ret;
}

sub _key {
    my $fkey = shift;
    return $fkey->[1] if ref $fkey eq "ARRAY";
    return $fkey;
}

# tell LJ::MemCache::reload_conf not to call 'weird' methods on us
# that we don't simulate.
sub doesnt_want_configuration {
    1;
}

sub disconnect_all    { }
sub forget_dead_hosts { }

package LJ::User;

# post a fake entry in a community journal
sub t_post_fake_comm_entry {
    my $u    = shift;
    my $comm = shift;
    my %opts = @_;

    # set the 'usejournal' and tell the protocol
    # to not do any checks for posting access
    $opts{usejournal}      = $comm->{user};
    $opts{usejournal_okay} = 1;

    return $u->t_post_fake_entry(%opts);
}

# post a fake entry in this user's journal
sub t_post_fake_entry {
    my $u    = shift;
    my %opts = @_;

    use LJ::Protocol;

    my $security  = delete $opts{security} || 'public';
    my $proto_sec = $security;
    if ( $security eq "friends" ) {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || "test suite post.";
    my $body    = delete $opts{body}    || "This is a test post from $$ at " . time() . "\n";

    my %req = (
        mode     => 'postevent',
        ver      => $LJ::PROTOCOL_VER,
        user     => $u->{user},
        password => '',
        event    => $body,
        subject  => $subject,
        tz       => 'guess',
        security => $proto_sec,
    );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    # pass-thru opts
    $req{usejournal} = $opts{usejournal} if $opts{usejournal};
    $flags->{usejournal_okay} = $opts{usejournal_okay} if $opts{usejournal_okay};

    LJ::do_request( \%req, \%res, $flags );

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";
    my $ju      = $opts{usejournal} ? LJ::load_user( $opts{usejournal} ) : $u;

    return LJ::Entry->new( $ju, jitemid => $jitemid );
}

package LJ::Entry;

use LJ::Talk;

# returns LJ::Comment object or dies on failure
sub t_enter_comment {
    my ( $entry, %opts ) = @_;
    my $jitemid = $entry->jitemid;

    # entry journal/u
    my $entryu = $entry->journal;

    # poster u
    my $u = delete $opts{u};
    $u = 0 unless ref $u;

    my $parent       = delete $opts{parent};
    my $parenttalkid = $parent ? $parent->jtalkid : 0;

    # add some random stuff for dupe protection
    my $rand = "t=" . time() . " r=" . rand();

    my $subject = delete $opts{subject} || "comment subject [$rand]";
    my $body    = delete $opts{body}    || "comment body\n\n$rand";

    my $err;

    my $commentref = {
        u       => $u,
        state   => 'A',
        subject => $subject,
        body    => $body,
        %opts,
        parenttalkid => $parenttalkid,
    };

    LJ::Talk::Post::post_comment(
        $entry->poster, $entry->journal, $commentref,
        { talkid => $parenttalkid, state => 'A' },
        { itemid => $jitemid,      state => 'A', opt_noemail => 1 }, \$err,
    );

    my $jtalkid = $commentref->{talkid};

    die "Could not post comment: $err" unless $jtalkid;

    delete $entry->{_loaded_comments};
    delete $entry->{_loaded_talkdata};

    return LJ::Comment->new( $entryu, jtalkid => $jtalkid );
}

package LJ::Comment;

# reply to a comment instance, takes same opts as LJ::Entry::t_enter_comment
sub t_reply {
    my ( $comment, %opts ) = @_;
    my $entry = $comment->entry;
    $opts{parent} = $comment;
    return $entry->t_enter_comment(%opts);
}

1;
