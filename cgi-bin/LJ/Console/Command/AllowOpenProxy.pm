package LJ::Console::Command::AllowOpenProxy;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "allow_open_proxy" }

sub desc { "Marks an IP address as not being an open proxy for the next 24 hours." }

sub args_desc { [
                 'ip' => "The IP address to mark as clear.",
                 'forever' => "Optional; set to 'forever' if this proxy should be allowed forever.",
                 ] }

sub usage { '<ip> [ <forever> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "allowopenproxy");
}

sub execute {
    my ($self, $ip, $forever, @args) = @_;

    return $self->error("This command takes either one or two arguments. Consult the reference.")
        unless $ip && scalar(@args) == 0;

    return $self->error("That is an invalid IP address.")
        unless $ip =~ /^(?:\d{1,3}\.){3}\d{1,3}$/;
    return $self->error("That IP address is not an open proxy.")
        unless LJ::is_open_proxy($ip);

    my $remote = LJ::get_remote();
    my $dbh = LJ::get_db_writer();
    my $asof = $forever ? "'0'" : "UNIX_TIMESTAMP()";
    $dbh->do("REPLACE INTO openproxy VALUES (?, 'clear', $asof, ?)",
             undef, $ip, "Manual: " . $remote->user);
    return $self->error("Database error: " . $dbh->errstr)
        if $dbh->err;

    my $period = $forever ? "forever" : "for the next 24 hours";
    return $self->print("$ip cleared as an open proxy $period");
}

1;
