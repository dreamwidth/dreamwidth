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

package LJ::NotificationMethod::IM;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';
use LJ::User;

sub can_digest { 0 };

# takes a $u
sub new {
    my $class = shift;

    croak "no args passed"
        unless @_;

    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { BML::ml('notification_method.im.title') }

sub help_url { "ljtalk_full" }

sub new_from_subscription {
    my $class = shift;
    my $subs = shift;

    return $class->new($subs->owner);
}

sub u {
    my $self = shift;
    croak "'u' is an object method"
        unless ref $self eq __PACKAGE__;

    if (my $u = shift) {
        croak "invalid 'u' passed to setter"
            unless LJ::isu($u);

        $self->{u} = $u;
    }

    croak "superfluous extra parameters"
        if @_;

    return $self->{u};
}

# send IMs for events passed in
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    my $u = $self->u;

    my @events = @_;
    croak "'notify' requires one or more events"
        unless @events;

    foreach my $ev (@events) {
        croak "invalid event passed" unless ref $ev;
        my $msg = $ev->as_im($u);
        $u->send_im(message => $msg);
    }

    return 1;
}

sub configured {
    my $class = shift;

    # FIXME: check if jabber server is configured
    return 1;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    # FIXME: check if user can use IM
    return $u->is_person ? 1 : 0;
}

sub url {
    my $class = shift;

    return LJ::Hooks::run_hook('jabber_link');
}

1;
