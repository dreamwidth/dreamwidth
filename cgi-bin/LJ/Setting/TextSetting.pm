package LJ::Setting::TextSetting;
use base 'LJ::Setting';
use strict;
use warnings;
use Carp qw(croak);

# if override to something non-undef, current_value and save_text work
# assuming a userprop
sub prop_name { undef }

sub current_value {
    my ($class, $u) = @_;
    if (my $propname = $class->prop_name) {
        return $u->prop($propname);
    }
    croak;
}

sub get_arg {
    my ($class, $args) = @_;
    return LJ::Setting::get_arg($class, $args, "txt");
}

# zero means no limit.
sub max_bytes { 0 }
sub max_chars { 0 }

# display size:
sub text_size { 40 }

sub question { croak; }

sub as_html {
    my ($class, $u, $errs, $post) = @_;
    my $key = $class->pkgkey;
    return "<label for=''>" . $class->question . "</label>" .
        LJ::html_text({
            name  => "${key}txt",
            id    => "${key}txt",
            class => "text",
            value => $errs ? $class->get_arg($post, "txt") : $class->current_value($u),
            size  => $class->text_size,
            maxlength => $class->max_chars || undef,
        }) .
        $class->errdiv($errs, "txt");
}

# each subclass can override if necessary
sub error_check { 1 }

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $txt = $args->{txt} || "";
    return 1 if $txt eq $class->current_value($u);
    unless (LJ::text_in($txt)) {
        $class->errors(txt => "Invalid UTF-8");
    }
    if ($class->max_bytes || $class->max_chars) {
        my $trimmed = LJ::text_trim($txt, $class->max_bytes, $class->max_chars);
        $class->errors(txt => "Too long") if $trimmed ne $txt;
    }
    return $class->save_text($u, $txt);
}

sub save_text {
    my ($class, $u, $txt) = @_;
    if (my $propname = $class->prop_name) {
        return $u->set_prop($propname, $txt);
    }
    croak;
}

1;



