#!/usr/bin/perl

use strict;
use Test::More;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Test;

use XML::Atom::Client;
use XML::Atom::Entry;

use LWP::Simple;
if (get("$LJ::SITEROOT/dev/t_00.bml") =~ /BML file/) {
    plan tests => 5;
} else {
    plan skip_all => "Webserver not running.";
    exit 0;
}

my $u = temp_user();
my $pass = "foopass";
$u->set_password($pass);

my $api = XML::Atom::Client->new;
$api->username($u->user);
$api->password($u->password);

my $entry = XML::Atom::Entry->new;
$entry->title('New Post');
my $content = "Content of my post at " . rand();
$entry->content($content);

my $EditURI = $api->createEntry("$LJ::SITEROOT/interface/atom/post", $entry);

ok($EditURI, "got an edit URI back, presumably posted");
like($EditURI, qr!/atom/edit/1$!, "got the right URI back");

my $entry = LJ::Entry->new($u, jitemid => 1);
ok($entry, "got entry");
ok($entry->valid, "entry is valid")
    or die "rest will fail";

is($entry->event_raw, $content, "item has right content");

