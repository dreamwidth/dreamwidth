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

package LJ::Widget::BetaFeature;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::BetaFeatures;

sub need_res { qw( stc/simple-form.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $feature = $opts{feature};
    return "" unless $feature;

    my $u = $opts{u};
    return "" unless LJ::isu($u);

    my $handler = LJ::BetaFeatures->get_handler($feature);
    return "" if $handler->is_sitewide_beta;

    my $ret;

    $ret .= "<h2>" . $class->ml("widget.betafeature.$feature.title") . "</h2>"
        if $handler->is_active;

    if ($handler->is_active && $handler->user_can_add($u)) {
        my @submit_actions = $handler->is_optout ? ( "on", "off" ) : ( "off", "on" );

        $ret .= "<div class='simple-form'>";
        $ret .= $class->start_form;
        if ($u->is_in_beta($feature)) {
            $ret .= "<?p " . $class->ml("widget.betafeature.$feature.on", { $handler->args_list } ) . " p?>";
            $ret .= "<fieldset class='submit'>" . $class->html_submit("off", $class->ml("widget.betafeature.btn.$submit_actions[0]")) . "</fieldset>";
        } else {
            $ret .= "<?p " . $class->ml("widget.betafeature.$feature.off", { $handler->args_list } ) . " p?>";
            $ret .= "<fieldset class='submit'>" . $class->html_submit("on", $class->ml("widget.betafeature.btn.$submit_actions[1]")) . "</fieldset>";
        }
        $ret .= $class->html_hidden( feature => $feature, user => $u->user );
        $ret .= $class->end_form;
        $ret .= "</div>";
    } elsif (!$handler->user_can_add($u)) {
        $ret .= "<?p " . $class->ml("widget.betafeature.$feature.cantadd") . " p?>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $feature = $post->{feature};
    die "No feature defined." unless $feature;

    my $u = LJ::load_user($post->{user});
    die "Invalid user." unless $u;

    if ($post->{on}) {
        LJ::BetaFeatures->add_to_beta( $u => $feature );
    } else {
        LJ::BetaFeatures->remove_from_beta( $u => $feature );
    }

    return;
}

1;
