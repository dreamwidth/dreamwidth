package LJ::ExternalSite::Vox;
use strict;
use warnings;
use base 'LJ::ExternalSite';

sub new {
    my ($class, $hostport) = @_;
    $hostport ||= "vox.com";  # by default, the main vox site
    my $self = bless {
        host => lc($hostport),
    }, $class;
    return $self;
}

sub matches_url {
    my ($self, $url) = @_;
    return 0 unless $url =~ m!^(?:http://)?([a-z][a-z0-9\-]{0,63})\.\Q$self->{host}\E/?$!i;
    return "http://" . lc($1) . "." . $self->{host} . "/";
}

sub icon_url {
    return "$LJ::IMGPREFIX/vox.gif";
}

1;
