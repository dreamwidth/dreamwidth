package LJ::Event::Befriended;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;
    foreach ($u, $fromu) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $fromu->{userid});
}

sub is_common { 0 }

my @_ml_strings_en = (
    'esn.public',                       # 'public',
    'esn.befriended.subject',           # '[[who]] added you as a friend!',
    'esn.add_friend',                   # '[[openlink]]Add [[journal]] to your Friends list[[closelink]]',
    'esn.read_journal',                 # '[[openlink]]Read [[postername]]\'s journal[[closelink]]',
    'esn.view_profile',                 # '[[openlink]]View [[postername]]\'s profile[[closelink]]',
    'esn.edit_friends',                 # '[[openlink]]Edit Friends[[closelink]]',
    'esn.edit_groups',                  # '[[openlink]]Edit Friends groups[[closelink]]',
    'esn.befriended.email_text',        # 'Hi [[user]],
                                        #
                                        #[[poster]] has added you to their Friends list. They will now be able to read your[[entries]] entries on their Friends page.
                                        #
                                        #You can:',
    'esn.befriended.openid_email_text', # 'Hi [[user]],
                                        #
                                        #[[poster]] has added you to their Friends list.
                                        #
                                        #You can:',
);

sub as_email_subject {
    my ($self, $u) = @_;
    return LJ::Lang::get_text($u->prop('browselang'), 'esn.befriended.subject', undef, { who => $self->friend->display_username } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang        = $u->prop('browselang');
    my $user        = $is_html ? ($u->ljuser_display) : ($u->display_username);
    my $poster      = $is_html ? ($self->friend->ljuser_display) : ($self->friend->display_username);
    my $postername  = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $journal_profile = $self->friend->profile_url;

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    my $entries = LJ::is_friend($u, $self->friend) ? "" : " " . LJ::Lang::get_text($lang, 'esn.public', undef);
    my $is_open_identity = $self->friend->openid_identity;

    my $vars = {
        who         => $self->friend->display_username,
        poster      => $poster,
        postername  => $poster,
        journal     => $poster,
        user        => $user,
        entries     => $entries,
    };

    my $email_body_key = 'esn.befriended.' .
        ($u->openid_identity ? 'openid_' : '' ) . 'email_text';

    return LJ::Lang::get_text($lang, $email_body_key, undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.add_friend'      => [ LJ::is_friend($u, $self->friend) ? 0 : 1,
                                            # Why not $self->friend->addfriend_url ?
                                            "$LJ::SITEROOT/manage/circle/add.bml?user=$postername" ],
            'esn.read_journal'    => [ $is_open_identity ? 0 : 2,
                                            $journal_url ],
            'esn.view_profile'    => [ 3, $journal_profile ],
            'esn.edit_friends'    => [ 4, "$LJ::SITEROOT/manage/circle/edit.bml" ],
            'esn.edit_groups'     => [ 5, "$LJ::SITEROOT/manage/circle/editgroups.bml" ],
        }
    );
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has added you as a friend.",
                   $self->friend->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $u = $self->u;
    my $friend = $self->friend;
    my $ret .= "<div class='actions'>";
    $ret .= $u->is_friend($friend)
            ? " <a href='" . $friend->profile_url . "'>View Profile</a>"
            : " <a href='" . $friend->addfriend_url . "'>Add Friend</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;
    return sprintf("%s has added you as a friend.",
                   $self->friend->{user});
}

sub as_sms {
    my $self = shift;
    return sprintf("%s has added you to their friends list. Reply with ADD %s to add them " .
                   "to your friends list. Standard rates apply.",
                   $self->friend->user, $self->friend->user);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";
    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    if ($journal_is_owner) {
        return BML::ml('event.befriended.me');   # "Someone adds me as a friend";
    } else {
        my $user = $journal->ljuser_display;
        return BML::ml('event.befriended.user', { user => $user } ); # "Someone adds $user as a friend";
    }
}

sub content {
    my ($self, $target) = @_;
    return $self->as_html_actions;
}

1;
