package LJ::ExternalSite;
use strict;
use warnings;

my $need_rebuild = 1;
my @sites = ();
# class method.  called after ljconfig.pl is reloaded
# to know we need to reconstruct our list of external site
# instances
sub forget_site_objs {
    $need_rebuild = 1;
    @sites = ();
}

# class method.
sub sites {
    _build_site_objs() if $need_rebuild;
    return @sites;
}

# class method
sub find_matching_site {
    my ($class, $url) = @_;
    foreach my $site ($class->sites) {
        return $site if $site->matches_url($url);
    }
    return undef;
}

sub _build_site_objs {
    return unless $need_rebuild;
    $need_rebuild = 0;
    @sites = ();
    foreach my $ci (@LJ::EXTERNAL_SITES) {
        my @args = @$ci;
        my $class = shift @args;
        $class = "LJ::ExternalSite::$class" unless $class =~ /::/;
        push @sites, $class->new(@args);
    }
}


# instance method.  given a URL (or partial URL), returns
# true (in the form of a canonical URL for this user) if
# this URL is owned by this site, or returns false otherwise.
sub matches_url {
    my ($self, $url) = @_;
    return 0;
}

# class or instance method.
# 16x16 image to be shown for the LJ user head for this user.
# unless overridden, external users are just (as default), OpenID-looking users
sub icon_url {
    return "$LJ::IMGPREFIX/openid-profile.gif";
}

1;
