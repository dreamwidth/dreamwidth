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

package LJ::Event::SecurityAttributeChanged;

use strict;

use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ( $class, $u, $opts ) = @_;
    croak 'Not an LJ::User' unless LJ::isu($u);

    my $_get_logtime = sub {
        my $u      = shift;
        my $action = shift;
        my $opts   = shift;

        my $ip = $opts->{ip};

        die "Missing credentials" unless $ip && $action;

        # We can't be sure which order the keys were saved in,
        # so search for both possibilities (old/new or new/old).

        # $action == 1 -- deleted
        my $extra =
            ( 1 == $action )
            ? "'old=V&new=D', 'new=D&old=V'"
            : "'old=D&new=V', 'new=V&old=D'";

        my $dbcr = LJ::get_cluster_reader($u);
        my $sth =
            $dbcr->prepare( "SELECT logtime, ip FROM userlog"
                . " WHERE userid=? AND extra IN ($extra)"
                . " ORDER BY logtime DESC LIMIT 2" );
        $sth->execute( $u->{userid} );
        my ( $logtime, $logip ) = $sth->fetchrow_array;

        # Check for errors
        die "This event (uid=$u->{userid}, extra=$extra) was not found in logs" unless $logtime;

        my ( $logtime2, $logip2 ) = $sth->fetchrow_array;
        die "Second record about this event was found in log"
            if $logtime2 && $logtime2 == $logtime && ( $logip2 ne $logip );

        die "The event (uid=$u->{userid}, extra=$extra, logtime=$logtime) was found in log,"
            . " but with wrong ip address ($logip, but not $ip)"
            if $ip ne $logip;

        return $logtime;
    };

    my $_get_rename_id = sub {
        my $u      = shift;
        my $action = shift;
        my $opts   = shift;

        my $ip           = $opts->{ip};
        my $old_username = $opts->{old_username};
        my $userid       = $u->{userid};

        # TODO: check is $u a user object?
        die "Missing credentials" unless $ip && $action && $old_username;

        my $dbh = LJ::get_db_writer($u);
        my $sth =
            $dbh->prepare( "SELECT UNIX_TIMESTAMP(timechange) as utimechange, oldvalue"
                . " FROM infohistory"
                . " WHERE userid=? AND what='username'"
                . " ORDER BY utimechange DESC LIMIT 2" );
        $sth->execute($userid);
        my ( $timechange, $oldvalue ) = $sth->fetchrow_array;

        # Check for errors
        die "This event (uid=$userid, what=username) was not found in logs"
            unless $timechange;

        die
"Event (uid=$userid, what=username) has wrong old username: $oldvalue instead of $old_username"
            if $oldvalue ne $old_username;

        my ( $timechange2, $oldvalue2 ) = $sth->fetchrow_array;
        die "Second record about this event was found in log"
            if $timechange2 && $timechange2 == $timechange && ( $oldvalue2 ne $oldvalue );

        # Remember ip address
        $dbh->do( "UPDATE infohistory"
                . " SET other='ip=$ip'"
                . " WHERE userid=$userid"
                . "   AND what='username'"
                . "   AND UNIX_TIMESTAMP(timechange)=$timechange" );

        return $timechange;
    };

    my %actions = (
        'account_deleted'   => [ 1, $_get_logtime ],
        'account_activated' => [ 2, $_get_logtime ],
        'account_renamed'   => [ 3, $_get_rename_id ],
    );

    die 'Wrong action parameter' unless exists( $actions{ $opts->{action} } );

    my $action = $actions{ $opts->{action} }[0];
    return $class->SUPER::new( $u, $action,
        $actions{ $opts->{action} }[1]->( $u, $action, $opts ) );
}

sub arg_list {
    return ( "Action", "(depends on action)" );
}

sub is_common { 1 }    # As seen in LJ/Event.pm, event fired without subscription

# Override this with a false value make subscriptions to this event not show up in normal UI
sub is_visible { 0 }

# Whether Inbox is always subscribed to
sub always_checked { 0 }

