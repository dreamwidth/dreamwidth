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

package LJ::Widget::MoodThemeChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub ajax          { 1 }
sub authas        { 1 }
sub need_res      { qw( stc/widgets/moodthemechooser.css ) }
sub need_res_opts { priority => $LJ::OLD_RES_PRIORITY }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";

    my $preview_moodthemeid =
        defined $opts{preview_moodthemeid} ? $opts{preview_moodthemeid} : $u->moodtheme;
    my $forcemoodtheme =
        defined $opts{forcemoodtheme} ? $opts{forcemoodtheme} : $u->{opt_forcemoodtheme} eq 'Y';

    my @themes = LJ::Customize->get_moodtheme_select_list($u);
    my @theme_dropdown =
        map { { value => $_->{moodthemeid}, text => $_->{name}, disabled => $_->{disabled} } }
        @themes;

    my $journalarg = $getextra ? "?journal=" . $u->user : "";
    my $mobj       = DW::Mood->new($preview_moodthemeid);
    my @show_moods = qw( happy sad angry tired );

    my $vars = {
        forcemoodtheme      => $forcemoodtheme,
        theme_dropdown      => \@theme_dropdown,
        journalarg          => $journalarg,
        preview_moodthemeid => $preview_moodthemeid,
        getextra            => $getextra,
        mobj                => $mobj
    };

    if ($mobj) {
        my $mood_des = $mobj->des;
        LJ::CleanHTML::clean( \$mood_des );
        my @cleaned_moods;
        foreach my $mood (@show_moods) {
            my %pic;
            if ( $mobj->get_picture( $mobj->mood_id($mood), \%pic ) ) {
                my $clean_mood = {
                    mood => $mood,
                    pic  => \%pic
                };
                push @cleaned_moods, $clean_mood;
            }
        }
        $vars->{mood_des}      = $mood_des;
        $vars->{cleaned_moods} = \@cleaned_moods;
    }

    return DW::Template->template_string( 'widget/moodthemechooser.tt', $vars );
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ( $given_moodthemeid, $given_forcemoodtheme );
    if ( $post_fields_of_parent->{reset} ) {
        $given_moodthemeid    = 1;
        $given_forcemoodtheme = 0;
    }
    else {
        $given_moodthemeid    = $post->{moodthemeid};
        $given_forcemoodtheme = $post->{opt_forcemoodtheme};
    }

    my %update;
    my $moodthemeid = LJ::Customize->validate_moodthemeid( $u, $given_moodthemeid );
    $update{moodthemeid}        = $moodthemeid;
    $update{opt_forcemoodtheme} = $given_forcemoodtheme ? "Y" : "N";

    # update 'user' table
    foreach ( keys %update ) {
        delete $update{$_} if $u->{$_} eq $update{$_};
    }
    $u->update_self( \%update ) if %update;

    # reload the user object to force the display of these changes
    $u = LJ::load_user( $u->user, 'force' );

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            DOM.addEventListener($('moodtheme_dropdown'), "change", function (evt) { self.previewMoodTheme(evt) });
        },
        previewMoodTheme: function (evt) {
            var opt_forcemoodtheme = 0;
            if ($('opt_forcemoodtheme').checked) opt_forcemoodtheme = 1;

            this.updateContent({
                preview_moodthemeid: $('moodtheme_dropdown').value,
                forcemoodtheme: opt_forcemoodtheme
            });
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
