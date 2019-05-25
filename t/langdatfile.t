# t/langdatfile.t
#
# Test translation system
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

use strict;
use warnings;

use Test::More tests => 9;    # 5 + total # of keys in sampletrans.dat

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::LangDatFile;

my $trans = LJ::LangDatFile->new("$ENV{LJHOME}/t/data/sampletrans.dat");
ok( $trans, 'Constructed an LJ::LangDatFile translation object' );

like( $trans->value('nagios.alert.subject'), qr/HEY MARK/i, 'Parsed translation string' );

like(
    $trans->value('banned.spammer.login.lolno'),
    qr/have a magical day/i,
    'Parsed multiline translation string'
);

# test foreach_key
my %foundkeys = ();
$trans->foreach_key(
    sub {
        my $key = shift;
        $foundkeys{$key}++;
        is( $trans->value($key), $trans->{values}->{$key}, 'Key found' );
    }
);

my @all_keys  = $trans->keys;
my @grep_keys = grep { $foundkeys{$_} == 1 } $trans->keys;

is( scalar @all_keys, scalar @grep_keys, 'All keys found' );

# change a value, write the file out, and make sure the new parsed
# file matches the currently parsed version
$trans->set( 'feedback.poll.option1', 'I love everyone in this bar' );
$trans->save;

# read the file back in, make sure state is the same
my $trans2 = LJ::LangDatFile->new("$ENV{LJHOME}/t/data/sampletrans.dat");
is_deeply( $trans2->{values}, $trans->{values}, 'State preserved between file saving' );
