#!/usr/bin/perl
#
# bin/upgrading/gen-secrets.pl
#
# This script can generate items for %LJ::SECRETS
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use Getopt::Long;
use POSIX;
use Data::Dumper;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $tv = system('openssl version >/dev/null 2>/dev/null');
die "OpenSSL command line not found" if $tv;

sub usage {
    die "Usage: gen-secrets.pl BLAH";
}

my $regen = 0;
my $no_rec= 0;

usage() unless GetOptions(
                          'regen'       => \$regen,
                          'required'    => \$no_rec,
                          );

my %sec_use;
%sec_use = %LJ::SECRETS unless $regen;

my %sec_out;

foreach my $secret ( sort keys %LJ::Secrets::secret ) {
    my $def = $LJ::Secrets::secret{$secret};

    next if defined $sec_use{$secret} && $sec_use{$secret};
    next if $no_rec && ! $def->{required};

    if ( $def->{max_len} && $def->{min_len} && $def->{max_len} < $def->{min_len} ) {
        warn "Invalid required length specifications ( max < min ) for '$secret'.\n";
        next;
    }

    if ( $def->{rec_max_len} && $def->{rec_min_len} && $def->{rec_max_len} < $def->{rec_min_len} ) {
        warn "Invalid recommended length specifications ( max < min ) for '$secret'.\n";
        next;
    }

    my $req_len = $def->{len} || $def->{max_len} || $def->{min_len};
    my $len = $req_len || $def->{rec_len} || $def->{rec_max_len} || $def->{rec_min_len};

    if ( $len < 0 ) {
        warn "Length for '$secret' is less then 0";
        next;
    }

    my $gen_len = ceil( $len / 2 );
    my $data = substr( `openssl rand -hex $gen_len`, 0, $len );
    chomp $data;
    die "Unable to get $len bytes of data from OpenSSL\n"
        if length($data) < $len;

    $sec_out{$secret} = $data;
}

unless ( %sec_out ) {
    print "Your secrets are up to date.\n";
    exit;
}

if ( ! %LJ::SECRETS ) {
    print "\nPlease add the following section to your etc/config-private.pl file,\n";
    print "inside the LJ package:\n\n";
    print "%LJ::SECRETS = (\n";
} else {
    print "\nPlease add or replace the following sections in LJ::SECRETS in your config\n";
    print "file (probably etc/config-private.pl):\n\n";
}

foreach my $secret ( sort keys %sec_out ) {
    my $value = $sec_out{$secret};
    # FIXME: There has to be a better way to do this.
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;

    if ( $secret =~ m/^[a-zA-Z0-9_]+$/ ) {
        print "    $secret => '$value',\n";
    } else {
        $secret =~ s/\\/\\\\/g;
        $secret =~ s/'/\\'/g;
        print "    '$secret' => '$value',\n";
    }
}

print ");\n" unless %LJ::SECRETS;
print "\n";
