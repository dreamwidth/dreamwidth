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

package LJ::Widget::ExampleAjaxWidget;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax { 1 }

#sub need_res { qw( stc/widgets/examplepostwidget.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $ret;
    my $submitted = $opts{submitted} ? 1 : 0;

    $ret .= "This widget does an AJAX POST.<br />";
    $ret .= "Render it with: <code>LJ::Widget::ExampleAjaxWidget->render;</code>";
    $ret .= $class->start_form( id => "ajax_form" );
    $ret .= "<p>Type in a word: " . $class->html_text( name => "text", size => 10 ) . " ";
    $ret .= $class->html_submit( button => "Click me!" ) . "</p>";
    $ret .= $class->end_form;

    if ($submitted) {
        $ret .= "Submitted!";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    if ( $post->{text} ) {
        warn "You entered: $post->{text}\n";
    }

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            DOM.addEventListener($("ajax_form"), "submit", function (evt) { self.warnWord(evt, $("ajax_form")) });
        },
        warnWord: function (evt, form) {
            var given_text = form["Widget[ExampleAjaxWidget]_text"].value + "";

            this.doPostAndUpdateContent({
                text: given_text,
                submitted: 1
            });

            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
