# LJ::Constants module, but actually loads everything into package
# "LJ". doesn't export to other modules.  for compat, other callers
# still can do LJ::BMAX_NAME, etc

package LJ;

use constant ENDOFTIME => 2147483647;
$LJ::EndOfTime = 2147483647;  # for string interpolation

use constant MAX_32BIT_UNSIGNED => 4294967295;
$LJ::MAX_32BIT_UNSIGNED = 4294967295;

use constant MAX_32BIT_SIGNED => 2147483647;
$LJ::MAX_32BIT_SIGNED = 2147483647;

# width constants. BMAX_ constants are restrictions on byte width,
# CMAX_ on character width (character means byte unless $LJ::UNICODE,
# in which case it means a UTF-8 character).

use constant BMAX_SUBJECT => 255; # *_SUBJECT for journal events, not comments
use constant CMAX_SUBJECT => 100;
use constant BMAX_COMMENT => 9000;
use constant CMAX_COMMENT => 4300;
use constant BMAX_MEMORY  => 150;
use constant CMAX_MEMORY  => 80;
use constant BMAX_NAME    => 100;
use constant CMAX_NAME    => 50;
use constant BMAX_KEYWORD => 80;
use constant CMAX_KEYWORD => 40;
use constant BMAX_PROP    => 255;   # logprop[2]/talkprop[2]/userproplite (not userprop)
use constant CMAX_PROP    => 100;
use constant BMAX_GRPNAME => 60;
use constant CMAX_GRPNAME => 30;
use constant BMAX_GRPNAME2 => 90; # introduced in dversion6, when we widened the groupname column
use constant CMAX_GRPNAME2 => 40; # but we have to keep the old GRPNAME around while dversion5 exists
use constant BMAX_BIO     => 65535;
use constant CMAX_BIO     => 65535;
use constant BMAX_EVENT   => 65535;
use constant CMAX_EVENT   => 65535;
use constant BMAX_INTEREST => 100;
use constant CMAX_INTEREST => 50;
use constant BMAX_UPIC_COMMENT => 255;
use constant CMAX_UPIC_COMMENT => 120;
use constant BMAX_UPIC_DESCRIPTION => 255;
use constant CMAX_UPIC_DESCRIPTION => 120;

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
use constant MAX_DVERSION => 8;
$LJ::MAX_DVERSION = MAX_DVERSION;

1;
