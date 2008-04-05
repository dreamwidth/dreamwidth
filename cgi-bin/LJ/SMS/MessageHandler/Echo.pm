package LJ::SMS::MessageHandler::Echo;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $echo_text = $msg->body_text;
    $echo_text =~ s/^\s*echo\s+//i;
    my $resp = eval { $msg->respond($echo_text) };

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*echo/i ? 1 : 0;
}

1;
