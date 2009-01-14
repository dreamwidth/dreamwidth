package LJ::Setting::SMS;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_community && $u->can_use_sms ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "sms_about";
}

sub label {
    my $class = shift;

    return $LJ::SMS_TITLE;
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $current_msisdn = $class->get_arg($args, "sms_phone") || $u->sms_mapped_number;
    my ($area, $prefix, $num) = $current_msisdn =~ /\+1(\d{3})(\d{3})(\d{4})/ if $current_msisdn;
    $current_msisdn = "$area-$prefix-$num" if $area && $prefix && $num;

    my $carrier = $class->get_arg($args, "sms_carrier") || $u->prop("sms_carrier");
    my @carriers;
    if (%LJ::SMS_CARRIERS) {
        my @keys = @LJ::SMS_CARRIER_ORDER ? @LJ::SMS_CARRIER_ORDER : keys %LJ::SMS_CARRIERS;

        foreach my $k (@keys) {
            my $v = $LJ::SMS_CARRIERS{$k} or next;
            $v .= '<super>&reg;</super>' unless $k eq 'other';
            push @carriers, ($k, $v);
        }
    }    

    my $ret .= "<p>" . $class->ml('setting.sms.option', { sitename => $LJ::SITENAMESHORT, aopts => "href='$LJ::SITEROOT/manage/sms/textcommands.bml'" }) . "</p>";

    $ret .= "<table class='setting_table' cellspacing='5' cellpadding='0'>";

    $ret .= "<tr><td class='setting_label'><label for='${key}sms_phone'>" . $class->ml('setting.sms.option.phone') . "</label></td>";
    $ret .= "<td>" . LJ::html_text({
        name => "${key}sms_phone",
        id => "${key}sms_phone",
        value => $current_msisdn || "",
    });
    my $phone_errdiv = $class->errdiv($errs, "sms_phone");
    $ret .= "<br />$phone_errdiv" if $phone_errdiv;
    $ret .= "</td></tr>";

    $ret .= "<tr><td class='setting_label'><label for='${key}sms_carrier'>" . $class->ml('setting.sms.option.carrier') . "</label></td>";
    $ret .= "<td>" . LJ::html_select({
        name => "${key}sms_carrier",
        id => "${key}sms_carrier",
        selected => $carrier || "",
        noescape => 1,
    }, ("", $class->ml('setting.sms.option.carrier.selectone')), @carriers);
    my $carrier_errdiv = $class->errdiv($errs, "sms_carrier");
    $ret .= "<br />$carrier_errdiv" if $carrier_errdiv;
    $ret .= "</td></tr>";

    $ret .= "<tr><td>&nbsp;</td>";
    $ret .= "<td><a href='$LJ::SITEROOT/manage/sms/'>" . $class->ml('setting.sms.option.advanced') . "</a></td></tr>";

    $ret .= "</table>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $phone_val = $class->get_arg($args, "sms_phone");
    my $carrier_val = $class->get_arg($args, "sms_carrier");

    # set carrier
    {
        if (%LJ::SMS_CARRIERS && $carrier_val && grep { $_ eq $carrier_val } keys %LJ::SMS_CARRIERS) {
            $u->set_prop( sms_carrier => $carrier_val );

        # invalid carrier
        } elsif ($carrier_val) {
            $class->errors( sms_carrier => $class->ml('setting.sms.error.carrier.invalid') );

        # clear carrier
        } elsif (!$carrier_val && !$phone_val) {
            $u->set_prop( sms_carrier => undef );
        }
    }

    my $new_msisdn = $phone_val;

    # user posted but with blank msisdn, clear it if it's mapped
    unless ($new_msisdn) {
        $u->delete_sms_number;
        $u->set_prop( sms_carrier => undef );
    }

    # strip out invalid characters
    $new_msisdn =~ s/[^\+\d]//g if $new_msisdn;

    # normalize given number to actual msisdn for storage in db
    if ($new_msisdn =~ /^\+?1?(\d{10})$/ && $1 !~ /^555/ && $u->prop("sms_carrier")) {
        # strip off leading + and leading 1, then re-add to normalize
        $new_msisdn =~ s/^\+//;
        $new_msisdn =~ s/^1//;

        # keep around a stripped version of the new msisdn, but also
        # make $new_msisdn a canonicalized version with +1
        my $new_msisdn_stripped = $new_msisdn;
        $new_msisdn = "+1$new_msisdn";

        # check for sysban on this msisdn
        if (LJ::sysban_check("msisdn", $new_msisdn_stripped)) {
            LJ::sysban_note($u->id, "Tried to register a banned MSISDN", { msisdn => $new_msisdn });
            $class->errors( sms_phone => $class->ml('setting.sms.error.phone.failed', { number => $new_msisdn }) );
        }

        # if user entered a number which doesn't match their current mapping...
        if ($u->sms_mapped_number ne $new_msisdn) {
            # in this instance we're looking to see if someone already has this
            # number verified in order to check for number stealing below
            my $existing_num_uid = LJ::SMS->num_to_uid($new_msisdn, verified_only => 1);

            # don't let them steal a number!
            if ($existing_num_uid && $existing_num_uid != $u->id) {
                $class->errors( sms_phone => $class->ml('setting.sms.error.phone.inuse') );

            # check rate limiting
            } elsif (!$u->rate_log("sms_register", 1)) {
                $class->errors( sms_phone => $class->ml('setting.sms.error.phone.ratelimit') );

            } else {
                # map the number
                $u->set_sms_number($new_msisdn, verified => 'N'); # not verified

                # run the post-reg hook
                my @errors;
                LJ::run_hook('sms_post_register', u => $u, errors => \@errors);
                foreach my $err (@errors) {
                    $class->errors( sms_phone => $err );
                }
            }
        }
    } elsif (!$u->prop("sms_carrier") && $phone_val) {
        # tried to set number but no carrier set
        $class->errors( sms_carrier => $class->ml('setting.sms.error.carrier.none') );
    } elsif ($phone_val) {
        # user has not entered a valid number for registration
        $class->errors( sms_phone => $class->ml('setting.sms.error.phone.invalid') );
    }

    LJ::run_hook('sms_bml_post', u => $u, POST => {});

    return 1;
}

1;
