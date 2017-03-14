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

package LJ::MassPrivacy;

# LJ::MassPrivacy object
#
# Used to handle Schwartz job for updating privacy of posts en masse
#

use strict;
use Carp qw(croak);
use DateTime;

sub schwartz_capabilities {
    return qw(LJ::Worker::MassPrivacy);
}

# enqueue job to update privacy
sub enqueue_job {
    my ($class, %opts) = @_;
    croak "enqueue_job is a class method"
        unless $class eq __PACKAGE__;

    croak "missing options argument" unless %opts;

    # Check options
    if (!($opts{s_security} =~ m/[private|usemask|public]/) ||
        !($opts{e_security} =~ m/[private|usemask|public]/) ) {
        croak "invalid privacy option";
    }

    if ($opts{'start_date'} || $opts{'end_date'}) {
        croak "start or end date not defined"
            if (!$opts{'start_date'} || !$opts{'end_date'});

        if (!($opts{'start_date'} >= 0) || !($opts{'end_date'} >= 0) ||
            !($opts{'start_date'} <= $LJ::EndOfTime) ||
            !($opts{'end_date'} <= $LJ::EndOfTime) ) {
            return undef;
        }
    }

    my $sclient = LJ::theschwartz();
    die "Unable to contact TheSchwartz!" unless $sclient;

    my $shandle = $sclient->insert("LJ::Worker::MassPrivacy", \%opts);

    return $shandle;
}

sub handle {
    my ($class, $opts) = @_;

    croak "missing options argument" unless $opts;

    my $u =  LJ::load_userid($opts->{'userid'});
    # we only handle changes to or from locked security
    # Allowmask for locked is 1, public and private are 0.
    my $s_allowmask = ($opts->{s_security} eq 'usemask') ? 1 :0;
    my $e_allowmask = ($opts->{e_security} eq 'usemask') ? 1 :0;
    my %privacy = ( private => 'private',
                    usemask => 'locked',
                    public  => 'public',
                  );

    my @jids;
    my $timeframe = ''; # date range string or empty
    # If there is a date range
    # add 24h to the final date; otherwise we don't get entries on that date
    if ($opts->{s_unixtime} && $opts->{e_unixtime}) {
        @jids = $u->get_post_ids(
                            'security' => $opts->{'s_security'},
                            'allowmask' => $s_allowmask,
                            'start_date' => $opts->{'s_unixtime'},
                            'end_date' => $opts->{'e_unixtime'} + 24*60*60 );
        my $s_dt = DateTime->from_epoch( epoch => $opts->{s_unixtime} );
        my $e_dt = DateTime->from_epoch( epoch => $opts->{e_unixtime} );
        $timeframe = "between " . $s_dt->ymd . " and " . $e_dt->ymd;

    } else {
        @jids = $u->get_post_ids(
                            'security' => $opts->{'s_security'},
                            'allowmask' => $s_allowmask, );
    }

    # check if there are any posts to update
    return 1 unless (scalar @jids);

    my @errs;
    my $okay_ct = 0;

    # Update each event using the API
    foreach my $itemid (@jids) {
        my %res = ();
        my %req = ( 'mode' => 'editevent',
                    'ver' => $LJ::PROTOCOL_VER,
                    'user' => $u->{'user'},
                    'itemid' => $itemid,
                    'security' => $opts->{e_security},
                    'allowmask' => $e_allowmask,
                    );

        # do editevent request
        LJ::do_request(\%req, \%res, { 'noauth' => 1, 'u' => $u,
                       'use_old_content' => 1 });

        # check response
        if ($res{'success'} eq "OK") {
            $okay_ct++;
        } else {
            push @errs, $res{'errmsg'};
        }
    }


    # better logging
    # only print 200 characters  of error message to log
    # allow some space at the end for error location message
    if (@errs) {
        my $errmsg = join(', ', @errs);
        $errmsg = substr($errmsg, 0, 200) . "... ";
        LJ::statushistory_add( $u, $u, "mass_privacy", "Error: $errmsg" );
        die $errmsg;
    }

    my $subject = LJ::Lang::ml( 'email.massprivacy.subject', { user => $u->user } );
    my $msg = LJ::Lang::ml( 'email.massprivacy.body', {
        user => $u->user,
        sitenameshort => $LJ::SITENAMESHORT,
        siteroot => $LJ::SITEROOT,
        count => $okay_ct,
        timeframe => $timeframe,
        oldsecurity => $privacy{$opts->{s_security}},
        newsecurity => $privacy{$opts->{e_security}},
        privacyurl => "$LJ::SITEROOT/editprivacy",
    } );

    LJ::send_mail({
        'to' => $u->email_raw,
        'from' => $LJ::BOGUS_EMAIL,
        'fromname' => $LJ::SITENAMESHORT,
        'wrap' => 1,
        'charset' => 'utf-8',
        'subject' => $subject,
        'body' => $msg,
    });

    LJ::statushistory_add( $u, $u, "mass_privacy", "Success: $okay_ct " .
                           $privacy{$opts->{s_security}} . " entries " .
                           $timeframe . "have now " . "been changed to be " .
                           $privacy{$opts->{e_security}} );

    return 1;
}

# Schwartz job for processing changes to privacy en masse
package LJ::Worker::MassPrivacy;
use base 'TheSchwartz::Worker';

use LJ::MassPrivacy;

sub work {
    my ($class, $job) = @_;

    my $opts = $job->arg;

    unless ($opts) {
        $job->failed;
        return;
    }

    LJ::MassPrivacy->handle($opts);

    return $job->completed;
}

sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
        my ($class, $fails) = @_;
            return (10, 30, 60, 300, 600)[$fails];
}

1;
