package LJ::Setting::Display::DomainMapping;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $LJ::OTHER_VHOSTS && $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "domain_mapping";
}

sub actionlink {
    my ($class, $u) = @_;

    my $has_domain = $u->prop("journaldomain") ? 1 : 0;
    my $upgrade_url = LJ::run_hook("upgrade_link", $u, "plus", url_only => 1) || "";
    my $upgrade_link = LJ::run_hook("upgrade_link", $u, "plus") || "";

    if ($u->get_cap('domainmap')) {
        return "<a href='$LJ::SITEROOT/manage/domain?authas=" . $u->user . "'>" . $class->ml('setting.display.domainmapping.actionlink') . "</a>";
    } elsif ($has_domain) {
        return "<a href='$LJ::SITEROOT/manage/domain?authas=" . $u->user . "'>" . $class->ml('setting.display.domainmapping.actionlink.remove') . "</a> $upgrade_link";
    } elsif ($upgrade_url) {
        return "<a href='$upgrade_url'>" . $class->ml('setting.display.domainmapping.actionlink') . "</a> $upgrade_link";
    }

    return "";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.domainmapping.label');
}

sub option {
    my ($class, $u, $errs) = @_;

    return $u->prop("journaldomain");
}

1;
