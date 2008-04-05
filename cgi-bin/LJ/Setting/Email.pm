package LJ::Setting::Email;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(email mail address) }

sub save {
    my ($class, $u, $args) = @_;
    my $email = $args->email_raw;
    return 1 if $email eq $u->email_raw;

    my @errors;
    local $BML::ML_SCOPE = "/editinfo.bml";

    if ($LJ::EMAIL_CHANGE_REQUIRES_PASSWORD) {
        push @errors, "You cannot change your your email address here.";
    } else {
        push @errors, $BML::ML{'.error.email.none'}
           unless $email;

        push @errors, BML::ml(".error.email.lj_domain", { 'user' => $u->{'user'}, 'domain' => $LJ::USER_DOMAIN, })
            if ($LJ::USER_EMAIL and $email =~ /\@\Q$LJ::USER_DOMAIN\E$/i);

        push @errors, $BML::ML{'.error.email.no_space'}
            if $email =~ /\s/;
    }

    LJ::check_email($email, \@errors) unless @errors;

    return 1 unless @errors;
    $class->errors(email => join(", ", @errors));
}

sub as_html {
    my ($class, $u, $errs) = @_;
    $errs ||= {};

    my $disabled = 0;
    if ($LJ::EMAIL_CHANGE_REQUIRES_PASSWORD) {
        $disabled = 1;
    }

    my $key = $class->pkgkey;
    my $ret = "What's your email address? " .
        LJ::html_text({
            name  => "${key}email",
            value => $u->email_raw,
            size  => 40,
            disabled => $disabled,
        });

    if ($LJ::EMAIL_CHANGE_REQUIRES_PASSWORD) {
        $ret .= "<p>$LJ::SITENAME requires that you change your email address over a secure connection, here: <a href='$LJ::SITEROOT/changeemail.bml'>change email</a>.</p>";
    }

    $ret .= $class->errdiv($errs, "email");
    return $ret;
}

1;



