package DW::Controller::Test::WidgetFoundation;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use LJ::Customize;

# This route exists only in dev instances for the browser resource-order fixture.
if ($LJ::IS_DEV_SERVER) {
    DW::Routing->register_string( '/__test/widget-foundation', \&handler, app => 1 );
}

sub handler {
    my ( $ok, $rv ) = controller( anonymous => 0 );
    return $rv unless $ok;

    LJ::set_active_resource_group('foundation');
    LJ::need_res( { group => 'foundation' },
        qw(js/customize.js js/6alib/hourglass.js js/6alib/datasource.js) );

    my $u = $rv->{remote};
    $u->set_prop( stylesys => 2 ) unless $u->prop('stylesys') == 2;
    LJ::Customize->verify_and_load_style($u);
    LJ::Customize->migrate_current_style($u);

    my $headextra = '';
    my $body      = '';

    my $current_theme = LJ::Widget::CurrentTheme->new;
    $headextra .= $current_theme->wrapped_js( page_js_obj => 'Customize' );
    $body      .= $current_theme->render;

    my $journal_titles = LJ::Widget::JournalTitles->new;
    $headextra .= $journal_titles->wrapped_js;
    $body      .= $journal_titles->render;

    my $theme_nav = LJ::Widget::ThemeNav->new;
    $headextra .= $theme_nav->wrapped_js( page_js_obj => 'Customize' );
    $body      .= $theme_nav->render( headextra => \$headextra );

    $rv->{headextra} = $headextra;
    $rv->{body}      = $body;
    return DW::Template->render_template( 'test/widget-foundation.tt', $rv );
}

1;
