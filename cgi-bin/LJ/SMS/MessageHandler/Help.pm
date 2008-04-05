package LJ::SMS::MessageHandler::Help;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $body_text = 
        LJ::run_hook("smscmd_help_text", $msg) ||
        "This is the $LJ::SITENAME SMS Gateway!  Baaaaaaaah.";

    my $resp = eval { $msg->respond($body_text, no_quota => 1) };

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*help/i ? 1 : 0;
}

1;
