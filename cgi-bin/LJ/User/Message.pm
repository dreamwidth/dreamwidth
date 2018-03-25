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

package LJ::User;
use strict;
no warnings 'uninitialized';

use Carp;
use Text::Fuzzy;
use LJ::Subscription;

########################################################################
###  16. Email-Related Functions

=head2 Email-Related Functions
=cut

sub accounts_by_email {
    my ( $u, $email ) = @_;
    $email ||= $u->email_raw if LJ::isu( $u );
    return undef unless $email;

    my $dbr = LJ::get_db_reader() or die "Couldn't get db reader";
    my $userids = $dbr->selectcol_arrayref(
                        "SELECT userid FROM email WHERE email=?",
                        undef, $email );
    die $dbr->errstr if $dbr->err;
    return $userids ? @$userids : ();
}


sub delete_email_alias {
    my $u = $_[0];

    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM email_aliases WHERE alias=?",
              undef, $u->site_email_alias );

    return 0 if $dbh->err;
    return 1;
}


sub email_for_feeds {
    my $u = shift;

    # don't display if it's mangled
    return if $u->prop("opt_mangleemail") eq "Y";

    my $remote = LJ::get_remote();
    return $u->email_visible($remote);
}


sub email_raw {
    my $u = shift;
    my $userid = $u->userid;
    $u->{_email} ||= LJ::MemCache::get_or_set( [$userid, "email:$userid"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array( "SELECT email FROM email WHERE userid=?",
                                      undef, $userid );
    } );
    return $u->{_email};
}

sub has_same_email_as {
    my ( $u, $other ) = @_;
    croak "invalid user object passed" unless LJ::isu( $u ) && LJ::isu( $other );

    my $email_1 = lc( $u->email_raw );
    my $email_2 = lc( $other->email_raw );
    return 1 if $email_1 eq $email_2;

    # if unequal, try stripping any +mailbox addressing
    $email_1 =~ s/\+[^@]+@/@/;
    $email_2 =~ s/\+[^@]+@/@/;
    return $email_1 eq $email_2;
}

sub email_status {
    my $u = shift;
    return $u->{status};
}


# in scalar context, returns user's email address.  given a remote user,
# bases decision based on whether $remote user can see it.  in list context,
# returns all emails that can be shown
sub email_visible {
    my ($u, $remote) = @_;

    return scalar $u->emails_visible($remote);
}

# returns an array of emails based on the user's display prefs
# A: actual email address
# D: display email address
# L: local email address
# B: both actual + local email address
# V: both display + local email address

sub emails_visible {
    my ($u, $remote) = @_;

    return () if $u->is_identity || $u->is_syndicated;

    # security controls
    return () unless $u->share_contactinfo($remote);

    my $whatemail = $u->opt_whatemailshow;

    # some classes of users we want to have their contact info hidden
    # after so much time of activity, to prevent people from bugging
    # them for their account or trying to brute force it.
    my $hide_contactinfo = sub {
        return 0 if $LJ::IS_DEV_SERVER;
        my $hide_after = $u->get_cap( "hide_email_after" );
        return 0 unless $hide_after;
        my $active = $u->get_timeactive;
        return $active && (time() - $active) > $hide_after * 86400;
    };

    return () if $whatemail eq "N" || $hide_contactinfo->();

    my @emails = ();

    if ( $whatemail eq "A" || $whatemail eq "B" ) {
        push @emails, $u->email_raw if $u->email_raw;
    } elsif ( $whatemail eq "D" || $whatemail eq "V" ) {
        my $profile_email = $u->prop( 'opt_profileemail' );
        push @emails, $profile_email if $profile_email;
    }

    if ( $whatemail eq "B" || $whatemail eq "V" || $whatemail eq "L" ) {
        push @emails, $u->site_email_alias
            unless $u->prop( 'no_mail_alias' );
    }
    return wantarray ? @emails : $emails[0];
}


sub is_validated {
    my $u = shift;
    return $u->email_status eq "A";
}


# return the setting indicating how a user can be found by their email address
# Y - Findable, N - Not findable, H - Findable but identity hidden
sub opt_findbyemail {
    my $u = shift;

    if ($u->raw_prop('opt_findbyemail') =~ /^(N|Y|H)$/) {
        return $u->raw_prop('opt_findbyemail');
    } else {
        return undef;
    }
}


