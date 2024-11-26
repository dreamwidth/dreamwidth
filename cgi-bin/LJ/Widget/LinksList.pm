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

package LJ::Widget::LinksList;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub authas { 1 }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    return "" unless $u->prop('stylesys') == 2;

    my $post    = $class->post_fields( $opts{post} );
    my $linkobj = LJ::Links::load_linkobj( $u, "master" );

    my $link_min   = $opts{link_min}   || 5;     # how many do they start with ?
    my $link_more  = $opts{link_more}  || 5;     # how many do they get when they click "more"
    my $order_step = $opts{order_step} || 10;    # step order numbers by

    # how many link inputs to show?
    my $showlinks = $post->{numlinks} || @$linkobj;
    my $caplinks  = $u->count_max_userlinks;
    $showlinks += $link_more if $post->{'action:morelinks'};
    $showlinks = $link_min if $showlinks < $link_min;
    $showlinks = $caplinks if $showlinks > $caplinks;

    my $vars = {
        linkobj    => $linkobj,
        caplinks   => $caplinks,
        showlinks  => $showlinks,
        order_step => $order_step
    };

    return DW::Template->template_string( 'widget/linkslist.tt', $vars );
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;
    my $u     = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    return if $post->{'action:morelinks'};    # this is handled in render_body

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    if ( $post_fields_of_parent->{reset} ) {
        foreach my $val ( keys %$post ) {
            next unless $val =~ /^link_\d+_title$/ || $val =~ /^link_\d+_url$/;

            $post->{$val} = "";
        }
    }

    my $linkobj = LJ::Links::make_linkobj_from_form( $u, $post );
    LJ::Links::save_linkobj( $u, $linkobj );

    return;
}

1;
