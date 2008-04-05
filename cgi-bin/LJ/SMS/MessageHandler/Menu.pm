package LJ::SMS::MessageHandler::Menu;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $resp = eval { $msg->respond
                          ("Available commands: (p)ost, (f)riends, (r)ead, (a)dd, i like, help. " . 
                           "E.g. to read username frank send \"read frank\". Standard rates apply.");
                      };

    # FIXME: do we set error status on $resp?

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*m(?:enu)?\s*$/i ? 1 : 0;
}

1;
