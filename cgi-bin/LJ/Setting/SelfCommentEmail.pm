package LJ::Setting::SelfCommentEmail;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub disabled {
    my ($class, $u) = @_;

    return $u->can_get_self_email;
}

sub selected {
    my ($class, $u) = @_;

    return $u->prop("opt_getselfemail") && !$class->disabled($u) ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.selfcommentemail.label');
}

sub option {
    my ($class, $u, $errs, $args, %opts) = @_;

    return $class->htmlcontrol($u, $errs, $args, %opts) . " " . $class->htmlcontrol_label($u);
}

sub htmlcontrol_label {
    my ($class, $u) = @_;
    my $key = $class->pkgkey;

    return "<label for='${key}selfcommentemail'>" . $class->ml('setting.selfcommentemail.option') . "</label>";
}

sub htmlcontrol {
    my ($class, $u, $errs, $args, %opts) = @_;
    my $key = $class->pkgkey;

    if ($opts{notif}) {
        my $catid = $opts{notif_catid};
        my $ntypeid = $opts{notif_ntypeid};

        return LJ::html_check({
            class => "SubscribeCheckbox-$catid-$ntypeid",
            selected => 1,
            disabled => 1,
        });
    } else {
        return LJ::html_check({
            name => "${key}selfcommentemail",
            id => "${key}selfcommentemail",
            class => "SubscriptionInboxCheck",
            value => 1,
            selected => $class->selected($u) ? 1 : 0,
            disabled => $class->disabled($u) ? 1 : 0,
        });
    }
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "selfcommentemail") ? 1 : 0;
    $u->set_prop( opt_getselfemail => $val );

    return 1;
}

1;
