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

# LJ::Constants module, but actually loads everything into package
# "LJ". doesn't export to other modules.  for compat, other callers
# still can do LJ::BMAX_NAME, etc

package LJ;
use strict;

use constant ENDOFTIME => 2147483647;
$LJ::EndOfTime = 2147483647;    # for string interpolation

use constant MAX_32BIT_UNSIGNED => 4294967295;
$LJ::MAX_32BIT_UNSIGNED = 4294967295;

use constant MAX_32BIT_SIGNED => 2147483647;
$LJ::MAX_32BIT_SIGNED = 2147483647;

# width constants. BMAX_ constants are restrictions on byte width,
# CMAX_ on character width (character used to mean byte, but now
# it means a UTF-8 character).

use constant BMAX_SUBJECT          => 255;      # *_SUBJECT for journal events, not comments
use constant CMAX_SUBJECT          => 100;
use constant BMAX_COMMENT          => 65535;
use constant CMAX_COMMENT          => 16000;
use constant BMAX_MEMORY           => 150;
use constant CMAX_MEMORY           => 80;
use constant BMAX_NAME             => 100;
use constant CMAX_NAME             => 50;
use constant BMAX_KEYWORD          => 80;
use constant CMAX_KEYWORD          => 40;
use constant BMAX_PROP             => 255;      # logprop[2]/talkprop[2]/userproplite (not userprop)
use constant CMAX_PROP             => 100;
use constant BMAX_GRPNAME          => 90;
use constant CMAX_GRPNAME          => 40;
use constant BMAX_BIO              => 65535;
use constant CMAX_BIO              => 65535;
use constant BMAX_EVENT            => 450000;
use constant CMAX_EVENT            => 300000;
use constant BMAX_SITEKEYWORD      => 100;
use constant CMAX_SITEKEYWORD      => 50;
use constant BMAX_UPIC_COMMENT     => 255;
use constant CMAX_UPIC_COMMENT     => 120;
use constant BMAX_UPIC_DESCRIPTION => 600;
use constant CMAX_UPIC_DESCRIPTION => 300;

# user.dversion values:
#    0: unclustered  (unsupported)
#    1: clustered, not pics (unsupported)
#    2: clustered
#    3: weekuserusage populated  (Note: this table's now gone)
#    4: userproplite2 clustered, and cldversion on userproplist table
#    5: overrides clustered, and style clustered
#    6: clustered memories, friend groups, and keywords (for memories)
#    7: clustered userpics, keyword limiting, and comment support
#    8: clustered polls
#    9: userpicmap3, with mapid
#
# Dreamwidth installations should ALL be dversion >= 8.  We do not support anything
# else and are ripping out code to support all previous dversions.
#
use constant MAX_DVERSION => 9;
$LJ::MAX_DVERSION = MAX_DVERSION;

1;
