package LJ::SMS::MessageHandler::ILike;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $u = $msg->from_u
        or die "no from_u for ILike message";

    my $text = $msg->body_text;
    $text =~ s/^\s*i\s+like\s+//i;

    # now all that's left are interests
    my @ints_to_add = LJ::interest_string_to_list($text);

    # in the case where the original body text is >= 160 characters,
    # we assume that they've bumped up against the edge of SMS's
    # length capability and most likely the last interest has been 
    # cut off... in this case, we'll pop from @ints_to_add

    # FIXME: don't hardcode 160
    if (length $msg->body_text >= 160 && $msg->body_text =~ /$ints_to_add[-1]$/i) {
        warn "truncating message: {" . length($msg->body_text) . "} " . $msg->body_text . "\n";
        pop @ints_to_add;
    }

    # load interests
    my %ints_old = (map { $_->[1] => $_->[0] } 
                    @{ LJ::get_interests($u, { forceids => 1 }) || []});

    my @ints_new = keys %ints_old;
    push @ints_new, @ints_to_add;

    LJ::set_interests($u, \%ints_old, \@ints_new)
        or die "Unable to set interests: " . join(",", @ints_new);

    # mark the requesting (source) message as processed
    # -- we'd die before now if there was an error
    $msg->status('success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*i\s+like\s+/i ? 1 : 0;
}

1;
