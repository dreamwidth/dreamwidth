package LJ::Setting::Gender;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(gender sex male female boy girl other) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    # show the one just posted, else the default one.
    my $gender = $class->get_arg($args, "gender") ||
        $u->prop("gender");

    return "<label for='${key}gender'>" . $class->ml('.setting.gender.question') . "</label>" .
        LJ::html_select({ 'name' => "${key}gender", 'id' => '${key}gender', 'class' => 'select', 'selected' => $gender || 'U' },
                        'F' => LJ::Lang::ml('/manage/profile/index.bml.gender.female'),
                        'M' => LJ::Lang::ml('/manage/profile/index.bml.gender.male'),
                        'O' => LJ::Lang::ml('/manage/profile/index.bml.gender.other'),
                        'U' => LJ::Lang::ml('/manage/profile/index.bml.gender.unspecified') ) .
                        $class->errdiv($errs, "gender");
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "gender");
    $class->errors("gender" => $class->ml('.setting.gender.error.invalid')) unless $val =~ /^[UMFO]$/;
    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $gen = $class->get_arg($args, "gender");
    return 1 if $gen eq ($u->prop('gender') || "U");

    $gen = "" if $gen eq "U";
    $u->set_prop("gender", $gen);
    $u->invalidate_directory_record;
}

1;



