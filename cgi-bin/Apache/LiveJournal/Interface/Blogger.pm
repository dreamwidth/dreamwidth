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
# Blogger API wrapper for LJ

use strict;
package LJ::Util;

sub blogger_deserialize {
    my $content = shift;
    my $event = { 'props' => {} };
    if ($content =~ s!<title>(.*?)</title>!!) {
        $event->{'subject'} = $1;
    }
    if ($content =~ s/(^|\n)lj-mood:\s*(.*)\n//i) {
        $event->{'props'}->{'current_mood'} = $2;
    }
    if ($content =~ s/(^|\n)lj-music:\s*(.*)\n//i) {
        $event->{'props'}->{'current_music'} = $2;
    }
    $content =~ s/^\s+//; $content =~ s/\s+$//;
    $event->{'event'} = $content;
    return $event;
}

sub blogger_serialize {
    my $event = shift;
    my $header;
    my $content;
    if ($event->{'subject'}) {
        $header .= "<title>$event->{'subject'}</title>";
    }
    if ($event->{'props'}->{'current_mood'}) {
        $header .= "lj-mood: $event->{'props'}->{'current_mood'}\n";
    }
    if ($event->{'props'}->{'current_music'}) {
        $header .= "lj-music: $event->{'props'}->{'current_music'}\n";
    }
    $content .= "$header\n" if $header;
    $content .= $event->{'event'};
    return $content;
}

# ISO 8601 (many formats available)
# "yyyy-mm-dd hh:mm:ss" => "yyyymmddThh:mm:ss"  (literal T)
sub mysql_date_to_iso {
    my $dt = shift;
    $dt =~ s/ /T/;
    $dt =~ s/\-//g;
    return $dt;
}

package Apache::LiveJournal::Interface::Blogger;

# for Class::Autouse
sub load { 1 }

sub newPost {
    shift;
    my ($appkey, $journal, $user, $password, $content, $publish) = @_;

    my $err;
    my $event = LJ::Util::blogger_deserialize($content);

    my $req = {
        'usejournal' => $journal ne $user ? $journal : undef,
        'ver' => 1,
        'username' => $user,
        'password' => $password,
        'event' => $event->{'event'},
        'subject' => $event->{'subject'},
        'props' => $event->{'props'},
        'tz'    => 'guess',
    };

    $req->{'props'}->{'interface'} = "blogger";

    my $res = LJ::Protocol::do_request("postevent", $req, \$err);

    if ($err) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($err))
            ->faultcode(substr($err, 0, 3));
    }

    return "$journal:$res->{'itemid'}";
}

sub deletePost {
    shift;
    my ($appkey, $postid, $user, $password, $content, $publish) = @_;
    return editPost(undef, $appkey, $postid, $user, $password, "", $publish);
}

sub editPost {
    shift;
    my ($appkey, $postid, $user, $password, $content, $publish) = @_;

    die "Invalid postid\n" unless $postid =~ /^([\w-]+):(\d+)$/;
    my ($journal, $itemid) = ($1, $2);

    my $event = LJ::Util::blogger_deserialize($content);

    my $req = {
        'usejournal' => $journal ne $user ? $journal : undef,
        'ver' => 1,
        'username' => $user,
        'password' => $password,
        'event' => $event->{'event'},
        'subject' => $event->{'subject'},
        'props' => $event->{'props'},
        'itemid' => $itemid,
    };

    my $err;
    my $res = LJ::Protocol::do_request("editevent", $req, \$err);

    if ($err) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($err))
            ->faultcode(substr($err, 0, 3));
    }

    return 1;
}

sub getUsersBlogs {
    shift;
    my ($appkey, $user, $password) = @_;

    my $u = LJ::load_user($user) or die "Invalid login\n";
    die "Invalid login\n" unless LJ::auth_okay($u, $password);

    my $ids = LJ::load_rel_target($u, 'P');
    my $us = LJ::load_userids(@$ids);
    my @list = ($u);
    foreach (sort { $a->{user} cmp $b->{user} } values %$us) {
        next unless $_->is_visible;
        push @list, $_;
    }

    return [ map { {
        'url' => LJ::journal_base($_) . "/",
        'blogid' => $_->{'user'},
        'blogName' => $_->{'name'},
    } } @list ];
}

sub getRecentPosts {
    shift;
    my ($appkey, $journal, $user, $password, $numposts) = @_;

    $numposts = int($numposts);
    $numposts = 1 if $numposts < 1;
    $numposts = 50 if $numposts > 50;

    my $req = {
        'usejournal' => $journal ne $user ? $journal : undef,
        'ver' => 1,
        'username' => $user,
        'password' => $password,
        'selecttype' => 'lastn',
        'howmany' => $numposts,
    };

    my $err;
    my $res = LJ::Protocol::do_request("getevents", $req, \$err);

    if ($err) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($err))
            ->faultcode(substr($err, 0, 3));
    }

    return [ map { {
        'content' => LJ::Util::blogger_serialize($_),
        'userID' => $_->{'poster'} || $journal,
        'postId' => "$journal:$_->{'itemid'}",
        'dateCreated' => LJ::Util::mysql_date_to_iso($_->{'eventtime'}),
    } } @{$res->{'events'}} ];
}

sub getPost {
    shift;
    my ($appkey, $postid, $user, $password) = @_;

    die "Invalid postid\n" unless $postid =~ /^(\w+):(\d+)$/;
    my ($journal, $itemid) = ($1, $2);

    my $req = {
        'usejournal' => $journal ne $user ? $journal : undef,
        'ver' => 1,
        'username' => $user,
        'password' => $password,
        'selecttype' => 'one',
        'itemid' => $itemid,
    };

    my $err;
    my $res = LJ::Protocol::do_request("getevents", $req, \$err);

    if ($err) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($err))
            ->faultcode(substr($err, 0, 3));
    }

    die "Post not found\n" unless $res->{'events'}->[0];

    return map { {
        'content' => LJ::Util::blogger_serialize($_),
        'userID' => $_->{'poster'} || $journal,
        'postId' => "$journal:$_->{'itemid'}",
        'dateCreated' => LJ::Util::mysql_date_to_iso($_->{'eventtime'}),
    } } $res->{'events'}->[0];
}

sub getTemplate { die "$LJ::SITENAME doesn't support Blogger Templates.  To customize your journal, visit $LJ::SITENAME/customize/"; }
*setTemplate = \&getTemplate;

sub getUserInfo {
    shift;
    my ($appkey, $user, $password) = @_;

    my $u = LJ::load_user($user) or die "Invalid login\n";
    die "Invalid login\n" unless LJ::auth_okay($u, $password);

    LJ::load_user_props($u, "url");

    return {
        'userid' => $u->{'userid'},
        'nickname' => $u->{'user'},
        'firstname' => $u->{'name'},
        'lastname' => $u->{'name'},
        'email' => $u->email_raw,
        'url' => $u->{'url'},
    };
}

1;
