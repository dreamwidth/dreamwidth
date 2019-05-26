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

package LJ::Event::CommunityJoinRequest;
use strict;
use LJ::Entry;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ( $class, $u, $requestor, $comm ) = @_;

    foreach ( $u, $requestor, $comm ) {
        LJ::errobj( 'Event::CommunityJoinRequest', u => $_ )->throw unless LJ::isu($_);
    }

    # Shouldn't these be method calls? $requestor->id, etc.
    return $class->SUPER::new( $u, $requestor->{userid}, $comm->{userid} );
}

sub arg_list {
    return ( "Requestor userid", "Comm userid" );
}

sub is_common { 0 }

sub comm {
    my $self = shift;
    return LJ::load_userid( $self->arg2 );
}

sub requestor {
    my $self = shift;
    return LJ::load_userid( $self->arg1 );
}

sub authurl {
    my $self = shift;

    # we need to force the authaction from the master db; otherwise, replication
    # delays could cause this to fail initially
    my $arg  = "targetid=" . $self->requestor->id;
    my $auth = LJ::get_authaction( $self->comm->id, "comm_join_request", $arg, { force => 1 } )
        or die "Unable to fetch authcode";

    return "$LJ::SITEROOT/approve/" . $auth->{aaid} . "." . $auth->{authcode};
}

sub as_html {
    my $self = shift;
    return sprintf(
        "The user %s has <a href=\"%s\">requested to join</a> the community %s.",
        $self->requestor->ljuser_display,
        $self->comm->member_queue_url,
        $self->comm->ljuser_display
    );
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret    .= " <a href='" . $self->requestor->profile_url . "'>View Profile</a> |";
    $ret    .= " <a href='" . $self->comm->member_queue_url . "'>Manage Members</a>";
    $ret    .= "</div>";

    return $ret;
}

sub content {
    my ( $self, $target ) = @_;

    return $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    return sprintf(
        "The user %s has requested to join the community %s.",
        $self->requestor->display_username,
        $self->comm->display_username
    );
}

my @_ml_strings_en = (
    'esn.community_join_requst.subject',    # '[[comm]] membership request by [[who]]',
    'esn.manage_membership_reqs'
    ,    # '[[openlink]]Manage [[communityname]]\'s membership requests[[closelink]]',
    'esn.manage_community',                    # '[[openlink]]Manage your communities[[closelink]]',
    'esn.community_join_requst.email_text',    # 'Hi [[maintainer]],
                                               #
        #[[username]] has requested to join your community, [[communityname]].
        #
        #You can:',
);

sub as_email_subject {
    my ( $self, $u ) = @_;
    return LJ::Lang::get_default_text(
        'esn.community_join_requst.subject',
        {
            comm => $self->comm->display_username,
            who  => $self->requestor->display_username,
        }
    );
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;

    my $maintainer = $is_html ? ( $u->ljuser_display ) : ( $u->user );
    my $username =
        $is_html ? ( $self->requestor->ljuser_display ) : ( $self->requestor->display_username );
    my $user          = $self->requestor->user;
    my $communityname = $self->comm->user;
    my $community = $is_html ? ( $self->comm->ljuser_display ) : ( $self->comm->display_username );
    my $auth_url  = $self->authurl;
    my $rej_url   = $auth_url;
    $rej_url =~ s/approve/reject/;
    my $queue_url = $self->comm->member_queue_url;

    # Precache text
    LJ::Lang::get_default_text_multi( \@_ml_strings_en );

    my $vars = {
        maintainer    => $maintainer,
        username      => $username,
        communityname => $community,
    };

    return LJ::Lang::get_default_text( 'esn.community_join_requst.email_text', $vars )
        . $self->format_options(
        $is_html, undef, $vars,
        {
            'esn.manage_request_approve' => [ 1, $auth_url ],
            'esn.manage_request_reject'  => [ 2, $rej_url ],
            'esn.manage_membership_reqs' => [ 3, $queue_url ],
            'esn.manage_community'       => [ 4, "$LJ::SITEROOT/communities/list" ],
        }
        );
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 1 );
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    return BML::ml('event.community_join_requst')
        ;    # Someone requests membership in a community I maintain';
}

sub available_for_user {
    my ( $class, $u, $subscr ) = @_;

    return $u->is_identity ? 0 : 1;
}

package LJ::Error::Event::CommunityJoinRequest;
sub fields { 'u' }

sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityJoinRequest passed bogus u object: $self->{u}";
}

1;
