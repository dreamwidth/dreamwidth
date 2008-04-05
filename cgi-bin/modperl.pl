#!/usr/bin/perl
#

package LJ::ModPerl;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use Apache;

# Image::Size wants to pull in Image::Magick.  Let's not let it during
# the init process.
my $still_loading = 1;
unshift @INC, sub {
    my $f = $_[1];
    return undef unless $still_loading;
    return undef unless $f eq "Image/Magick.pm";
    die "Will not start with Image/Magick.pm"; # makes the require fail, which Image::Size traps
};

# pull in libraries and do per-start initialization once.
require "modperl_subs.pl";

$still_loading = 0;

# do per-restart initialization
LJ::ModPerl::setup_restart();

# delete itself from %INC to make sure this file is run again
# when apache is restarted
delete $INC{"$ENV{'LJHOME'}/cgi-bin/modperl.pl"};

# remember modtime of all loaded libraries
%LJ::LIB_MOD_TIME = ();
while (my ($k, $file) = each %INC) {
    next if $LJ::LIB_MOD_TIME{$file};
    next unless $file =~ m!^\Q$LJ::HOME\E!;
    my $mod = (stat($file))[9];
    $LJ::LIB_MOD_TIME{$file} = $mod;
}

# compatibility with old location of LJ::email_check:
*BMLCodeBlock::check_email = \&LJ::check_email;

1;