# initiate reset of user's email
# newemail: the new address provided (not validated?)
# err: reference for error messages
# emailsucc: send email if defined, report success if reference
# update_opts: additional options for the update_user call
sub reset_email {
    my ( $u, $newemail, $err, $emailsucc, $update_opts ) = @_;
    my $errsub = sub { $$err = $_[0] if ref $err; return undef };

    my $dbh = LJ::get_db_writer();
    $dbh->do( "UPDATE infohistory SET what='emailreset'" .
              " WHERE userid=? AND what='email'", undef, $u->id ) or
        return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr );

    $u->infohistory_add( 'emailreset', $u->email_raw, $u->email_status )
        if $u->email_raw ne $newemail; # record only if it changed

    $update_opts ||= { status => 'T' };
    $update_opts->{email} = $newemail;
    $u->update_self( $update_opts ) or
        return $errsub->( LJ::Lang::ml( "email.emailreset.error",
                                        { user => $u->user } ) );

    if ( $LJ::T_SUPPRESS_EMAIL ) {
        $$emailsucc = 1 if ref $emailsucc;  # pretend we sent it
    } elsif ( defined $emailsucc ) {
        my $aa = LJ::register_authaction( $u->id, "validateemail", $newemail );
        my $auth = "$aa->{aaid}.$aa->{authcode}";
        my $sent = LJ::send_mail( {
            to => $newemail,
            from => $LJ::ADMIN_EMAIL,
            subject => LJ::Lang::ml( "email.emailreset.subject" ),
            body => LJ::Lang::ml( "email.emailreset.body",
                                  { user => $u->user,
                                    sitename => $LJ::SITENAME,
                                    siteroot => "$LJ::SITEROOT/",
                                    auth => $auth } ),
        } );
        $$emailsucc = $sent if ref $emailsucc;
    }
}


sub set_email {
    my ($u, $email) = @_;
    return LJ::set_email($u->id, $email);
}


sub site_email_alias {
    my $u = $_[0];
    my $alias = $u->user . "\@$LJ::USER_DOMAIN";
    return $alias;
}


sub update_email_alias {
    my $u = $_[0];

    return unless $u && $u->can_have_email_alias;
    return if $u->prop("no_mail_alias");
    return unless $u->is_validated;

    my $dbh = LJ::get_db_writer();
    $dbh->do( "REPLACE INTO email_aliases (alias, rcpt) VALUES (?,?)",
              undef, $u->site_email_alias, $u->email_raw );

    return 0 if $dbh->err;
    return 1;
}


sub validated_mbox_sha1sum {
    my $u = shift;

    # must be validated
    return undef unless $u->is_validated;

    # must have one on file
    my $email = $u->email_raw;
    return undef unless $email;

    # return SHA1, which does not disclose the actual value
    return Digest::SHA1::sha1_hex('mailto:' . $email);
}


########################################################################
###  25. Subscription, Notifiction, and Messaging Functions

=head2 Subscription, Notifiction, and Messaging Functions
=cut

# this is the count used to check the maximum subscription count
sub active_inbox_subscription_count {
    my $u = shift;
    return scalar ( grep { $_->active && $_->enabled } $u->find_subscriptions(method => 'Inbox') );
}


sub can_add_inbox_subscription {
    my $u = shift;
    return $u->active_inbox_subscription_count >= $u->max_subscriptions ? 0 : 1;
}


# can this user use ESN?
sub can_use_esn {
    my $u = $_[0];
    return 0 if $u->is_community || $u->is_syndicated;
    return LJ::is_enabled( 'esn' );
}


# 1/0 if someone can send a message to $u
sub can_receive_message {
    my ($u, $sender) = @_;

    my $opt_usermsg = $u->opt_usermsg;
    return 0 if $opt_usermsg eq 'N' || !$sender;
    return 0 if $u->has_banned($sender);
    return 0 if $opt_usermsg eq 'M' && !$u->mutually_trusts($sender);
    return 0 if $opt_usermsg eq 'F' && !$u->trusts($sender);

    return 1;
}


