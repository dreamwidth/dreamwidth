package DW::Setting::XPostAccounts;
use base 'LJ::Setting';
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);

sub tags { qw(xpost_option_server xpost_option_username xpost_option_password xpost_option_xpostbydefault crosspost_footer_append crosspost_footer_text) }

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
    return unless LJ::isu( $u );

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

    # convenience
    my $key = $class->pkgkey;

    # be sure to add your style info in htdocs/stc/settings.css or this won't
    # look very good.
    $ret .= "<h2>" . $class->ml('setting.xpost.accounts') ."</h2><br/>"; 
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
            $ret .= "<td style='text-align: center;'><a href='$LJ::SITEROOT/manage/externalaccount?acctid=${acctid}'>" . $class->ml('setting.xpost.option.change') . "</a></td>\n";
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
    my $max_accounts = $u->count_max_xpost_accounts;
    $ret .= "<p style='text-align: center;'>" . $class->ml('setting.xpost.message.usage', { current => scalar @accounts, max => $max_accounts });

    # add account
    if (scalar @accounts < $max_accounts) {
        $ret .= "<div class='xpost_add'><a href='$LJ::SITEROOT/manage/externalaccount'>" . $class->ml('setting.xpost.btn.add') . "</a></div>\n";
    }

    $ret .= "<h2>" . $class->ml('setting.xpost.settings') . "</h2>";
    # disable comments on crosspost
    $ret .= "<table><tr>";
    $ret .= "<td><b>" . $class->ml('setting.xpost.comments') . "</b></td><td><label for='${key}xpostdisablecomments'>" . $class->ml('setting.xpost.option.disablecomments') . "</label></td><td>";
    $ret .= LJ::html_check({
        name     => "${key}xpostdisablecomments",
        value    => 1,
        id       => "${key}xpostdisablecomments",
        selected => $u->prop('opt_xpost_disable_comments')
        }) .  "</p>";
    $ret .= "</td></tr>";
    
    # When should the footer be displayed?
    $ret .= "<tr><td><b>" . $class->ml('setting.xpost.footer') . "</b></td><td><label for='${key}crosspost_footer_append'>" . $class->ml( 'setting.xpost.option.footer.when' ) . "</label></td><td>";
    my $append_when = $u->prop('crosspost_footer_append');

    $ret .= LJ::html_select({
        name      => "${key}crosspost_footer_append",
        id        => "${key}crosspost_footer_append",
        class     => "select",
        selected  => $append_when || 'D' },
        'A'       => $class->ml( 'setting.xpost.option.footer.when.always' ),
        'D'       => $class->ml( 'setting.xpost.option.footer.when.disabled' ),
        'N'       => $class->ml( 'setting.xpost.option.footer.when.never' )
    );
    $ret .= "</td></tr>";

    # define custom footer
    $ret .= "<tr><td>&nbsp</td><td colspan='2'><label for='${key}crosspost_footer_text'>" . $class->ml( 'setting.xpost.option.footer' ) . "</label><br/>";

    my $footer_text = $u->prop('crosspost_footer_text');

    $ret .= LJ::html_textarea({
        name      => "${key}crosspost_footer_text",
        id        => "${key}crosspost_footer_text",
        rows      => 3,
        cols      => 80,
        maxlength => "512",
        onkeyup   => "javascript:updatePreview()",
        value     => $footer_text
    }) . "<br/><br/>";

    $ret .= "<div id='preview_section' style='display: none;'>" . $class->ml('setting.xpost.preview') . "\n";

    my $baseurl = $LJ::SITEROOT;
    my $alttext = $class->ml('setting.xpost.option.footer.vars.comment_image.alttext');
    my $default_comment = $class->ml('xpost.redirect.comment', { postlink => "%%url%%" });

    $ret .= qq [
      <div id='footer_preview' class='xpost_footer_preview'></div>
      </div>
      <script type="text/javascript">
        function updatePreview() {
          var previewString = \$('${key}crosspost_footer_text').value;
          if (! previewString) {
            previewString = '$default_comment';
          }
          previewString = previewString.replace(/%%url%%/, '$baseurl/12345.html');
          previewString = previewString.replace(/%%reply_url%%/, '$baseurl/12345.html?mode=reply');
          previewString = previewString.replace(/%%comment_url%%/, '$baseurl/12345.html#comments');
          previewString = previewString.replace(/%%comment_image%%/, '<img src="$baseurl/tools/commentcount?samplecount=23" width="30" height="12" alt="$alttext" style="vertical-align: middle;"/>');
          \$('footer_preview').innerHTML = previewString;
        }
        \$('preview_section').style.display = 'block';
        updatePreview();
      </script>
    ];
    $ret .= "<p style='font-size: smaller;'>" . $class->ml('setting.xpost.option.footer.vars') . "<br/>";
    foreach my $var qw (url reply_url comment_url comment_image) {
        $ret .= "<b>%%$var%%</b>: " . $class->ml("setting.xpost.option.footer.vars.$var") . "<br/>\n";
    }
    $ret .= "<br/>" . $class->ml("setting.xpost.footer.default.label") .  "<br/>" . LJ::ehtml($default_comment) . "\n";
    $ret .= "</td></tr></table>\n";
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

    # change footer text
    $u->set_prop( crosspost_footer_text => $class->get_arg( $args, "crosspost_footer_text" ) );

    # change footer display
    $u->set_prop( crosspost_footer_append => $class->get_arg( $args, "crosspost_footer_append" ) );


    return 1;
}

1;
