#!/usr/bin/perl
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::ModPerl;

use strict;

# very important that this is done early!  everything else in the LJ
# setup relies on $LJ::HOME being set...
$LJ::HOME = $ENV{LJHOME};
use lib "$ENV{LJHOME}/extlib/lib/perl5";

#use APR::Pool ();
#use Apache::DB ();
#Apache::DB->init();

#use strict;
#use Data::Dumper;
#use Apache2::Const -compile => qw(OK);
#use Apache2::ServerUtil ();

#Apache2::ServerUtil->server->add_config( [ 'PerlResponseHandler LJ::ModPerl', 'SetHandler perl-script' ] );

#sub handler {
#    my $apache_r = shift;
#
#    print STDERR Dumper(\@_);
#    print STDERR Dumper(\%ENV);
#
#    die 1;
#    return Apache2::Const::OK;
#}

# pull in libraries and do per-start initialization once.
require "$LJ::HOME/cgi-bin/modperl_subs.pl";

# do per-restart initialization
LJ::ModPerl::setup_restart();

# delete itself from %INC to make sure this file is run again
# when apache is restarted

delete $INC{"$LJ::HOME/cgi-bin/modperl.pl"};

# remember modtime of all loaded libraries
%LJ::LIB_MOD_TIME = ();
while ( my ( $k, $file ) = each %INC ) {
    next unless defined $file;    # Happens if require caused a runtime error
    next if $LJ::LIB_MOD_TIME{$file};
    next unless $file =~ m!^\Q$LJ::HOME\E!;
    my $mod = ( stat($file) )[9];
    $LJ::LIB_MOD_TIME{$file} = $mod;
}

# compatibility with old location of LJ::email_check:
*BMLCodeBlock::check_email = \&LJ::check_email;

1;
