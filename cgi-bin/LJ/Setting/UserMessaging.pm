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

package LJ::Setting::UserMessaging;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(email message contact) }

sub should_render {
    my ( $class, $u ) = @_;
    return $u->is_person && LJ::is_enabled( 'user_messaging' );
}

sub label {
    my $class = shift;
    return $class->ml( 'settings.usermessaging.label',
                       { siteabbrev => $LJ::SITENAMEABBREV }
                     );
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $ret;
    my $helper = ( $args && $args->{helper} == 0 ) ? 0 : 1;

    $ret .= "<label for='${key}opt_usermsg'>" . $class->ml('settings.usermessaging.question') . "</label>"
        unless $args && $args->{minimal_display};
    $ret .= LJ::html_select( { name => "${key}opt_usermsg",
                               id => "${key}opt_usermsg",
                               class => "select",
                               title => $class->label,
                               selected => $u->opt_usermsg },
                             Y => LJ::Lang::ml('settings.usermessaging.opt.Y'),
                             F => LJ::Lang::ml('settings.usermessaging.opt.F'),
                             M => LJ::Lang::ml('settings.usermessaging.opt.M'),
                             N => LJ::Lang::ml('settings.usermessaging.opt.N'),
                           );
    $ret .= "<div class='helper'>" .
            $class->ml('settings.usermessaging.helper', {
                sitename => $LJ::SITENAMESHORT }) .
            "</div>" if $helper;
    $ret .= $class->errdiv($errs, "opt_usermsg");

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $opt_usermsg= $class->get_arg($args, "opt_usermsg");
    $class->errors("opt_usermsg" => $class->ml('settings.usermessaging.error.invalid')) unless $opt_usermsg=~ /^[MFNY]$/;
    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $opt_usermsg = $class->get_arg($args, "opt_usermsg");
    return $u->set_prop('opt_usermsg', $opt_usermsg);
}

1;
