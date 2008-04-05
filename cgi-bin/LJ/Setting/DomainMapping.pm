package LJ::Setting::DomainMapping;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(domain domainname mapping forwarding alias) }

sub save {
    my ($class, $u, $args) = @_;

    my $has_cap = $u->get_cap('domainmap');

    # sanitize POST value

    my $domainname = $args->{journaldomain};
    $domainname =~ s!^(http://)?(www\.)?!!;
    $domainname = lc($domainname);

    my $dbh = LJ::get_db_writer();

    unless ($LJ::OTHER_VHOSTS) {
        $class->errors(domainname => "Feature is disabled sitewide.");
        return;
    }

    $class->errors(domainname => "Bogus domain name") if $domainname =~ /\s+/;

    # Blank domain = delete mapping
    if ($domainname eq "") {
        $dbh->do("DELETE FROM domains WHERE userid=?", undef, $u->{userid});
        $u->set_prop("journaldomain", "");
    # If they're able to, change the mapping and update the userprop
    } elsif ($has_cap) {
        return if $domainname eq $u->prop('journaldomain');
        $dbh->do("INSERT INTO domains VALUES (?, ?)", undef, $domainname, $u->{'userid'});
        if ($dbh->err) {
            my $otherid = $dbh->selectrow_array("SELECT userid FROM domains WHERE domain=?",
                                                undef, $domainname);
            if ($otherid != $u->{'userid'}) {
                $class->errors(domainname => "Duplicate mapping");
                return;
            }
        }
        $u->set_prop("journaldomain", $domainname);
        if ($u->prop('journaldomain')) {
            $dbh->do("DELETE FROM domains WHERE userid=? AND domain <> ?",
                     undef, $u->{'userid'}, $domainname);
        }
    # Otherwise do nothing.
    } else {
        $class->errors(access => "Your current account settings do not allow you to modify your domain mapping.");
    }
}

sub as_html {
    my ($class, $u, $errs) = @_;
    $errs ||= {};

    my $has_cap = $u->get_cap('domainmap');
    my $has_dom = $u->prop('journaldomain') ? 1 : 0;

    my $key = $class->pkgkey;
    my $ret = "Domain Name: " .
        LJ::html_text({
            name  => "${key}journaldomain",
            value => $u->prop('journaldomain'),
            size  => 30,
            maxlength => 80,
        });

    $ret .= "<br />Clear the box to remove your domain mapping." if $has_dom;
    $ret .= $class->errdiv($errs, "domainname");
    $ret .= $class->errdiv($errs, "access");

    $ret = "The domain mapping feature is not available for this site." unless $LJ::OTHER_VHOSTS;
    return $ret;
}

1;