# delete all of a user's subscriptions
sub delete_all_subscriptions {
    return LJ::Subscription->delete_all_subs( @_ );
}


# delete all of a user's subscriptions
sub delete_all_inactive_subscriptions {
    return LJ::Subscription->delete_all_inactive_subs( @_ );
}


# ensure that this user does not have more than the maximum number of subscriptions
# allowed by their cap, and enable subscriptions up to their current limit
sub enable_subscriptions {
    my $u = shift;

    # first thing, disable everything they don't have caps for
    # and make sure everything is enabled that should be enabled
    map { $_->available_for_user($u) ? $_->enable : $_->disable } $u->find_subscriptions(method => 'Inbox');

    my $max_subs = $u->get_cap('subscriptions');
    my @inbox_subs = grep { $_->active && $_->enabled } $u->find_subscriptions(method => 'Inbox');

    if ((scalar @inbox_subs) > $max_subs) {
        # oh no, too many subs.
        # disable the oldest subscriptions that are "tracking" subscriptions
        my @tracking = grep { $_->is_tracking_category } @inbox_subs;

        # oldest subs first
        @tracking = sort {
            return $a->createtime <=> $b->createtime;
        } @tracking;

        my $need_to_deactivate = (scalar @inbox_subs) - $max_subs;

        for (1..$need_to_deactivate) {
            my $sub_to_deactivate = shift @tracking;
            $sub_to_deactivate->deactivate if $sub_to_deactivate;
        }
    } else {
        # make sure all subscriptions are activated
        my $need_to_activate = $max_subs - (scalar @inbox_subs);

        # get deactivated subs
        @inbox_subs = grep { $_->active && $_->available_for_user } $u->find_subscriptions(method => 'Inbox');

        for (1..$need_to_activate) {
            my $sub_to_activate = shift @inbox_subs;
            $sub_to_activate->activate if $sub_to_activate;
        }
    }
}


sub esn_inbox_default_expand {
    my $u = shift;

    my $prop = $u->raw_prop('esn_inbox_default_expand');
    return $prop ne 'N';
}

# search for a subscription
*find_subscriptions = \&has_subscription;
sub has_subscription {
    my ($u, %params) = @_;
    croak "No parameters" unless %params;

    return LJ::Subscription->find($u, %params);
}


sub max_subscriptions {
    my $u = shift;
    return $u->get_cap('subscriptions');
}


# return the URL to the send message page
sub message_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return undef unless LJ::is_enabled('user_messaging');
    return "$LJ::SITEROOT/inbox/compose?user=" . $u->user;
}


sub new_message_count {
    my $u = shift;
    my $inbox = $u->notification_inbox;
    my $count = $inbox->unread_count;

    return $count || 0;
}


sub notification_archive {
    my $u = shift;
    return LJ::NotificationArchive->new($u);
}


# Returns the NotificationInbox for this user
*inbox = \&notification_inbox;
sub notification_inbox {
    my $u = shift;
    return LJ::NotificationInbox->new($u);
}


# opt_usermsg options
# Y - Registered Users
# F - Trusted Users
# M - Mutually Trusted Users
# N - Nobody
sub opt_usermsg {
    my $u = shift;
    my $prop = $u->raw_prop('opt_usermsg');

    if ( defined $prop && $prop =~ /^(Y|F|M|N)$/ ) {
        return $prop;
    } else {
        return 'Y';
    }
}


# subscribe to an event
sub subscribe {
    my ($u, %opts) = @_;
    croak "No subscription options" unless %opts;

    return LJ::Subscription->create($u, %opts);
}


sub subscription_count {
    my $u = shift;
    return scalar LJ::Subscription->subscriptions_of_user($u);
}


sub subscriptions {
    my $u = shift;
    return LJ::Subscription->subscriptions_of_user($u);
}


########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
###  16. Email-Related Functions

=head2 Email-Related Functions (LJ)
=cut

