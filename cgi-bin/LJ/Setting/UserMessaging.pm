package LJ::Setting::UserMessaging;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(email message contact) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $ret;

    $ret .= "<label for='${key}opt_usermsg'>" . $class->ml('settings.usermessaging.question') . "</label>";
    $ret .= LJ::html_select({ 'name' => "${key}opt_usermsg",
                              'id' => "${key}opt_usermsg",
                              'class' => "select",
                              'selected' => $u->opt_usermsg },
                              { text => LJ::Lang::ml('settings.usermessaging.opt.Y'),
                                value => "Y",},
                              { text => LJ::Lang::ml('settings.usermessaging.opt.F'),
                                value => "F",},
                              { text => LJ::Lang::ml('settings.usermessaging.opt.M'),
                                value => "M",},
                              { text => LJ::Lang::ml('settings.usermessaging.opt.N'),
                                value => "N",});
    $ret .= "<div class='helper'>" .
            $class->ml('settings.usermessaging.helper', {
                sitename => $LJ::SITENAMESHORT }) .
            "</div>";
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
