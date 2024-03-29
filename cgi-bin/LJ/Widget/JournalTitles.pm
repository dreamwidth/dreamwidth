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

package LJ::Widget::JournalTitles;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax     { 1 }
sub authas   { 1 }
sub need_res { qw( stc/widgets/journaltitles.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my @ids = qw( journaltitle journalsubtitle friendspagetitle friendspagesubtitle );

    my $vars = {
        u         => $u,
        help_icon => \&LJ::help_icon,
        ids       => \@ids
    };

    return DW::Template->template_string( 'widget/journaltitles.tt', $vars );
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $eff_val = LJ::text_trim( $post->{title_value}, 0, LJ::std_max_length() );
    $eff_val = "" unless $eff_val;
    $u->set_prop( $post->{which_title}, $eff_val );

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            // store current field values
            self.journaltitle_value = $("journaltitle").value;
            self.journalsubtitle_value = $("journalsubtitle").value;
            self.friendspagetitle_value = $("friendspagetitle").value;
            self.friendspagesubtitle_value = $("friendspagesubtitle").value;

            // show view mode
            $("journaltitle_view").style.display = "inline";
            $("journalsubtitle_view").style.display = "inline";
            $("friendspagetitle_view").style.display = "inline";
            $("friendspagesubtitle_view").style.display = "inline";
            $("journaltitle_cancel").style.display = "inline";
            $("journalsubtitle_cancel").style.display = "inline";
            $("friendspagetitle_cancel").style.display = "inline";
            $("friendspagesubtitle_cancel").style.display = "inline";
            $("journaltitle_modify").style.display = "none";
            $("journalsubtitle_modify").style.display = "none";
            $("friendspagetitle_modify").style.display = "none";
            $("friendspagesubtitle_modify").style.display = "none";

            // set up edit links
            DOM.addEventListener($("journaltitle_edit"), "click", function (evt) { self.editTitle(evt, "journaltitle") });
            DOM.addEventListener($("journalsubtitle_edit"), "click", function (evt) { self.editTitle(evt, "journalsubtitle") });
            DOM.addEventListener($("friendspagetitle_edit"), "click", function (evt) { self.editTitle(evt, "friendspagetitle") });
            DOM.addEventListener($("friendspagesubtitle_edit"), "click", function (evt) { self.editTitle(evt, "friendspagesubtitle") });

            // set up cancel links
            DOM.addEventListener($("journaltitle_cancel"), "click", function (evt) { self.cancelTitle(evt, "journaltitle") });
            DOM.addEventListener($("journalsubtitle_cancel"), "click", function (evt) { self.cancelTitle(evt, "journalsubtitle") });
            DOM.addEventListener($("friendspagetitle_cancel"), "click", function (evt) { self.cancelTitle(evt, "friendspagetitle") });
            DOM.addEventListener($("friendspagesubtitle_cancel"), "click", function (evt) { self.cancelTitle(evt, "friendspagesubtitle") });

            // set up save forms
            DOM.addEventListener($("journaltitle_form"), "submit", function (evt) { self.saveTitle(evt, "journaltitle") });
            DOM.addEventListener($("journalsubtitle_form"), "submit", function (evt) { self.saveTitle(evt, "journalsubtitle") });
            DOM.addEventListener($("friendspagetitle_form"), "submit", function (evt) { self.saveTitle(evt, "friendspagetitle") });
            DOM.addEventListener($("friendspagesubtitle_form"), "submit", function (evt) { self.saveTitle(evt, "friendspagesubtitle") });

        },
        editTitle: function (evt, id) {
            $(id + "_modify").style.display = "inline";
            $(id + "_view").style.display = "none";
            $(id).focus();

            // cancel any other titles that are being edited since
            // we only want one title in edit mode at a time
            if (id == "journaltitle") {
                this.cancelTitle(evt, "journalsubtitle");
                this.cancelTitle(evt, "friendspagetitle");
                this.cancelTitle(evt, "friendspagesubtitle");
            } else if (id == "journalsubtitle") {
                this.cancelTitle(evt, "journaltitle");
                this.cancelTitle(evt, "friendspagetitle");
                this.cancelTitle(evt, "friendspagesubtitle");
            } else if (id == "friendspagetitle") {
                this.cancelTitle(evt, "journaltitle");
                this.cancelTitle(evt, "journalsubtitle");
                this.cancelTitle(evt, "friendspagesubtitle");
            } else if (id == "friendspagesubtitle") {
                this.cancelTitle(evt, "journaltitle");
                this.cancelTitle(evt, "journalsubtitle");
                this.cancelTitle(evt, "friendspagetitle");
            }


            Event.stop(evt);
        },
        cancelTitle: function (evt, id) {
            $(id + "_modify").style.display = "none";
            $(id + "_view").style.display = "inline";

            // reset appropriate field to default
            if (id == "journaltitle") {
                $("journaltitle").value = this.journaltitle_value;
            } else if (id == "journalsubtitle") {
                $("journalsubtitle").value = this.journalsubtitle_value;
            } else if (id == "friendspagetitle") {
                $("friendspagetitle").value = this.friendspagetitle_value;
            } else if (id == "friendspagesubtitle") {
                $("friendspagesubtitle").value = this.friendspagesubtitle_value;
            } 

            Event.stop(evt);
        },
        saveTitle: function (evt, id) {
            $("save_btn_" + id).disabled = true;

            this.doPostAndUpdateContent({
                which_title: id,
                title_value: $(id).value
            });

            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
