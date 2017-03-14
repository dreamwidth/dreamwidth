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

#
# Wrapper around MemCachedClient

use Cache::Memcached;
use strict;

package LJ::MemCache;

our $GET_DISABLED = 0;

# NOTE:  if you update the list of values stored in the cache here, you will
# need to increment the version number, too.
%LJ::MEMCACHE_ARRAYFMT = (
                          'user' =>
                          [qw[2 userid user caps clusterid dversion email password status statusvis statusvisdate
                              name bdate themeid moodthemeid opt_forcemoodtheme allow_infoshow allow_contactshow
                              allow_getljnews opt_showtalklinks opt_whocanreply opt_gettalkemail opt_htmlemail
                              opt_mangleemail useoverrides defaultpicid has_bio is_system
                              journaltype lang oldenc]],
                          'trust_group' => [qw[2 userid groupnum groupname sortorder is_public]],
                          # version #101 because old userpic format in memcached was an arrayref of
                          # [width, height, ...] and widths could have been 1 before, although unlikely
                          'userpic' => [qw[101 width height userid fmt state picdate location flags]],
                          'userpic2' => [qw[2 picid fmt width height state pictime md5base64 comment description flags location url]],
                          'talk2row' => [qw[1 nodetype nodeid parenttalkid posterid datepost state]],
                          'usermsg' => [qw[1 journalid parent_msgid otherid timesent type]],
                          'oauth_consumer' => [qw[1 consumer_id userid token secret name website createtime updatetime invalidatetime approved active]],
                          'oauth_request' => [qw[1 consumer_id userid token secret createtime verifier callback]],
                          'oauth_access' => [qw[1 consumer_id userid token secret createtime]],
                          );


my $memc;  # memcache object

sub init {
    my $opts = {};

    my $parser_class = LJ::conf_test($LJ::MEMCACHE_USE_GETPARSERXS) ? 'Cache::Memcached::GetParserXS'
                                                                    : 'Cache::Memcached::GetParser';
    # Eval, but we don't care about the result here. Loading errors will have been encountered
    # when Cache::Memcached was loaded, so we won't even see them here. This may not even return
    # true.
    eval "use $parser_class";

    # Check to see if the 'new' function/method is defined in the proper namespace, othewise don't
    # explicitly set a parser class. Cached::Memcached may have attempted to load the XS module, and
    # failed. This is a reasonable check to make sure it all went OK.
    if (eval 'defined &' . $parser_class . '::new') {
        $opts->{'parser_class'} = $parser_class;
    }

    $memc = Cache::Memcached->new($opts);
    reload_conf();
}

sub set_memcache {
    $memc = shift;
}

sub get_memcache {
    init() unless $memc;
    return $memc
}

sub client_stats {
    return $memc->{'stats'} || {};
}

sub reload_conf {
    return $memc if eval { $memc->doesnt_want_configuration; };

    $memc->set_servers(\@LJ::MEMCACHE_SERVERS);
    $memc->set_debug($LJ::DEBUG{'memcached'});
    $memc->set_pref_ip(\%LJ::MEMCACHE_PREF_IP);
    $memc->set_compress_threshold($LJ::MEMCACHE_COMPRESS_THRESHOLD);

    $memc->set_connect_timeout($LJ::MEMCACHE_CONNECT_TIMEOUT);
    $memc->set_cb_connect_fail($LJ::MEMCACHE_CB_CONNECT_FAIL);

    $memc->set_stat_callback(undef);
    $memc->set_readonly(1) if $ENV{LJ_MEMC_READONLY};

    return $memc;
}

sub forget_dead_hosts { $memc->forget_dead_hosts(); }
sub disconnect_all    { $memc->disconnect_all();    }

sub delete {
    # use delete time if specified
    return $memc->delete(@_) if defined $_[1];

    # else default to 4 seconds:
    # version 1.1.7 vs. 1.1.6
    $memc->delete(@_, 4) || $memc->delete(@_);
}

sub add       { ( defined $_[1] ) ? $memc->add( @_ )
                                  : $memc->add( $_[0],     '', $_[2] ); }
sub replace   { ( defined $_[1] ) ? $memc->replace( @_ )
                                  : $memc->replace( $_[0], '', $_[2] ); }
sub set       { ( defined $_[1] ) ? $memc->set( @_ )
                                  : $memc->set( $_[0],     '', $_[2] ); }
sub incr      { $memc->incr(@_);      }
sub decr      { $memc->decr(@_);      }

sub get       {
    return undef if $GET_DISABLED;
    $memc->get(@_);
}
sub get_multi {
    return {} if $GET_DISABLED || ! @_;
    $memc->get_multi(@_);
}

sub _get_sock { $memc->get_sock(@_);   }

sub run_command { $memc->run_command(@_); }


sub array_to_hash {
    my ($fmtname, $ar) = @_;
    my $fmt = $LJ::MEMCACHE_ARRAYFMT{$fmtname};
    return undef unless $fmt;
    return undef unless $ar && ref $ar eq "ARRAY" && $ar->[0] == $fmt->[0];
    my $hash = {};
    my $ct = scalar(@$fmt);
    for (my $i=1; $i<$ct; $i++) {
        $hash->{$fmt->[$i]} = $ar->[$i];
    }
    return $hash;
}

sub hash_to_array {
    my ($fmtname, $hash) = @_;
    my $fmt = $LJ::MEMCACHE_ARRAYFMT{$fmtname};
    return undef unless $fmt;
    return undef unless $hash && ref $hash;
    my $ar = [$fmt->[0]];
    my $ct = scalar(@$fmt);
    for (my $i=1; $i<$ct; $i++) {
        $ar->[$i] = $hash->{$fmt->[$i]};
    }
    return $ar;
}

sub get_or_set {
    my ($memkey, $code, $expire) = @_;
    my $val = LJ::MemCache::get($memkey);
    return $val if $val;
    $val = $code->();
    LJ::MemCache::set($memkey, $val, $expire);
    return $val;
}

1;
