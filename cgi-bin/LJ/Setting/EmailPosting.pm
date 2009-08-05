package LJ::Setting::EmailPosting;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $LJ::EMAIL_POST_DOMAIN && $u && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "email_post";
}

sub label {
    my $class = shift;

    return $class->ml('setting.emailposting.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $can_emailpost = $u->get_cap("emailpost") ? 1 : 0;
    my $upgrade_link = $can_emailpost ? "" : LJ::run_hook("upgrade_link", $u, "plus");

    my $addrlist = LJ::Emailpost::get_allowed_senders($u);
    my @addresses = sort keys %$addrlist;

    my $pin = $class->get_arg($args, "emailposting_pin") || $u->prop("emailpost_pin");

    my $ret .= "<p>" . $class->ml('setting.emailposting.option', { domain => $LJ::EMAIL_POST_DOMAIN, aopts => "href='$LJ::SITEROOT/manage/emailpost?mode=help'" }) . " $upgrade_link</p>";

    $ret .= "<table class='setting_table' cellspacing='5' cellpadding='0'>";

    foreach my $i (0..2) {
        $ret .= "<tr><td class='setting_label'><label for='${key}emailposting_addr$i'>" . $class->ml('setting.emailposting.option.addr') . "</label></td>";
        $ret .= "<td>" . LJ::html_text({
            name => "${key}emailposting_addr$i",
            id => "${key}emailposting_addr$i",
            value => $class->get_arg($args, "emailposting_addr$i") || $addresses[$i] || "",
            disabled => $can_emailpost ? 0 : 1,
            size => 40,
            maxlength => 80,
        });
        $ret .= " <label for='${key}emailposting_senderrors$i' style='color: #000;'>" . $class->ml('setting.emailposting.option.senderrors') . "</label>";
        $ret .= " " . LJ::html_check({
            name => "${key}emailposting_senderrors$i",
            id => "${key}emailposting_senderrors$i",
            value => 1,
            selected => $class->get_arg($args, "emailposting_senderrors$i") || ($addresses[$i] && $addrlist->{$addresses[$i]} && $addrlist->{$addresses[$i]}->{get_errors}) ? 1 : 0,
            disabled => $can_emailpost ? 0 : 1,
        });
        my $addr_errdiv = $class->errdiv($errs, "emailposting_addr$i");
        $ret .= "<br />$addr_errdiv" if $addr_errdiv;
        $ret .= "</td></tr>";
    }

    $ret .= "<tr><td class='setting_label'><label for='${key}emailposting_pin'>" . $class->ml('setting.emailposting.option.pin') . "</label></td>";
    $ret .= "<td>" . LJ::html_text({
        name => "${key}emailposting_pin",
        id => "${key}emailposting_pin",
        type => "password",
        value => $pin || "",
        disabled => $can_emailpost ? 0 : 1,
        size => 10,
        maxlength => 20,
    }) . " <span class='smaller'>" . $class->ml('setting.emailposting.option.pin.note') . "</span>";
    my $pin_errdiv = $class->errdiv($errs, "emailposting_pin");
    $ret .= "<br />$pin_errdiv" if $pin_errdiv;
    $ret .= "</td></tr>";

    if ($can_emailpost) {
        $ret .= "<tr><td>&nbsp;</td>";
        $ret .= "<td><a href='$LJ::SITEROOT/manage/emailpost'>" . $class->ml('setting.emailposting.option.advanced') . "</a></td></tr>";
    }

    $ret .= "</table>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $addr0_val = $class->get_arg($args, "emailposting_addr0");
    my $addr1_val = $class->get_arg($args, "emailposting_addr1");
    my $addr2_val = $class->get_arg($args, "emailposting_addr2");
    my $pin_val = $class->get_arg($args, "emailposting_pin");

    my %allowed;
    my $addrcount = 0;
    foreach my $addr ($addr0_val, $addr1_val, $addr2_val) {
        $addr =~ s/\s+//g;
        next unless $addr;
        next if length $addr > 80;
        $addr = lc $addr;
        $class->errors( "emailposting_addr$addrcount" => $class->ml('setting.emailposting.error.email.invalid') )
            unless $addr =~ /\@/;
        $allowed{$addr} = {};
        $allowed{$addr}->{get_errors} = 1
            if $class->get_arg($args, "emailposting_senderrors$addrcount");

        $addrcount++;
    }

    LJ::Emailpost::set_allowed_senders($u, \%allowed);

    $pin_val =~ s/\s+//g;
    $class->errors( emailposting_pin => $class->ml('setting.emailposting.error.pin.invalid', { num => 4 }) )
        unless !$pin_val || $pin_val =~ /^([a-z0-9]){4,20}$/i;

    $class->errors( emailposting_pin => $class->ml('setting.emailposting.error.pin.invalidaccount', { sitename => $LJ::SITENAMESHORT }) )
        if $pin_val eq $u->password || $pin_val eq $u->user;

    $u->set_prop( emailpost_pin => $pin_val );

    return 1;
}

1;
