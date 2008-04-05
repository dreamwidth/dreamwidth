package LJ::CProd::ControlStrip;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 unless (!defined $u->prop("view_control_strip") || $u->prop("view_control_strip") eq '');
    return 0 unless (!defined $u->prop("show_control_strip") || $u->prop("show_control_strip") eq '');

    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.controlstrip.link', $version);

    return "<p>".BML::ml($class->get_ml($version), { "link" => $link }) . "</p>";

}

sub ml { 'cprod.controlstrip.text' }
sub link { "$LJ::SITEROOT/manage/settings/" }
sub button_text { "Navigation strip" }

1;
