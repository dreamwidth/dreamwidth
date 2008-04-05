package LJ::Setting::MailEncoding;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(mail translate encoding) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my %mail_encnames;
    LJ::load_codes({ "encname" => \%mail_encnames } );

    my $ret = "<?h2 $BML::ML{'.translatemailto.header'} h2?>\n";
    $ret .= LJ::html_select({ 'name' => "${key}mailencoding",
                              'selected' => $u->prop('mailencoding')},
                              map { $_, $mail_encnames{$_} } sort keys %mail_encnames);
    $ret .= "<br />\n$BML::ML{'.translatemailto.about'}";
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $val = $args->{'mailencoding'};

    my %mail_encnames;
    LJ::load_codes({ "encname" => \%mail_encnames } );
    $class->errors(oldenc => "Invalid") unless ! $val || $mail_encnames{$val};

    return 1 if $val eq $u->prop('mailencoding');
    return 0 unless $u->set_prop('mailencoding', $val);
    return 1;
}

1;



