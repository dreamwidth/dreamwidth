package LJ::Widget::ExampleRenderWidget;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

#sub need_res { qw( stc/widgets/examplerenderwidget.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= "This widget just renders something.<br />";
    $ret .= "Call it with: <code>LJ::Widget::ExampleRenderWidget->render( word => 'foo' );</code><br />";
    $ret .= "The word you passed in was: $opts{word}";

    return $ret;
}

1;
