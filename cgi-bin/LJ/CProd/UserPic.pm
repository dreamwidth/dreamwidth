package LJ::CProd::UserPic;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->{defaultpicid};
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    $ml_key = $class->get_ml($version);
    my $link = $class->clickthru_link('cprod.userpic.link', $version);
    my $user = LJ::ljuser($u);
    my $empty = '<div style="overflow: hidden; padding: 5px; width: 100px;
height: 100px; border: 1px solid #000000;">&nbsp;</div>';

    return BML::ml($ml_key, { "user" => $user,
                                          "link" => $link,
                                          "empty" => $empty });
}

sub ml { 'cprod.userpic.text' }
sub link { "$LJ::SITEROOT/editpics.bml" }
sub button_text { "Userpic" }

1;
