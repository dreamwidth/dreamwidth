#!/usr/bin/perl
#
# dump-profile-editors.pl -- Read and reset the profile_editors key from memcache
#
# Copyright (c) 2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use Getopt::Long;

# parse input options
my $ro;
GetOptions( 'readonly' => \$ro );

# now load in the beast
BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

use LJ::MemCache;

my $memval = LJ::MemCache::get('profile_editors') // [];
LJ::MemCache::delete('profile_editors') unless $ro;

my $us = LJ::load_userids(@$memval);

my @users = sort { $a->user cmp $b->user } values %$us;

foreach my $u (@users) {
    next unless $u && $u->is_visible;

    my $url     = $u->url;
    my $urlname = $u->prop('urlname');
    next if index( $url, '.' ) == -1 && index( $urlname, '.' ) == -1;

    my $timecreate = scalar localtime( $u->timecreate );
    my $user       = $u->user;

    print "$user\t$timecreate\t$url\t$urlname\n";
}
