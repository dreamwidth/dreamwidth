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

package LJ::Widget::Login;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/login.css js/md5.js js/login.js) }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote();
    return "" if $remote;

    my $nojs = $opts{nojs};
    my $user = $opts{user};
    my $mode = $opts{mode};

    my $getextra = $nojs ? '?nojs=1' : '';

    # Is this the login page?
    # If so treat ret value differently
    my $r = eval { BML::get_request() };
    my $isloginpage = 0;
    $isloginpage = 1 if ($r->uri eq '/login.bml');

    if (!$isloginpage && $opts{get_ret} == 1) {
        $getextra .= $getextra eq '' ? '?ret=1' : '&ret=1';
    }

    my $root = $LJ::IS_SSL ? $LJ::SSLROOT : $LJ::SITEROOT;
    my $form_class = LJ::Hooks::run_hook("login_form_class_name_$opts{mode}");
    $form_class = "lj_login_form pkg" unless $form_class;
    $ret .= "<form action='$root/login$getextra' method='post' class='$form_class'>\n";
    $ret .= LJ::form_auth();

    my $chal = LJ::challenge_generate(300); # 5 minute auth token
    $ret .= "<input type='hidden' name='chal' class='lj_login_chal' value='$chal' />\n";
    $ret .= "<input type='hidden' name='response' class='lj_login_response' value='' />\n";

    my $referer = BML::get_client_header('Referer');
    if ($isloginpage && $opts{get_ret} == 1 && $referer) {
        my $eh_ref = LJ::ehtml($referer);
        $ret .= "<input type='hidden' name='ref' value='$eh_ref' />\n";
    }

    if (! $opts{get_ret} && $opts{ret_cur_page}) {
        # use current url as return destination after login, for inline login
        $ret .= LJ::html_hidden('ret', $LJ::SITEROOT . BML::get_uri());
    }

    if ($opts{returnto}) {
        $ret .= LJ::html_hidden('returnto', $opts{returnto});
    }

    my $hook_rv = LJ::Hooks::run_hook("login_form_$opts{mode}", create_link => $opts{create_link});
    if ($hook_rv) {
        $ret .= $hook_rv;
    } else {
        # TabIndex
        # tab indexes start at 11, instead of 1, in order to make
        # the mid-page tab indexes start AFTER the login
        # information in the site header in all of the non-lynx
        # site schemed pages. Possibly this should be replaced
        # with a tabindex variable which is scoped by page
        # instead of by widget.
        $ret .= "<h2>" . LJ::Lang::ml('/login.bml.login.welcome', { 'sitename' => $LJ::SITENAMESHORT }) . "</h2>\n";
        $ret .= "<fieldset class='pkg nostyle'>\n";
        $ret .= "<label for='user' class='left'>" . LJ::Lang::ml('/login.bml.login.username') . "</label>\n";
        $ret .= "<input type='text' value='$user' name='user' id='user' class='text' size='18' maxlength='27' style='' tabindex='11' />\n";
        $ret .= "</fieldset>\n";
        $ret .= "<fieldset class='pkg nostyle'>\n";
        $ret .= "<label for='lj_loginwidget_password' class='left'>" . LJ::Lang::ml('/login.bml.login.password') . "</label>\n";
        $ret .= "<input type='password' id='lj_loginwidget_password' name='password' class='lj_login_password text' size='20' maxlength='30' tabindex='12' /><a href='$LJ::SITEROOT/lostinfo' class='small-link' tabindex='16'>" 
                . LJ::Lang::ml('/login.bml.login.forget2') 
                . "</a>\n";
        $ret .= "</fieldset>\n";
        $ret .= "<p><input type='checkbox' name='remember_me' id='remember_me' value='1' tabindex='13' /> <label for='remember_me'>Remember me</label></p>";

        # standard/secure links removed for now
        my $secure = "<p>";
        $secure .= "<img src='$LJ::IMGPREFIX/padlocked.gif' class='secure-image' width='20' height='16' alt='secure login' />";
        $secure .= LJ::Lang::ml('/login.bml.login.secure') . " | <a href='$LJ::SITEROOT/login?nojs=1'>" . LJ::Lang::ml('/login.bml.login.standard') . "</a></p>";

        $ret .= "<p><input name='action:login' type='submit' value='"
                . LJ::Lang::ml('/login.bml.login.btn.login') 
                . "' tabindex='14' /> <a href='$LJ::SITEROOT/openid/' class='small-link' tabindex='15'>" 
                . LJ::Lang::ml('/login.bml.login.openid') 
                . "</a></p>";

        if (! $LJ::IS_SSL) {
            my $login_btn_text = LJ::ejs(LJ::Lang::ml('/login.bml.login.btn.login'));

            if ($nojs) {
                # insecure now, but because they choose to not use javascript.  link to
                # javascript version of login if they seem to have javascript, otherwise
                # noscript to SSL
                $ret .= "<script type='text/javascript' language='Javascript'>\n";
                $ret .= "<!-- \n document.write(\"<p style='padding-bottom: 5px'><img src='$LJ::IMGPREFIX/unpadlocked.gif' width='20' height='16' alt='secure login' align='middle' />" .
                    LJ::ejs(" <a href='$LJ::SITEROOT/login'>" . LJ::Lang::ml('/login.bml.login.secure') . "</a> | " . LJ::Lang::ml('/login.bml.login.standard') . "</p>") .
                    "\"); \n // -->\n </script>\n";
                if ($LJ::USE_SSL) {
                    $ret .= "<noscript>";
                    $ret .= "<p style='padding-bottom: 5px'><img src='$LJ::IMGPREFIX/unpadlocked.gif' width='20' height='16' alt='secure login' align='middle' /> <a href='$LJ::SSLROOT/login'>" . LJ::Lang::ml('/login.bml.login.secure') . "</a> | " . LJ::Lang::ml('/login.bml.login.standard') . "</p>";
                    $ret .= "</noscript>";
                }
            } else {
                # insecure now, and not because it was forced, so javascript doesn't work.
                # only way to get to secure now is via SSL, so link there
                $ret .= "<p><img src='$LJ::IMGPREFIX/unpadlocked.gif' width='20' height='16' class='secure-image' alt='secure login' />";
                $ret .= " <a href='$LJ::SSLROOT/login'>" . LJ::Lang::ml('/login.bml.login.secure') . "</a> | " . LJ::Lang::ml('/login.bml.login.standard') . "</p>\n"
                    if $LJ::USE_SSL;

            }
        }
        $ret .= LJ::help_icon('securelogin', '&nbsp;');

        if (LJ::Hooks::are_hooks("login_formopts")) {
            $ret .= "<table>";
            $ret .= "<tr><td>" . LJ::Lang::ml('/login.bml.login.otheropts') . "</td><td style='white-space: nowrap'>\n";
            LJ::Hooks::run_hooks("login_formopts", { 'ret' => \$ret });
            $ret .= "</td></tr></table>";
        }
    }

    # Save offsite redirect uri between POSTs
    my $redir = $opts{get_ret} || $opts{post_ret};
    $ret .= LJ::html_hidden('ret', $redir) if $redir && $redir != 1;

    $ret .= "</form>\n";

    return $ret;
}

1;
