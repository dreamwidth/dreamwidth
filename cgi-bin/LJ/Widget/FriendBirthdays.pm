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

package LJ::Widget::FriendBirthdays;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use DW::Template;

sub need_res {
    return qw( stc/widgets/friendbirthdays.css );
}

# args
#   user: optional $u whose friend birthdays we should get (remote is default)
#   limit: optional max number of birthdays to show; default is 5
sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $opts{user} && LJ::isu( $opts{user} ) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my @bdays = $u->get_birthdays( months_ahead => 1 );
    @bdays = @bdays[ 0 .. $limit - 1 ]
        if @bdays > $limit;

    return "" unless @bdays;

    my $vars = {
        bdays       => \@bdays,
        load_user   => \&LJ::load_user,
        month_short => \&LJ::Lang::month_short
    };

    return DW::Template->template_string( 'widget/friendbirthdays.tt', $vars );
}

1;