sub is_significant { 1 }

# override parent class subscriptions method to always return
# a subscription object for the user
sub raw_subscriptions {
    my ( $class, $self, %args ) = @_;

    $args{ntypeid} = LJ::NotificationMethod::Email->ntypeid;    # Email

    return $class->_raw_always_subscribed( $self, %args );
}

sub get_subscriptions {
    my ( $self, $u, $subid ) = @_;

    unless ($subid) {
        my $row = {
            userid  => $u->{userid},
            ntypeid => LJ::NotificationMethod::Email->ntypeid,    # Email
        };

        return LJ::Subscription->new_from_row($row);
    }

    return $self->SUPER::get_subscriptions( $u, $subid );
}

sub _arg1_to_mlkey {
    my $action     = shift;
    my @ml_actions = ( 'account_deleted', 'account_activated', 'account_renamed', );

    return 'esn.security_attribute_changed.' . $ml_actions[ $action - 1 ] . '.';
}

sub as_email_subject {
    my ( $self, $u ) = @_;

    return LJ::Lang::get_default_text(
        _arg1_to_mlkey( $self->arg1 ) . 'email_subject2',
        {
            'user' => $u->{user}
        }
    );
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;

    my $action  = $self->arg1;
    my $logtime = $self->arg2;

    my $_get_params_from_logtime = sub {
        my ( $u, $logtime ) = @_;

        my $userid = $u->{userid};
        my $dbcr   = LJ::get_cluster_reader($u);
        my ( $datetime, $remoteid, $ip, $uniq ) = $dbcr->selectrow_array(
            "SELECT FROM_UNIXTIME(logtime), remoteid, ip, uniq"
                . " FROM userlog"
                . " WHERE userid=? AND logtime=? LIMIT 1",
            undef, $userid, $logtime
        );
        return undef unless $remoteid;
        my $remoteuser = LJ::get_username($remoteid);
        return (
            datetime   => $datetime,
            remoteid   => $remoteid,
            remoteuser => $remoteuser,
            ip         => $ip,
            uniq       => $uniq,
            userid     => $userid,
        );
    };

    my $_get_params_from_rename_id = sub {
        my ( $u, $timechange_stamp ) = @_;
        my $userid = $u->{userid};

        my $dbh = LJ::get_db_reader($u);
        my $sth =
            $dbh->prepare( "SELECT oldvalue, other"
                . " FROM infohistory"
                . " WHERE userid=? AND what='username' AND UNIX_TIMESTAMP(timechange)=?" );
        $sth->execute( $userid, $timechange_stamp );
        my ( $old_name, $other ) = $sth->fetchrow_array;

        # Check for errors
        unless ($old_name) {
            croak "This event (uid=$userid, what=username) was not found in logs";
            return undef;
        }

        # Convert $timechange from GMT to local for user
        my $offset = 0;
        LJ::get_timezone( $u, \$offset );
        my $timechange = LJ::mysql_time( $timechange_stamp + 60 * 60 * $offset, 0 );

        $other =~ /ip=(.+)/;
        my ($ip) = ($1);

        return (
            oldname  => $old_name,
            ip       => $ip,
            datetime => $timechange,
        );
    };

    my @actions =
        ( $_get_params_from_logtime, $_get_params_from_logtime, $_get_params_from_rename_id, );

    my %logparams = $actions[ $action - 1 ]( $u, $logtime );

    if ( %logparams && $logparams{datetime} ) {
        ( $logparams{date}, $logparams{time} ) = split( / /, $logparams{datetime} );
    }

    my $vars = {
        'user'     => $u->{user},
        'username' => $u->{name},
        'sitename' => $LJ::SITENAME,
        'siteroot' => $LJ::SITEROOT,
        %logparams,
    };

    my $iscomm = $u->is_community ? '.comm' : '';

    return LJ::Lang::get_default_text( _arg1_to_mlkey($action) . 'email_text2' . $iscomm, $vars );
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return '' unless $u;
    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return '' unless $u;
    return _as_email( $self, $u, 1 );
}

1;
