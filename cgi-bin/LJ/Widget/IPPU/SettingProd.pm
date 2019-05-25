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

package LJ::Widget::IPPU::SettingProd;

use strict;
use base qw(LJ::Widget::IPPU);
use Carp qw(croak);
use LJ::JSUtil;
use LJ::Setting;
use LJ::User;

sub authas { 0 }

sub render_body {
    my ( $class, %opts ) = @_;

    my $key = $opts{setting};
    my $body;
    my $remote        = LJ::get_remote;
    my $setting_class = "LJ::Setting::$key";

    $body .= "<div class='settingprod'>";
    $body .= "<p>"
        . $class->ml( 'settings.settingprod.intro', { sitename => $LJ::SITENAMESHORT } ) . "</p>";

    $body .= $class->start_form( id => 'settingprod_form', );

    $body .= "<div class='warningbar'>";
    $body .= $setting_class->as_html( $remote, undef, { helper => 0, faq => 1 } );

    $body .= "<p>" . $class->html_submit( $class->ml('settings.settingprod.update') ) . "</p>";
    $body .= $class->html_hidden( { name => 'setting_key', value => $key } );
    $body .= "</div>";

    $body .= $class->end_form;

    $body .= "<p><span class='helper'>"
        . $class->ml( 'settings.settingprod.outro',
        { aopts => "href='$LJ::SITEROOT/manage/profile/'" } )
        . "</span></p>";

    my $ret;
    LJ::Hooks::run_hooks( 'campaign_tracking', \$ret, { cname => 'Popup Setting Display' } );
    $body .= $ret;

    $body .= "</div>\n";

    return $body;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    my $setting       = $post->{setting};
    my $setting_class = "LJ::Setting::$setting";

    my $remote = LJ::get_remote;
    my $sv     = eval { $setting_class->save( $remote, $post ) };
    my $save_errors;
    if ( my $err = $@ ) {
        $save_errors = $err->field('map') if ref $err;
        die join( " <br />", map { $save_errors->{$_} } sort keys %$save_errors );
    }

    my $xtra;
    my $postvars = join( ",", $setting_class->settings($post) );
    LJ::Hooks::run_hooks(
        'campaign_tracking',
        \$xtra,
        {
            cname     => 'Popup Setting Submitted',
            trackvars => "$postvars",
        }
    );

    return ( success => 1, extra => "$xtra" );
}

1;
