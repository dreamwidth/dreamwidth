package LJ::Test::AtomAPI;

use strict;
use warnings;

use lib "$LJ::HOME/cgi-bin";

use Test::FakeApache;

require "modperl.pl";

use Carp ();
use DBI;
use LJ::Test;

use HTTP::Request;

use List::Util qw(first);

use XML::Atom::Client;
use XML::Atom::Entry;
use XML::Atom::Feed;

use bytes ();

sub new {
    my $class = shift;
    my $self = bless {}, (ref $class || $class);

    $self->{apache} = LJ::Test->fake_apache;
    my $client = $self->{client} = XML::Atom::Client->new;

    $client->username('ads');
    $client->password('ads');

    return $self;
}

sub base_uri {
    return "$LJ::SITEROOT/interface/atom";
}

sub post_uri {
    my $self = shift;

    my $feed = $self->fetch_feed($self->base_uri);

    foreach my $link ($feed->links) {
        return $link->href if $link->rel eq 'service.post';
    }

    Carp::croak("Unable to find service.post link");
}

sub fetch_feed {
    my $self = shift;
    my $uri = shift;
    my $res = $self->atom_run(GET => $uri);
    return XML::Atom::Feed->new(Stream => \$res->content);
}

sub fetch_entry {
    my $self = shift;
    my $uri = shift;
    my $res = $self->atom_run(GET => $uri);
    return XML::Atom::Entry->new(Stream => \$res->content);
}

sub post_entry {
    my $self = shift;
    my $uri = shift;
    my $entry = shift;

    return $self->atom_run(POST => $uri, $entry);
}

sub atom_run {
    my $self = shift;
    my ($method, $uri, $obj) = @_;

    my $a = $self->{apache};

    my $req;

    if ($obj) {
        my $content = $obj->as_xml;
        $req = HTTP::Request->new($method, $uri,
                                  [
                                   'Content-Length', bytes::length($content),
                                   'Content-Type', "application/x.atom+xml",
                                  ], $content);
    } else {
        $req = HTTP::Request->new($method, $uri);
    }

    my $client = $self->{client};

    $client->munge_request($req);

    if ($ENV{DEBUG}) {
        print "****** START REQUEST ******\n";
        print $req->as_string;
        print "****** END REQUEST  ******\n";
    }

    my $res = $a->run($req);

    $client->munge_response($res);

    if ($ENV{DEBUG}) {
        print "****** START RESPONSE ******\n";
        print $res->as_string;
        print "****** END RESPONSE  ******\n";
    }

    return $res;
}

1;
