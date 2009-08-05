package LJ::Setting::Display::Email;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return $u->is_validated ? "change_email" : "validate_email";
}

sub actionlink {
    my ($class, $u) = @_;

    my $text = $u->is_identity && !$u->email_raw ? $class->ml('setting.display.email.actionlink.set') : $class->ml('setting.display.email.actionlink.change');
    return "<a href='$LJ::SITEROOT/changeemail?authas=" . $u->user . "'>$text</a>";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.email.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    my $email = $u->email_raw;

    if ($u->is_identity && !$email) {
        return "";
    } elsif ($u->email_status eq "A") {
        return "$email " . $class->ml('setting.display.email.option.validated');
    } else {
        return "$email " . $class->ml('setting.display.email.option.notvalidated', { aopts => "href='$LJ::SITEROOT/register?authas=" . $u->user . "'" });
    }
}

1;
