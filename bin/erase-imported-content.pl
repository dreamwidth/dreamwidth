#!/usr/bin/perl

use v5.10;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Talk;
use DW::Worker::ContentImporter::Local::Entries;
use DW::Worker::ContentImporter::Local::Comments;

use Getopt::Long;

my ( $user, $confirm );
GetOptions(
    'user=s' => \$user,
    'confirm=s' => \$confirm,
);

my $u = LJ::load_user( $user )
    or die "Usage: $0 -u USER -c CODEWORD\n";
$confirm = $confirm && $confirm eq 'b00p' ? 1 : 0;

# Select posts that were imported
my %map = %{ DW::Worker::ContentImporter::Local::Entries->get_entry_map( $u ) || {} };
unless ( scalar keys %map > 0 ) {
    say 'Account has no imported entries, nothing to do.';
    exit 0;
}

# Nuke all entries that have been imported.
my %csrc_in = %{ DW::Worker::ContentImporter::Local::Comments->get_comment_map( $u ) || {} };
my %csrc;
$csrc{$csrc_in{$_}} = $_ foreach keys %csrc_in; # Invert it.

foreach my $val ( keys %map ) {
    my $jitemid = $map{$val};
    say "$val (jitemid $jitemid) ...";

    my $nuke = 1;
    my %cmts = %{ LJ::Talk::get_talk_data( $u, 'L', $jitemid ) || {} };
    foreach my $jtalkid ( keys %cmts ) {
        next if exists $csrc{$jtalkid};

        say " ... non-imported comment: $jtalkid";
        $nuke = 0;
    }

    unless ( $nuke ) {
        say ' ... NOT DELETING';
        next;
    }

    if ( $confirm ) {
        my $rv = LJ::delete_entry( $u, $jitemid, 0, undef );
        if ( $rv ) {
            say ' ... deleted';
        } else {
            say ' ... FAILED TO DELETE';
        }
    } else {
        say ' ... no action, confirmation not set';
    }
}

exit 0;
