package LJ::M::ProfilePage;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;
    my $u = shift || die;
    my $self = bless {
        u => $u,
        max_friends_show => 500,
        max_friendof_show => 150,
    }, (ref $class || $class);
    $self->_init;
    return $self;
}

sub _init {
    my $self = shift;

    $self->{banned_userids} = {};
    if (my $uidlist = LJ::load_rel_user($self->{u}, 'B')) {
        $self->{banned_userids}{$_} = 1 foreach @$uidlist;
    }

    my $u = $self->{u};

    my $remote = LJ::get_remote();
    $self->{remote_isowner} = ($remote && $remote->id == $u->id);

    ### load user props.  some don't apply to communities
    {
        my @props = qw(opt_whatemailshow country state city zip renamedto
                       journaltitle journalsubtitle public_key
                       url urlname opt_hidefriendofs dont_load_members
                       opt_blockrobots adult_content admin_content_flag
                       opt_showmutualfriends fb_num_pubpics opt_showschools);
        if ($u->is_community) {
            push @props, qw(moderated comm_theme);
        } elsif ($u->is_syndicated) {
            push @props, qw(rssparseerror);
        } else {
            push @props, qw(gizmo aolim icq yahoo msn gender jabber google_talk skype last_fm_user);
        }
        LJ::load_user_props($u, @props);
    }
}


sub max_friends_show { $_[0]{max_friends_show} }
sub max_friendof_show { $_[0]{max_friendof_show} }

sub should_hide_friendof {
    my ($self, $uid) = @_;
    return $self->{banned_userids}{$uid};
}

sub head_meta_tags {
    my $self = shift;
    my $u = $self->{u};
    my $jbase = $u->journal_base;
    my $remote = LJ::get_remote();
    my $ret;

    $ret .= "<link rel='alternate' type='application/rss+xml' title='RSS' href='$jbase/data/rss' />\n";
    $ret .= "<link rel='alternate' type='application/atom+xml' title='Atom' href='$jbase/data/atom' />\n";
    $ret .= "<link rel='alternate' type='application/rdf+xml' title='FOAF' href='$jbase/data/foaf' />\n";
    if ($u->email_visible($remote)) {
        my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
        $ret .= "<meta name=\"foaf:maker\" content=\"foaf:mbox_sha1sum '$digest'\" />\n";
    }

    return $ret;
}

sub has_journal {
    my $pm = shift;
    return ! $pm->{u}->is_identity && ! $pm->{u}->is_syndicated;
}

sub remote_isowner { $_[0]{remote_isowner} }

sub remote_can_post {
    my $pm = shift;
    my $remote = LJ::get_remote()
        or return 0;
    return 0 unless $pm->has_journal;
    return 0 if $remote->is_identity;
    return LJ::can_use_journal($remote->id, $pm->{u}->user);
}

sub header_bar_links {
    my $pm = shift;
    my @ret;
    my $label = $pm->{u}->is_community ? $BML::ML{'.monitor.comm2'} : $BML::ML{'.monitor.user'};

    my $user = $pm->{u}->user;
    push @ret, "<a href='$LJ::SITEROOT/manage/circle/add.bml?user=$user'><img src='$LJ::IMGPREFIX/btn_addfriend.gif' width='22' height='20' alt='$label' title='$label' align='middle' border='0' /></a>";

    my $remote = LJ::get_remote();

    if ($pm->remote_can_post) {
        if ($pm->remote_isowner) {
            $label = $BML::ML{'.label.postalt'};
        } else {
            $label = BML::ml('.label.post', {'journal' => $user});
        }

        $label = LJ::ehtml($label);
        push @ret, "<a href='$LJ::SITEROOT/update.bml?usejournal=$user'><img src='$LJ::IMGPREFIX/btn_edit.gif' width='22' height='20' alt='$label' title='$label' align='middle' border='0' /></a>";
    }

    unless ($pm->{u}->is_identity || $pm->{u}->is_syndicated) {
        $label = LJ::ehtml($BML::ML{'.label.memories'});
        push @ret, "<a href='$LJ::SITEROOT/tools/memories.bml?user=$user'><img src='$LJ::IMGPREFIX/btn_memories.gif' width='22' height='20' alt='$label' title='$label' align='middle' border='0' /></a>";
    }

     unless ($LJ::DISABLED{'tellafriend'} || $pm->{u}->is_identity) {
         push @ret, "<a href='$LJ::SITEROOT/tools/tellafriend.bml?user=$user'><img align='middle' hspace='2' vspace='2' src='$LJ::IMGPREFIX/btn_tellfriend.gif' width='22' height='20' alt='$BML::ML{'.tellafriend'}' title='$BML::ML{'.tellafriend'}' border='0' /></a>";
     }

     unless ($LJ::DISABLED{'offsite_journal_search'} || ! $pm->has_journal) {
         push @ret, "<a href='$LJ::SITEROOT/tools/search.bml?journal=$user'><img align='middle' hspace='2' vspace='2' src='$LJ::IMGPREFIX/btn_search.gif' width='22' height='20' alt='$BML::ML{'.label.searchjournal'}' title='$BML::ML{'.label.searchjournal'}' border='0' /></a>";
     }

     if ($remote && !$pm->{u}->is_syndicated && $remote->can_use_esn) {
         push @ret, "<a href='$LJ::SITEROOT/manage/subscriptions/user.bml?journal=$user'>" .
             LJ::img("track", "", { 'align' => 'middle' }) . "</a>";
     }

    foreach my $row (LJ::run_hooks("userinfo_linkele", $pm->{u}, $remote)) {
        push @ret, @$row;
    }

    return @ret;
}

1;
