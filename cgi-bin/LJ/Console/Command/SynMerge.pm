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

package LJ::Console::Command::SynMerge;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);
use LJ::Feed;

sub cmd { "syn_merge" }

sub desc { "Merge two syndicated accounts into one, setting up a redirect and using one account's URL. Requires priv: syn_edit." }

sub args_desc { [
                 'from_user' => "Syndicated account to merge into another.",
                 'to_user'   => "Syndicated account to merge 'from_user' into.",
                 'url'       => "Source feed URL to use for 'to_user'. Specify the direct URL to the feed.",
                 ] }

sub usage { '<from_user> "to" <to_user> "using" <url>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "syn_edit" );
}

sub execute {
    my ($self, $from_user, $to, $to_user, $using, $url, @args) = @_;

    return $self->error("This command takes five arguments. Consult the reference.")
        unless $from_user && $to_user && $url && scalar(@args) == 0;

    return $self->error("Second argument must be 'to'.")
        unless $to eq 'to';

    return $self->error("Fourth argument must be 'using'.")
        if $using ne 'using';

    my ( $ok,$msg ) = LJ::Feed::merge_feed( from_name => $from_user, to_name => $to_user, url => $url );
    return $self->error($msg) unless $ok;
    return $self->print($msg);
}

1;
