#!/usr/bin/perl
#
# Given a specific user, change their dversion from 8 to 7
# migrating whatever polls they have to their user cluster

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Poll;
use Term::ReadLine;

my $user = shift() or die "need parameter of username\n";
my $u = LJ::load_user($user) or die "user doesn't exist\n";
die "user not at dversion 8\n" unless ($u->{'dversion'} == 8);

my $VERBOSE    = 0;      # print out extra info

my $dbh = LJ::get_db_writer()
    or die "Could not connect to global master";

my $dbr = LJ::get_cluster_reader($u)
    or die "can't get cluster reader for user $user\n";;

my $term = new Term::ReadLine 'd7-d8 rollback';
my $line = $term->readline("Do you want to roll user $user back to dversion 7? [N/y] ");
unless ($line =~ /^y/i) {
    print "Not rolling back to dversion 7\n\n";
    exit;
}

print "\n--- Downgrading user to dversion 7 ---\n\n";

my $maxpollid_master = $dbh->selectrow_array("SELECT MAX(pollid) FROM poll2 WHERE journalid=?", undef, $u->{userid});
my $maxpollid_cluster = $dbr->selectrow_array("SELECT MAX(pollid) FROM poll2 WHERE journalid=?", undef, $u->{userid});

# Polls created on the cluster will not exist on the master, so ask how to proceed
# "[Error: Invalid poll ID ####]" will appear for polls that are not retrievable
if ($maxpollid_cluster > $maxpollid_master) {
    $line = $term->readline("User has created polls on the cluster, downgrade user anyhow? [N/y] ");
    unless ($line =~ /^y/i) {
        print "Not rolling back to dversion 7\n\n";
        exit;
    }
}

#$dbh->do("UPDATE user SET dversion=7 where userid=?", undef, $u->{userid});
die "Downgrade failed: " . $dbh->errstr
    unless ( LJ::update_user($u, { 'dversion' => 7 }) );

print "--- Done downgrading user $user to dversion 7 ---\n";