# loads the valid tlds as a hashref
sub load_valid_tlds {
    return $LJ::VALID_EMAIL_DOMAINS
        if $LJ::VALID_EMAIL_DOMAINS;

    my %domains = map { lc $_ => 1 }
                    grep { $_ && $_ !~ /^#/ }
                    split( /\r?\n/, LJ::load_include( 'tlds' ) );

    return $LJ::VALID_EMAIL_DOMAINS = \%domains;
}

# <LJFUNC>
# name: LJ::check_email
# des: checks for and rejects bogus e-mail addresses.
# info: Checks that the address is of the form username@some.domain,
#        does not contain invalid characters. in the username, is a valid domain.
#       Also checks for mis-spellings of common webmail providers,
#       and web addresses instead of an e-mail address.
# args:
# returns: nothing on success, or error with error message if invalid/bogus e-mail address
# </LJFUNC>
sub check_email
{
    my ($email, $errors, $post, $checkbox, $errorcodes) = @_;

    my $force_spelling = ref( $post ) && $post->{force_spelling};

    # Trim off whitespace and force to lowercase.
    $email =~ s/^\s+//;
    $email =~ s/\s+$//;
    $email = lc $email;

    my $reject = sub {
        my $errcode = shift;
        my $errmsg = shift;
        push @$errors, $errmsg if ref( $errors );
        push @$errorcodes, $errcode if ref( $errorcodes );
        return;
    };

    # Empty email addresses are not good.
    unless ($email) {
        return $reject->("empty",
                         "The email address cannot be blank.");
    }

    # Check that the address is of the form username@some.domain.
    my ($username, $domain);
    if ($email =~ /^([^@]+)@([^@]+)/) {
        $username = $1;
        $domain = $2;
    } else {
        return $reject->("bad_form",
                         "You did not give a valid email address.  An email address looks like username\@some.domain");
    }

    # Check the username for invalid characters.
    unless ($username =~ /^[^\s\",;\(\)\[\]\{\}\<\>]+$/) {
        return $reject->("bad_username",
                         "You have invalid characters in the email address username.");
    }

    # Check the domain name.
    my $valid_tlds = LJ::load_valid_tlds();
    unless ($domain =~ /^[\w-]+(?:\.[\w-]+)*\.(\w+)$/ && $valid_tlds->{$1})
    {
        return $reject->("bad_domain",
                         "The email address domain is invalid.");
    }

    # Catch misspellings of gmail.com, yahoo.com, hotmail.com, outlook.com,
    # aol.com, live.com.
    # https://github.com/dreamwidth/dw-free/issues/993#issuecomment-357466645
    # explains where 3 comes from.
    my $tf_domain = Text::Fuzzy->new( $domain, max => 3, trans => 1 );
    my @common_domains = ( 'gmail.com', 'yahoo.com', 'hotmail.com',
                           'outlook.com', 'aol.com', 'live.com',
                           'mail.com', 'ymail.com' );
    my $nearest = $tf_domain->nearest( \@common_domains );
    my $bad_spelling = defined $nearest && $tf_domain->last_distance > 0;

    # Keep the checkbox if it was checked before, to stop it alternating
    # between present/absent on successive submissions with other errors
    if ( ref( $checkbox ) && ( $bad_spelling || $force_spelling ) ) {
        $$checkbox = "<input type=\"checkbox\" name=\"force_spelling\" id=\"force_spelling\" "
                   . ( $force_spelling ? "checked=\"checked\" " : "" ) . "/>&nbsp;"
                   . "<label for=\"force_spelling\">Yes I'm sure this is correct</label>";
    }
    if ( $bad_spelling && ! $force_spelling ) {
        return $reject->( "bad_spelling",
                "You gave $email as the email address. Are you sure you didn't mean $common_domains[$nearest]?" );
    }

    # Catch web addresses (two or more w's followed by a dot)
    if ($username =~ /^www*\./)
    {
        return $reject->("web_address",
                         "You gave $email as the email address, but it looks more like a web address to me.");
    }
}

sub set_email {
    my ($userid, $email) = @_;

    my $dbh = LJ::get_db_writer();
    if ($LJ::DEBUG{'write_emails_to_user_table'}) {
        $dbh->do("UPDATE user SET email=? WHERE userid=?", undef,
                 $email, $userid);
    }
    $dbh->do("REPLACE INTO email (userid, email) VALUES (?, ?)",
             undef, $userid, $email);

    # update caches
    LJ::memcache_kill($userid, "userid");
    LJ::MemCache::delete([$userid, "email:$userid"]);
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_email'} = $email;
}


1;
