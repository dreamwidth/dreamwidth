# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Setting::SiteScheme;
use base 'LJ::Setting';
use strict;
use warnings;
use DW::SiteScheme;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "site_schemes";
}

sub label {
    my $class = shift;

    my $ret = "<a name='skin'></a>" . $class->ml('setting.sitescheme.label');

    return $ret;
}

sub option {
    my ( $class, $u, $errs, $args, %opts ) = @_;
    my $key = $class->pkgkey;

    my $r = DW::Request->get;

    my @bml_schemes = DW::SiteScheme->available;
    return "" unless @bml_schemes;

    my $show_hidden = $opts{getargs}->{view} && $opts{getargs}->{view} eq "schemes";
    my $sitescheme  = $class->get_arg( $args, "sitescheme" ) || DW::SiteScheme->current;

    my $ret;
    foreach my $scheme (@bml_schemes) {
        my $label     = $scheme->{title};
        my $value     = $scheme->{scheme};
        my $is_hidden = $scheme->{hidden} ? 1 : 0;

        next if !$show_hidden && $is_hidden && $sitescheme ne $value;

        my $scheme_alt_ml;
        $scheme_alt_ml = $scheme->{alt}
            if $scheme->{alt} && LJ::Lang::string_exists( $scheme->{alt} );
        $scheme_alt_ml ||= "siteskins.$scheme->{scheme}.alt"
            if LJ::Lang::string_exists("siteskins.$scheme->{scheme}.alt");
        my $alt = $scheme_alt_ml ? "alt='" . LJ::Lang::ml($scheme_alt_ml) . "'" : "";

        my $img = $scheme->{img} || "$scheme->{scheme}.png";
        $label .=
            qq{<img src="$LJ::IMGPREFIX/siteskins/previews/$img" $alt width="150" height="114" />};

        my $desc_ml;
        $desc_ml = $scheme->{desc} if $scheme->{desc} && LJ::Lang::string_exists( $scheme->{desc} );
        $desc_ml ||= "siteskins.$scheme->{scheme}.desc"
            if LJ::Lang::string_exists("siteskins.$scheme->{scheme}.desc");
        my $desc = $desc_ml ? LJ::Lang::ml($desc_ml) : "";
        $label .= "<p class='note'>$desc</p>" if $desc;

        $ret .= "<div class='sitescheme-item'>"
            . LJ::html_check(
            {
                type     => "radio",
                name     => "${key}sitescheme",
                id       => "${key}sitescheme_$value",
                value    => $value,
                selected => $sitescheme eq $value ? 1 : 0,
            }
            ) . "<label for='${key}sitescheme_$value' class='radiotext'>$label</label></div>";
    }

    my $errdiv = $class->errdiv( $errs, "sitescheme" );
    $ret .= "<br />$errdiv" if $errdiv;
    $ret .=
          "<p class='sitescheme-style'><a href='$LJ::SITEROOT/customize/'>"
        . $class->ml('setting.sitescheme.journal.style')
        . "</a></p>";

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "sitescheme" );

    return 1 unless $val;

    my @scheme_names;
    foreach my $scheme ( DW::SiteScheme->available ) {
        push @scheme_names, $scheme->{scheme};
    }

    $class->errors( sitescheme => $class->ml('setting.sitescheme.error.invalid') )
        unless $val && grep { $val eq $_ } @scheme_names;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $r = DW::Request->get;

    my $val = $class->get_arg( $args, "sitescheme" );
    return 1 unless $val;

    unless ( DW::SiteScheme->set_for_user( $val, $u ) ) {
        return 0;
    }
    BML::set_scheme($val);

    return 1;
}

1;
