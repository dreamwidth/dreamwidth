package LJ::Widget::SettingProdDisplay;

use strict;
use base qw(LJ::Widget);

use Apache;
use Carp qw(croak);

sub render_body {
    my $class = shift;

    my $remote = LJ::get_remote();
    return unless $remote;

    my $body;
    my $title = LJ::ejs( $class->ml('setting.prod.display.title') );
    foreach my $prod (@LJ::SETTING_PROD) {
        if (Apache->request->notes('codepath') =~ $prod->{codepaths} && $prod->{should_show}->($remote)) {
            $body .= "\n<script language='javascript'>setTimeout(\"displaySettingProd('" .
                    $prod->{setting} . "', '" . $prod->{field} . "', '" . $title . "')\", 400)</script>\n";
            last;
        }
    }

    return $body;
}

sub need_res {
    qw(js/settingprod.js
       js/ljwidget.js
       js/ljwidget_ippu.js
       js/widget_ippu/settingprod.js
       stc/widgets/settingprod.css
      )
}

1;
