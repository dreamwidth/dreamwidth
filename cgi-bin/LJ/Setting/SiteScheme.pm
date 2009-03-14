package LJ::Setting::SiteScheme;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "site_schemes";
}

sub label {
    my $class = shift;

    return $class->ml('setting.sitescheme.label');
}

sub option {
    my ($class, $u, $errs, $args, %opts) = @_;
    my $key = $class->pkgkey;

    my @bml_schemes = LJ::site_schemes();
    return "" unless @bml_schemes;

    my $show_hidden = $opts{getargs}->{view} && $opts{getargs}->{view} eq "schemes";
    my $sitescheme = $class->get_arg($args, "sitescheme") || BML::get_scheme() || $BML::COOKIE{BMLschemepref} || $bml_schemes[0]->{scheme};

    my $ret;
    foreach my $scheme (@bml_schemes) {
        my $label = $scheme->{title};
        my $value = $scheme->{scheme};
        my $is_hidden = $scheme->{hidden} ? 1 : 0;

        next if !$show_hidden && $is_hidden && $sitescheme ne $value;

        my $desc = $scheme->{desc} && LJ::Lang::string_exists($scheme->{desc}) ? LJ::Lang::ml($scheme->{desc}) : "";
        $label .= " ($desc)" if $desc;

        $ret .= LJ::html_check({
            type => "radio",
            name => "${key}sitescheme",
            id => "${key}sitescheme_$value",
            value => $value,
            selected => $sitescheme eq $value ? 1 : 0,
        }) . "<label for='${key}sitescheme_$value' class='radiotext'>$label</label>";
    }

    my $errdiv = $class->errdiv($errs, "sitescheme");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "sitescheme");

    return 1 unless $val;

    my @scheme_names;
    foreach my $scheme (LJ::site_schemes()) {
        push @scheme_names, $scheme->{scheme};
    }

    $class->errors( sitescheme => $class->ml('setting.sitescheme.error.invalid') )
        unless $val && grep { $val eq $_ } @scheme_names;

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $val = my $cval = $class->get_arg($args, "sitescheme");
    return 1 unless $val;
    my @bml_schemes = LJ::site_schemes();

    # don't set cookie for default scheme
    if ($val eq $bml_schemes[0]->{scheme} && !$LJ::SAVE_SCHEME_EXPLICITLY) {
        $cval = "";
        delete $BML::COOKIE{BMLschemepref};
    }

    if ($u) {
        # set a userprop to remember their schemepref
        $u->set_prop( schemepref => $val );

        # cookie expires when session expires
        $cval = [ $val, $u->{_session}->{timeexpire} ]
            if $u->{_session}->{exptype} eq "long";
    }

    # set cookie
    $BML::COOKIE{BMLschemepref} = $cval if $cval;
    BML::set_scheme($val);

    return 1;
}

1;
