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

package LJ::Setting::EmailPosting;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $LJ::EMAIL_POST_DOMAIN && $u && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "email_post";
}

sub label {
    my $class = shift;

    return $class->ml('setting.emailposting.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $can_emailpost = $u->can_emailpost;
    my $upgrade_link  = $can_emailpost ? "" : LJ::Hooks::run_hook( "upgrade_link", $u, "plus" );

    my $addrlist  = LJ::Emailpost::Web::get_allowed_senders($u);
    my @addresses = sort keys %$addrlist;

    my $pin = $class->get_arg( $args, "emailposting_pin" ) || $u->prop("emailpost_pin");

    my $ret = "<p>"
        . $class->ml(
        'setting.emailposting.option',
        {
            domain => $LJ::EMAIL_POST_DOMAIN,
            aopts  => "href='$LJ::SITEROOT/manage/emailpost?mode=help'"
        }
        );
    $ret .= " $upgrade_link</p>";

    $ret .= "<table summary='' class='setting_table' cellspacing='5' cellpadding='0'>";

    if ($can_emailpost) {
        foreach my $i ( 0 .. 4 ) {
            $ret .= "<tr><td class='setting_label'><label for='${key}emailposting_addr$i'>";
            $ret .= $class->ml('setting.emailposting.option.addr') . "</label></td>";
            $ret .= "<td>"
                . LJ::html_text(
                {
                    name  => "${key}emailposting_addr$i",
                    id    => "${key}emailposting_addr$i",
                    value => $class->get_arg( $args, "emailposting_addr$i" )
                        || $addresses[$i]
                        || "",
                    size      => 40,
                    maxlength => 80,
                }
                );
            $ret .= " <label for='${key}emailposting_senderrors$i'>";
            $ret .= $class->ml('setting.emailposting.option.senderrors') . "</label>";
            $ret .= " "
                . LJ::html_check(
                {
                    name     => "${key}emailposting_senderrors$i",
                    id       => "${key}emailposting_senderrors$i",
                    value    => 1,
                    selected => $class->get_arg( $args, "emailposting_senderrors$i" )
                        || ( $addresses[$i]
                        && $addrlist->{ $addresses[$i] }
                        && $addrlist->{ $addresses[$i] }->{get_errors} ) ? 1 : 0,
                }
                );
            $ret .= "<br />";
            $ret .= " <label for='${key}emailposting_helpmessage$i'>";
            $ret .= $class->ml('setting.emailposting.option.helpmessage') . "</label>";
            $ret .= " "
                . LJ::html_check(
                {
                    name     => "${key}emailposting_helpmessage$i",
                    id       => "${key}emailposting_helpmessage$i",
                    value    => 1,
                    selected => 0,
                }
                );
            my $addr_errdiv = $class->errdiv( $errs, "emailposting_addr$i" );
            $ret .= "<br />$addr_errdiv" if $addr_errdiv;
            $ret .= "<br />&nbsp;";
            $ret .= "</td></tr>";
        }

        $ret .= "<tr><td class='setting_label'><label for='${key}emailposting_pin'>";
        $ret .= $class->ml('setting.emailposting.option.pin') . "</label></td>";
        $ret .= "<td>"
            . LJ::html_text(
            {
                name      => "${key}emailposting_pin",
                id        => "${key}emailposting_pin",
                type      => "password",
                value     => $pin || "",
                size      => 10,
                maxlength => 20,
            }
            )
            . " <span class='smaller'>"
            . $class->ml('setting.emailposting.option.pin.note')
            . "</span>";
        my $pin_errdiv = $class->errdiv( $errs, "emailposting_pin" );
        $ret .= "<br />$pin_errdiv" if $pin_errdiv;
        $ret .= "</td></tr>";

        $ret .= "<tr><td>&nbsp;</td>";
        $ret .= "<td><a href='$LJ::SITEROOT/manage/emailpost'>";
        $ret .= $class->ml('setting.emailposting.option.advanced') . "</a></td></tr>";

    }
    else {
        $ret .= $class->ml('setting.emailposting.notavailable');
        $ret .= " "
            . $class->ml( 'setting.emailposting.notavailable.upgrade',
            { aopts => "href='$LJ::SITEROOT/shop'" } )
            if LJ::is_enabled('payments');
    }

    $ret .= "</table>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my @addr_val = map { $class->get_arg( $args, "emailposting_addr$_" ) } ( 0 ... 4 );
    my $pin_val  = $class->get_arg( $args, "emailposting_pin" );

    my %allowed;
    my $addrcount = 0;
    my @send_helpmessage;
    foreach my $addr (@addr_val) {
        $addr =~ s/\s+//g;
        next unless $addr;
        next if length $addr > 80;
        $addr = lc $addr;
        $class->errors(
            "emailposting_addr$addrcount" => $class->ml('setting.emailposting.error.email.invalid')
        ) unless $addr =~ /\@/;
        $allowed{$addr} = {};
        $allowed{$addr}->{get_errors} = 1
            if $class->get_arg( $args, "emailposting_senderrors$addrcount" );
        push @send_helpmessage, $addr
            if $class->get_arg( $args, "emailposting_helpmessage$addrcount" );

        $addrcount++;
    }

    LJ::Emailpost::Web::set_allowed_senders( $u, \%allowed );
    $class->email_helpmessage( $u, $_ ) foreach @send_helpmessage;

    $pin_val =~ s/\s+//g;
    $class->errors(
        emailposting_pin => $class->ml( 'setting.emailposting.error.pin.invalid', { num => 4 } ) )
        unless !$pin_val || $pin_val =~ /^([a-z0-9]){4,20}$/i;

    $class->errors(
        emailposting_pin => $class->ml(
            'setting.emailposting.error.pin.invalidaccount',
            { sitename => $LJ::SITENAMESHORT }
        )
    ) if $pin_val eq $u->password || $pin_val eq $u->user;

    $u->set_prop( emailpost_pin => $pin_val );

    return 1;
}

sub email_helpmessage {
    my ( $class, $u, $address ) = @_;
    return unless $u && $address;
    my $user       = LJ::isu($u) ? $u->user : $u;    # allow object or string
    my $postdomain = "\@post.$LJ::DOMAIN";
    LJ::send_mail(
        {
            to       => $address,
            from     => $LJ::BOGUS_EMAIL,
            fromname => $LJ::SITENAME,
            subject  => LJ::Lang::ml(
                'setting.emailposting.helpmessage.subject',
                { sitenameshort => $LJ::SITENAMESHORT }
            ),
            body => LJ::Lang::ml(
                'setting.emailposting.helpmessage.body',
                {
                    email => "$user+PIN$postdomain",
                    comm  => "$user.communityname$postdomain",
                    url   => "$LJ::SITEROOT/manage/emailpost"
                }
            ),
        }
    );
}

1;
