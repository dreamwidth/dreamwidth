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

package LJ::Event::CommunityInvite;
use strict;
use LJ::Entry;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu, $commu) = @_;
    foreach ($u, $fromu, $commu) {
        LJ::errobj('Event::CommunityInvite', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $fromu->{userid}, $commu->{userid});
}

sub arg_list {
    return ( "From userid", "Comm userid" );
}

sub is_common { 0 }

my @_ml_strings = (
    'esn.comm_invite.email.subject',# "You've been invited to join [[community]]"
    'esn.comm_invite.email',        # 'Hi [[user]],
                                    #
                                    # [[maintainer]] has invited you to join the community [[community]]!
                                    #
                                    # You can:'
    'esn.manage_invitations2',       # '[[openlink]]Accept or decline the invitation[[closelink]]'
    'esn.read_last_comm_entries',   # '[[openlink]]Read the latest entries in [[journal]][[closelink]]'
    'esn.view_profile',             # '[[openlink]]View [[postername]]'s profile[[closelink]]',
    'esn.add_watch',                # '[[openlink]]Subscribe to [[journal]][[closelink]]',
);

sub as_email_subject {
    my ($self, $u) = @_;
    my $cu      = $self->comm;

    return LJ::Lang::get_default_text( 'esn.comm_invite.email.subject',
                                       { 'community' => $cu->user } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    # Precache text lines
    LJ::Lang::get_default_text_multi( \@_ml_strings );

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

    return LJ::Lang::get_default_text( 'esn.comm_invite.email', $vars ) .
        $self->format_options( $is_html, undef, $vars,
        {
            'esn.manage_invitations2'       => [ 1, "$LJ::SITEROOT/manage/invites" ],
            'esn.read_last_comm_entries'    => [ 2, $community_url ],
            'esn.view_profile'              => [ 3, $community_profile ],
            'esn.add_watch'                 => [ $u->watches( $self->comm ) ? 0 : 4,
                                                "$LJ::SITEROOT/circle/$community_user/edit?action=subscribe" ],
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
    return sprintf("The user %s has <a href=\"$LJ::SITEROOT/manage/invites\">invited you to join</a> the community %s.",
                   $self->inviter->ljuser_display,
                   $self->comm->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $self->comm->profile_url . "'>View Profile</a>";
    $ret .= " | <a href='$LJ::SITEROOT/manage/invites'>Accept or Decline</a>"
        unless $self->u->member_of( $self->comm );
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

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return BML::ml('event.comm_invite'); # "I receive an invitation to join a community";
}

sub available_for_user {
    my ($class, $u, $subscr) = @_;

    return 1;
}

package LJ::Error::Event::CommunityInvite;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityInvite passed bogus u object: $self->{u}";
}

1;
