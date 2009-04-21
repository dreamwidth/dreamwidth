package DW::Setting::XPostAccounts;
use base 'LJ::Setting';
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);

sub tags { qw(xpost_option_server xpost_option_username xpost_option_password xpost_option_xpostbydefault) }

# show this setting editor
sub should_render {
    my ($class, $u) = @_;

    return 1;
}

# link to the help url
sub helpurl {
    my ($class, $u) = @_;

    return "cross_post";
}

# label; by default, displayed on the left side of the editor page
sub label {
    my $class = shift;

    return $class->ml('setting.xpost.label');
}

# option. this is where all of the entered info is displayed.  in this case,
# shows both the existing configured ExternalAccounts, as well as the UI for
# adding new accounts.
sub option {
    my ($class, $u, $errs, $args, %opts) = @_;
    my $key = $class->pkgkey;

    # first load up the existing accounts.
    my @accounts = DW::External::Account->get_external_accounts($u);

    # label displayed at top of the option (right) section
    my $ret .= "<p>" . $class->ml('setting.xpost.option') . "</p>";

    # check to see if we have an update message
    my $getargs = $opts{getargs};
    if ($getargs) {
        if ($getargs->{create}) {
            my $acct = DW::External::Account->get_external_account($u, $getargs->{create});
            # FIXME blue is temporary.  move to css.
            $ret .= "<div style='color: blue;'>" . $class->ml('setting.xpost.message.create', { username => $acct->username, servername => $acct->servername }) . "</div>";
        } elsif ($getargs->{update}) {
            my $acct = DW::External::Account->get_external_account($u, $getargs->{update});
            # FIXME blue is temporary.  move to css.
            $ret .= "<div style='color: blue;'>" . $class->ml('setting.xpost.message.update', { username => $acct->username, servername => $acct->servername }) . "</div>";
        }
    }

    # be sure to add your style info in htdocs/stc/settings.css or this won't
    # look very good.
    $ret .= "<table class='setting_table'>\n";
    if (scalar @accounts) {
        $ret .= "<tr>\n";
        $ret .= "<th>" . $class->ml('setting.xpost.option.username') . "</th>\n";
        $ret .= "<th>" . $class->ml('setting.xpost.option.server') . "</th>\n";
        $ret .= "<th>" . $class->ml('setting.xpost.option.xpostbydefault') . "</th>\n";
        $ret .= "<th>" . $class->ml('setting.xpost.option.change') . "</th>\n";
        $ret .= "<th>" . $class->ml('setting.xpost.option.delete') . "</th>\n";
        $ret .= "</tr>\n";

        # display each account
        foreach my $externalacct (@accounts) {
            my $acctid = $externalacct->acctid;
            $ret .= "<tr>\n";
            $ret .= "<td><input type=hidden name='${key}displayed[${acctid}]' value='1'/>" . $externalacct->username . "</td>";
            $ret .= "<td>" . $externalacct->servername . "</td>";
            $ret .= "<td class='checkbox'>" . LJ::html_check({
                name     => "${key}xpostbydefault[${acctid}]",
                value    => 1,
                id       => "${key}xpostbydefault[${acctid}]",
                selected => $externalacct->xpostbydefault
            }) . "</td>";
            $ret .= "<td style='text-align: center;'><a href='$LJ::SITEROOT/manage/externalaccount.bml?acctid=${acctid}'>" . $class->ml('setting.xpost.option.change') . "</a></td>\n";
            $ret .= "<td class='checkbox'>" . LJ::html_check({
                name     => "${key}delete[${acctid}]",
                value    => 1,
                id       => "${key}delete[${acctid}]",
                selected => 0
            }) . "</td>";
            $ret .= "</tr>\n";
        }
    } else {
        $ret .= "<tr><td>" . $class->ml('setting.xpost.noaccounts') . "</td></tr>\n";
    }
    $ret .= "</table>\n";

    # show account usage.
    my $max_accounts = LJ::get_cap($u, "xpost_accounts");
    $ret .= "<p style='text-align: center;'>" . $class->ml('setting.xpost.message.usage', { current => scalar @accounts, max => $max_accounts });

    # add account
    if (scalar @accounts < $max_accounts) {
        $ret .= "<div class='xpost_add'><a href='$LJ::SITEROOT/manage/externalaccount.bml'>" . $class->ml('setting.xpost.btn.add') . "</a></div>\n";
    }

    # disable comments on crosspost
    $ret .= "<p><label for='${key}xpostdisablecomments'>" . $class->ml('setting.xpost.option.disablecomments') . "</label>";
    $ret .= LJ::html_check({
        name     => "${key}xpostdisablecomments",
        value    => 1,
        id       => "${key}xpostdisablecomments",
        selected => $u->prop('opt_xpost_disable_comments')
        }) .  "</p>";

    return $ret;
}

# each subclass can override if necessary
sub error_check { 1 }

# this is basically your form handler.  takes the submitted form and makes
# the appropriate changes.
sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    # update existing accounts
    my @accounts = DW::External::Account->get_external_accounts($u);
    for my $account (@accounts) {
        my $acctid = $account->{'acctid'};
        if ($class->get_arg($args, "displayed[$acctid]")) {
            # delete account if selected
            if ($class->get_arg($args, "delete[$acctid]")) {
                $account->delete();
            } else {
                # check to see if we need to reset the xpostbydefault
                if ($class->get_arg($args, "xpostbydefault[$acctid]") ne $account->{'xpostbydefault'}) {
                    $account->set_xpostbydefault($class->get_arg($args, "xpostbydefault[$acctid]"));
                }
            }
        }
    }

    # reset disable comments
    $u->set_prop( opt_xpost_disable_comments => $class->get_arg($args, "xpostdisablecomments") ? "1" : "0");

    return 1;
}

1;
