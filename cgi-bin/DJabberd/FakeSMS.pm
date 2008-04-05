package DJabberd::RosterStorage::FakeSMS;
use strict;
use base 'DJabberd::RosterStorage';

sub blocking { 0 }

sub _get_sms_acct {
    my $tosub = DJabberd::Subscription->new;
    $tosub->set_to;

    my $ri = DJabberd::RosterItem->new(
                                       jid => "sms\@" . $LJ::DOMAIN,
                                       name => "SMS to/from $LJ::SITENAMESHORT",
                                       subscription => $tosub,
                                       );
    $ri->add_group("SMS Test");
    return $ri;
}

sub get_roster {
    my ($self, $cb, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

    $roster->add($self->_get_sms_acct);
    $cb->set_roster($roster);
}

sub load_roster_item {
    my ($self, $jid, $contact_jid, $cb) = @_;

    unless ($jid->as_bare_string eq "sms\@$LJ::DOMAIN") {
        $cb->decline;
        return;
    }

    my $sb = DJabberd::Subscription->new;
    $sb->set_from;

    my $ri = DJabberd::RosterItem->new(
                                       jid => $contact_jid,
                                       subscription => $sb,
                                       );
    $cb->set($ri);
}

1;

package DJabberd::Delivery::FakeSMS;
use strict;
use warnings;
use base 'DJabberd::Delivery';
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;

my $ua = LWP::UserAgent->new;

sub deliver {
    my ($self, $conn, $cb, $stanza) = @_;
    warn "fake sms delivery attempt.......\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    return $cb->declined unless $to->node eq "sms";
    warn "fakesms delivery!\n";

    my $from = $stanza->from;
    $from =~ s/\@.+//;
    my $msg_xml = $stanza->as_xml;
    return $cb->declined unless $msg_xml =~ m!<body>(.+?)</body>!;
    my $msg = $1;

    warn "****** FROM: $from\n";
    warn "****** Message: $msg\n";

    my $res = $ua->request(POST "$LJ::SITEROOT/misc/fakesms.bml", [from => $from, message => $msg]);
    if ($res->is_success) {
        warn " ... delivered!\n";
    } else {
        warn " ... failure.\n";
    }

    $cb->delivered;
}

package DJabberd::PresenceChecker::FakeSMS;
use strict;
use warnings;
use base 'DJabberd::PresenceChecker';

sub check_presence {
    my ($self, $cb, $jid, $adder) = @_;

    warn "Check presence for [$jid] adding to $adder\n";

    if ($jid->as_bare_string eq "sms\@$LJ::DOMAIN") {
        my $avail = DJabberd::Presence->available_stanza;
        $avail->set_from($jid);
        $adder->($jid, $avail);
    }

    $cb->done;
}

1;
