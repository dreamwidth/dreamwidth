package LJ::Event::CommunityInvite;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu, $commu) = @_;
    foreach ($u, $fromu, $commu) {
        LJ::errobj('Event::CommunityInvite', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $fromu->{userid}, $commu->{userid});
}

sub is_common { 0 }

my @_ml_strings = (
    'esn.comm_invite.subject',      # "You've been invited to join [[user]]"
    'esn.comm_invite.email',        # 'Hi [[user]],
                                    #
                                    # [[maintainer]] has invited you to join the community [[community]]!
                                    #
                                    # You can:'
    'esn.manage_invitations',       # '[[openlink]]Manage your invitations[[closelink]]'
    'esn.read_last_comm_entries',   # '[[openlink]]Read the latest entries in [[journal]][[closelink]]'
    'esn.view_profile',             # '[[openlink]]View [[postername]]'s profile[[closelink]]',
    'esn.add_friend',               # '[[openlink]]Add [[journal]] to your Friends list[[closelink]]'
);

sub as_email_subject {
    my $self = shift;
    return sprintf "You've been invited to join %s", $self->comm->user;
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang        = $u->prop('browselang');

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings);

    my $username    = $u->user;
    my $user        = $is_html ? $u->ljuser_display : $u->display_username;

    my $maintainer  = $is_html ? $self->inviter->ljuser_display : $self->inviter->display_username;

    my $communityname       = $self->comm->display_username;
    my $community           = $is_html ? $self->comm->ljuser_display : $communityname;

    my $community_url       = $self->comm->journal_base;
    my $community_profile   = $self->comm->profile_url;
    my $community_user      = $self->comm->user;

    my $vars = {
        user            => $user,
        maintainer      => $maintainer,
        community       => $community,
        postername      => $communityname,
        journal         => $communityname,
    };

    return LJ::Lang::get_text($lang, 'esn.comm_invite.email', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.manage_invitations'        => [ 1, "$LJ::SITEROOT/manage/invites.bml" ],
            'esn.read_last_comm_entries'    => [ 2, $community_url ],
            'esn.view_profile'              => [ 3, $community_profile ],
            'esn.add_friend'                => [ $u->watches( $self->comm ) ? 0 : 4,
                                                "$LJ::SITEROOT/manage/circle/add.bml?user=$community_user" ],
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

sub inviter {
    my $self = shift;
    my $u = LJ::load_userid($self->arg1);
    return $u;
}

sub comm {
    my $self = shift;
    my $u = LJ::load_userid($self->arg2);
    return $u;
}

sub as_html {
    my $self = shift;
    return sprintf("The user %s has <a href=\"$LJ::SITEROOT/manage/invites.bml\">invited you to join</a> the community %s.",
                   $self->inviter->ljuser_display,
                   $self->comm->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $self->comm->profile_url . "'>View Profile</a>";
    $ret .= " <a href='$LJ::SITEROOT/manage/invites.bml'>Join Community</a>";
    $ret .= "</div>";

    return $ret;
}

sub content {
    my ($self, $target) = @_;
    return $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    return sprintf("The user %s has invited you to join the community %s.",
                   $self->inviter->display_username,
                   $self->comm->display_username);
}

sub as_sms {
    my $self = shift;

    return sprintf("%s sent you an invitation to join the community %s. Visit the invitation page to accept",
                   $self->inviter->display_username,
                   $self->comm->display_username);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return BML::ml('event.comm_invite'); # "I receive an invitation to join a community";
}

package LJ::Error::Event::CommunityInvite;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityInvite passed bogus u object: $self->{u}";
}

1;
