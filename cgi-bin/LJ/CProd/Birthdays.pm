package LJ::CProd::Birthdays;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $icon = "<div style=\"float: left; padding-right: 5px;\">
               <img border=\"1\" src=\"$LJ::SITEROOT/img/cake.jpg\" /></div>";
    my $link = $class->clickthru_link('cprod.birthday.link', $version);

    return "<p>$icon ". BML::ml($class->get_ml($version), { "user" => $user,
                                                            "link" => $link }) . "</p>";
}

sub ml { 'cprod.birthday.text' }
sub link { "$LJ::SITEROOT/birthdays.bml" }
sub button_text { "Birthdays" }

1;
