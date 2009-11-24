package LJ::Setting::MinSecurity;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "minsecurity_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.minsecurity.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $minsecurity = $class->get_arg($args, "minsecurity") || $u->prop("newpost_minsecurity");

    my @options = (
        "" => $class->ml('setting.minsecurity.option.select.public'),
        friends => $u->is_community ? $class->ml('setting.minsecurity.option.select.members') : $class->ml('setting.minsecurity.option.select.friends'),
        private => $u->is_community ?
        $class->ml( 'setting.minsecurity.option.select.admin' ) :
        $class->ml( 'setting.minsecurity.option.select.private' )
    );


    my $ret = "<label for='${key}minsecurity'>" . $class->ml('setting.minsecurity.option') . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}minsecurity",
        id => "${key}minsecurity",
        selected => $minsecurity,
    }, @options);

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "minsecurity");
    $val = "" unless $val =~ /^(friends|private)$/;

    $u->set_prop( newpost_minsecurity => $val );

    return 1;
}

1;
