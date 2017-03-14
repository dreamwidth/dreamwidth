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

package LJ::Event::CommunityJoinApprove;
use strict;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $cu) = @_;
    foreach ($u, $cu) {
        croak 'Not an LJ::User' unless LJ::isu($_);
    }
    return $class->SUPER::new($u, $cu->{userid});
}

sub arg_list {
    return ( "Comm userid" );
}


sub is_common { 1 } # As seen in LJ/Event.pm, event fired without subscription

# Override this with a false value make subscriptions to this event not show up in normal UI
sub is_visible { 0 }

# Whether Inbox is always subscribed to
sub always_checked { 1 }

my @_ml_strings_en = (
    'esn.comm_join_approve.email_subject',  # 'Your Request to Join [[community]] community',
    'esn.add_friend_community',             # '[[openlink]]Add community "[[community]]" to your friends page reading list[[closelink]]',
    'esn.comm_join_approve.email_text',     # 'Dear [[user]],
                                            #
                                            #Your request to join the "[[community]]" community has been approved.
                                            #If you wish to add this community to your friends page reading list,
                                            #click the link below.
                                            #
                                            #[[options]]
                                            #Please note that replies to this email are not sent to the community\'s maintainer(s). If you
                                            #have any questions, you will need to contact them directly.
                                            #
                                            #Regards,
                                            #[[sitename]] Team
                                            #
                                            #',
);

sub as_email_subject {
    my ($self, $u) = @_;
    my $cu      = $self->community;

    return LJ::Lang::get_default_text( 'esn.comm_join_approve.email_subject',
                                       { 'community' => $cu->{user} } );
}

sub _as_email {
    my ($self, $u, $cu, $is_html) = @_;

    my $vars = {
            'user'      => $u->{name},
            'username'  => $u->{name},
            'community' => $cu->{user},
            'sitename'  => $LJ::SITENAME,
            'siteroot'  => $LJ::SITEROOT,
    };

    $vars->{'options'} =
        $self->format_options( $is_html, undef, $vars,
            {
                'esn.add_friend_community'  => [ 1, "$LJ::SITEROOT/circle/" . $cu->{user} . "/edit?action=subscribe" ],
            } );

    return LJ::Lang::get_default_text( 'esn.comm_join_approve.email_text', $vars );
}

sub as_email_string {
    my ($self, $u) = @_;
    my $cu = $self->community;
    return '' unless $u && $cu;
    return _as_email($self, $u, $cu, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    my $cu = $self->community;
    return '' unless $u && $cu;
    return _as_email($self, $u, $cu, 1);
}

sub community {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

1;
