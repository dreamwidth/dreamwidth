package LJ::Setting::Display::SecretQuestion;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "secret_question";
}

sub actionlink {
    my ($class, $u) = @_;

    my $text = $u->prop("secret_question_text") ? $class->ml('setting.display.secretquestion.actionlink.change') : $class->ml('setting.display.secretquestion.actionlink.set');
    return "<a href='$LJ::SITEROOT/set_secret.bml'>$text</a>";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.secretquestion.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return $u->prop("secret_question_text") ? "******" : "";
}

1;
