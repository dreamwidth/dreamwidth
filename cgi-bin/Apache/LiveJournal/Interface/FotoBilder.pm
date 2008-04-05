#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::FotoBilder;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED
                         HTTP_MOVED_PERMANENTLY BAD_REQUEST);

sub run_method
{
    my $cmd = shift;

    # Available functions for this interface.
    my $interface = {
        'checksession'       => \&checksession,
        'get_user_info'      => \&get_user_info,
        'makechals'          => \&makechals,
        'set_quota'          => \&set_quota,
        'user_exists'        => \&user_exists,
        'get_auth_challenge' => \&get_auth_challenge,
        'get_groups'         => \&get_groups,
    };
    return undef unless $interface->{$cmd};

    return $interface->{$cmd}->(@_);
}

sub handler
{
    my $r = shift;
    my $uri = $r->uri;
    return 404 unless $uri =~ m#^/interface/fotobilder(?:/(\w+))?$#;
    my $cmd = $1;

    return BAD_REQUEST unless $r->method eq "POST";

    $r->content_type("text/plain");
    $r->send_http_header();

    my %POST = $r->content;
    my $res = run_method($cmd, \%POST)
        or return BAD_REQUEST;

    $res->{"fotobilder-interface-version"} = 1;

    $r->print(join("", map { "$_: $res->{$_}\n" } keys %$res));

    return OK;
}

# Is there a current LJ session?
# If so, return info.
sub get_user_info
{
    my $POST = shift;
    BML::reset_cookies();
    $LJ::_XFER_REMOTE_IP = $POST->{'remote_ip'};

    # try to get a $u from the passed uid or user, falling back to the ljsession cookie
    my $u;
    if ($POST->{uid}) {
        $u = LJ::load_userid($POST->{uid});
    } elsif ($POST->{user}) {
        $u = LJ::load_user($POST->{user});
    } else {
        my $sess = LJ::Session->session_from_fb_cookie;
        $u = $sess->owner if $sess;
    }
    return {} unless $u && $u->{'journaltype'} =~ /[PI]/;

    my $defaultpic = $u->userpic;

    my %ret = (
               user            => $u->{user},
               userid          => $u->{userid},
               statusvis       => $u->{statusvis},
               can_upload      => can_upload($u),
               gallery_enabled => can_upload($u),
               diskquota       => LJ::get_cap($u, 'disk_quota') * (1 << 20), # mb -> bytes
               fb_account      => LJ::get_cap($u, 'fb_account'),
               fb_usage        => LJ::Blob::get_disk_usage($u, 'fotobilder'),
               all_styles      => LJ::get_cap($u, 'fb_allstyles'),
               is_identity     => $u->{journaltype} eq 'I' ? 1 : 0,
               userpic_url     => $defaultpic ? $defaultpic->url : undef,
               lj_can_style    => $u->get_cap('styles') ? 1 : 0,
               userpic_count   => $u->get_userpic_count,
               userpic_quota   => $u->userpic_quota,
               esn             => $u->can_use_esn ? 1 : 0,
               new_messages    => $u->new_message_count,
               directory       => $u->get_cap('directory') ? 1 : 0,
               makepoll        => $u->get_cap('makepoll') ? 1 : 0,
               sms             => $u->can_use_sms ? 1 : 0,
               );

    # when the set_quota rpc call is executed (below), a placholder row is inserted
    # into userblob.  it's just used for livejournal display of what we last heard
    # fotobilder disk usage was, but we need to subtract that out before we report
    # to fotobilder how much disk the user is using on livejournal's end
    $ret{diskused} = LJ::Blob::get_disk_usage($u) - $ret{fb_usage};

    return \%ret unless $POST->{fullsync};

    LJ::fill_groups_xmlrpc($u, \%ret);
    return \%ret;
}

# Forcefully push user info out to FB.
# We use this for cases where we don't want to wait for
# sync cache timeouts, such as user suspensions.
sub push_user_info
{
    my $uid = LJ::want_userid( shift() );
    return unless $uid;

    my $ret = get_user_info({ uid => $uid });

    eval "use XMLRPC::Lite;";
    return if $@;

    return XMLRPC::Lite
        -> proxy("$LJ::FB_SITEROOT/interface/xmlrpc")
        -> call('FB.XMLRPC.update_userinfo', $ret)
        -> result;
}

# get_user_info above used to be called 'checksession', maintain
# an alias for compatibility
sub checksession { get_user_info(@_); }

sub get_groups {
    my $POST = shift;
    my $u = LJ::load_user($POST->{user});
    return {} unless $u;

    my %ret = ();
    LJ::fill_groups_xmlrpc($u, \%ret);
    return \%ret;
}

# Pregenerate a list of challenge/responses.
sub makechals
{
    my $POST = shift;
    my $count = int($POST->{'count'}) || 1;
    if ($count > 50) { $count = 50; }
    my $u = LJ::load_user($POST->{'user'});
    return {} unless $u;

    my %ret = ( count => $count );

    for (my $i=1; $i<=$count; $i++) {
        my $chal = LJ::rand_chars(40);
        my $resp = Digest::MD5::md5_hex($chal . Digest::MD5::md5_hex($u->password));
        $ret{"chal_$i"} = $chal;
        $ret{"resp_$i"} = $resp;
    }

    return \%ret;
}

# Does the user exist?
sub user_exists
{
    my $POST = shift;
    my $u = LJ::load_user($POST->{'user'});
    return {} unless $u;

    return {
        exists => 1,
        can_upload => can_upload($u),
    };
}

# Mirror FB quota information over to LiveJournal.
# 'user' - username
# 'used' - FB disk usage in bytes
sub set_quota
{
    my $POST = shift;
    my $u = LJ::load_userid($POST->{'uid'});
    return {} unless $u && defined $POST->{'used'};

    return {} unless $u->writer;

    my $used = $POST->{'used'} * (1 << 10);  # Kb -> bytes
    my $result = $u->do('REPLACE INTO userblob SET ' .
                        'domain=?, length=?, journalid=?, blobid=0',
                        undef, LJ::get_blob_domainid('fotobilder'),
                        $used, $u->{'userid'});

    LJ::set_userprop($u, "fb_num_pubpics", $POST->{'pub_pics'});

    return {
        status => ($result ? 1 : 0),
    };
}

sub get_auth_challenge
{
    my $POST = shift;

    return {
        chal => LJ::challenge_generate($POST->{goodfor}+0),
    };
}

#########################################################################
# non-interface helper functions
#

# Does the user have upload access?
sub can_upload
{
    my $u = shift;

    return LJ::get_cap($u, 'fb_account')
        && LJ::get_cap($u, 'fb_can_upload') ? 1 : 0;
}

1;
