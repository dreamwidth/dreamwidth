package LJ::Widget::StyleAlwaysMine;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/controlstrip-local.css ) }

sub authas { 1 }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{u};
    return "" unless LJ::isu($u);

    my $ret;

    if ($u->can_use_stylealwaysmine) {
        $ret .= $class->start_form( action => "$LJ::SITEROOT/tools/setstylemine.bml",
                                    name => "setstyle_form");
        if ($u->opt_stylealwaysmine) {
            $ret .= $class->html_hidden( feature => 'off', user => $u->user );
            $ret .= "<a href='' onclick='document.setstyle_form.submit();return false;'>" .
                    $class->ml("web.controlstrip.links.styleorigstyle") .
                    "</a>";
        } else {
            $ret .= $class->html_hidden( feature => 'on', user => $u->user );
            $ret .= "<a href='' onclick='document.setstyle_form.submit();return false;'>" .
                    $class->ml("web.controlstrip.links.stylemystyle") .
                    "</a>";
        }
        $ret .= $class->end_form;
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = LJ::load_user($post->{user});
    die "Invalid user." unless $u;

    $opts{returnto} = $post->{returnto} if $post->{returnto};

    if ($post->{feature} eq 'on') {
        $u->set_prop('opt_stylealwaysmine', 'Y');
    } elsif ($post->{feature} eq 'off') {
        $u->set_prop('opt_stylealwaysmine', 'N');
    }

    return;
}

1;
