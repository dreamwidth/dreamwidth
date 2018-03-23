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

package LJ::OpenID;

use strict;
use Digest::SHA1 qw(sha1 sha1_hex);
use LJ::OpenID::Cache;

BEGIN {
    $LJ::OPTMOD_OPENID_CONSUMER = $LJ::OPENID_CONSUMER ? eval "use Net::OpenID::Consumer; 1;" : 0;
    $LJ::OPTMOD_OPENID_SERVER   = $LJ::OPENID_SERVER   ? eval "use Net::OpenID::Server; 1;" : 0;
}

# returns boolean whether consumer support is enabled and available
sub consumer_enabled {
    return 0 unless $LJ::OPENID_CONSUMER;
    return $LJ::OPTMOD_OPENID_CONSUMER || eval "use Net::OpenID::Consumer; 1;";
}

# returns boolean whether server support is enabled and available
sub server_enabled {
    return 0 unless $LJ::OPENID_SERVER;
    return $LJ::OPTMOD_OPENID_CONSUMER || eval "use Net::OpenID::Server; 1;";
}

sub server {
    my ($get, $post) = @_;

    my %args = ( %{ $get || {} }, %{ $post || {} } );

    return Net::OpenID::Server->new(
                                    args         => \%args,

                                    get_user     => \&LJ::get_remote,
                                    is_identity  => sub {
                                        my ($u, $ident) = @_;
                                        return LJ::OpenID::is_identity($u, $ident, $get);
                                    },
                                    is_trusted   => \&LJ::OpenID::is_trusted,

                                    setup_url    => "$LJ::SITEROOT/openid/approve",

                                    server_secret => \&LJ::OpenID::server_secret,
                                    secret_gen_interval => 3600,
                                    secret_expire_age   => 86400 * 14,
                                    );
}

# Returns a Consumer object
# When planning to verify identity, needs GET
# arguments passed in
sub consumer {
    my $get_args = shift || {};

    # always use a paranoid useragent
    my $ua = LJ::get_useragent( role => "OpenID",
                                timeout => 10,
                                max_size => 1024*300, );

    my $cache = undef;
    if (! $LJ::OPENID_STATELESS && scalar(@LJ::MEMCACHE_SERVERS)) {
        $cache = LJ::OpenID::Cache->new;
    }

    my $csr = Net::OpenID::Consumer->new(
                                         ua => $ua,
                                         args => $get_args,
                                         cache => $cache,
                                         consumer_secret => \&LJ::OpenID::consumer_secret,
                                         debug => $LJ::IS_DEV_SERVER || 0,
                                         required_root => $LJ::SITEROOT,
                                         );

    return $csr;
}

sub consumer_secret {
    my $time = shift;
    return server_secret($time - $time % 3600);
}

sub server_secret {
    my $time = shift;
    my ($t2, $secret) = LJ::get_secret($time);
    die "ASSERT: didn't get t2 (t1=$time)" unless $t2;
    die "ASSERT: didn't get secret (t2=$t2)" unless $secret;
    die "ASSERT: time($time) != t2($t2)\n" unless $t2 == $time;
    return $secret;
}

sub is_trusted {
    my ($u, $trust_root, $is_identity) = @_;
    return 0 unless $u;
    # we always look up $is_trusted, even if $is_identity is false, to avoid timing attacks

    my $dbh = LJ::get_db_writer();
    my ($endpointid, $duration) = $dbh->selectrow_array("SELECT t.endpoint_id, t.duration ".
                                                        "FROM openid_trust t, openid_endpoint e ".
                                                        "WHERE t.userid=? AND t.endpoint_id=e.endpoint_id AND e.url=?",
                                                        undef, $u->{userid}, $trust_root);
    return 0 unless $endpointid;
    return 1;
}

sub is_identity {
    my ($u, $ident, $get) = @_;
    return 0 unless $u && $u->is_person;

    # canonicalize trailing slash
    $ident .= "/" unless $ident =~ m!/$!;

    my $user = $u->user;
    my $url  = $u->journal_base . "/";

    return 1 if
        $ident eq $url ||
        # legacy:
        $ident eq "$LJ::SITEROOT/users/$user/" ||
        $ident eq "$LJ::SITEROOT/~$user/" ||
        $ident eq "http://$user.$LJ::USER_DOMAIN/" ||
        $ident eq "https://$user.$LJ::USER_DOMAIN/";

    return 0;
}

sub getmake_endpointid {
    my $site = shift;

    my $dbh = LJ::get_db_writer()
        or return undef;

    my $rv = $dbh->do("INSERT IGNORE INTO openid_endpoint (url) VALUES (?)", undef, $site);
    my $end_id;
    if ($rv > 0) {
        $end_id = $dbh->{'mysql_insertid'};
    } else {
        $end_id = $dbh->selectrow_array("SELECT endpoint_id FROM openid_endpoint WHERE url=?",
                                        undef, $site);
    }
    return $end_id;
}

sub add_trust {
    my ($u, $site) = @_;

    my $end_id = LJ::OpenID::getmake_endpointid($site)
        or return 0;

    my $dbh = LJ::get_db_writer()
        or return undef;

    my $rv = $dbh->do("REPLACE INTO openid_trust (userid, endpoint_id, duration, trust_time) ".
                      "VALUES (?,?,?,UNIX_TIMESTAMP())", undef, $u->{userid}, $end_id, "always");
    return $rv;
}

# From Digest::HMAC
sub hmac_sha1_hex {
    unpack("H*", &hmac_sha1);
}
sub hmac_sha1 {
    hmac($_[0], $_[1], \&sha1, 64);
}
sub hmac {
    my($data, $key, $hash_func, $block_size) = @_;
    $block_size ||= 64;
    $key = &$hash_func($key) if length($key) > $block_size;

    my $k_ipad = $key ^ (chr(0x36) x $block_size);
    my $k_opad = $key ^ (chr(0x5c) x $block_size);

    &$hash_func($k_opad, &$hash_func($k_ipad, $data));
}

# Returns 1 if destination identity server
# is blocked
sub blocked_hosts {
    my $csr = shift;

    # uncomment this if you need to bypass this check for testing purposes
    # return do { my $dummy = 0; \$dummy; } if $LJ::IS_DEV_SERVER;

    my $tried_local_id = 0;
    $csr->ua->blocked_hosts( [
                            sub {
                                my $dest = shift;

                                if ($dest =~ /(^|\.)\Q$LJ::DOMAIN\E$/i) {
                                    $tried_local_id = 1;
                                    return 1;
                                }
                                return 0;
                            } ] );
    return \$tried_local_id;
}

1;
