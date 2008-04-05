package LJ::Setting::OldEncoding;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(encoding) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my (%old_encnames, %encodings);
    LJ::load_codes({ "encoding" => \%encodings } );
    LJ::load_codes({ "encname" => \%old_encnames } );

    # which encodings to show? For now, we just delete utf-8 from the
    # old encodings list because it doesn't make sense there.
    foreach my $id (keys %encodings) {
        delete $old_encnames{$id} if lc($encodings{$id}) eq 'utf-8';
    }

    my $ret = "<?h2 $BML::ML{'.encoding.header'} h2?>\n";
    $ret .= "$BML::ML{'.autotranslate.header'}<br />\n";
    $ret .= LJ::html_select({ 'name' => "${key}oldenc", 'selected' => $u->{'oldenc'}},
                              map { $_, $old_encnames{$_} } sort keys %old_encnames );
    $ret .= "<br />\n$BML::ML{'.autotranslate.about'}";
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $arg = $args->{'oldenc'};
    $class->errors(oldenc => "Invalid") unless $arg =~ /^\d*$/;
    return 1 if $arg eq $u->{'oldenc'};
    return 0 unless LJ::update_user($u, { oldenc => $arg });
    return 1;
}

1;



