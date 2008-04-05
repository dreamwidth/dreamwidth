package LJ::SMS::MessageHandler::Stop;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $u = $msg->from_u or croak "No user in message";

    if ($msg->body_text =~ /stop all/i || $u->prop('sms_yes_means') eq 'stop') {
        LJ::SMS::stop_all($u, $msg);
      } else {

          $msg->respond("Disable $LJ::SMS_TITLE? ".
                        "Send YES to confirm. Standard rates apply.", no_quota => 1);

          $u->set_prop('sms_yes_means', 'stop');
      }

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    my @synonyms = qw (
                       stop
                       end
                       cancel
                       unsubscribe
                       quit
                       );

    foreach my $syn (@synonyms) {
        return 1 if $msg->body_text =~ /^\s*$syn/i;
    }

    return 0;
}

1;
