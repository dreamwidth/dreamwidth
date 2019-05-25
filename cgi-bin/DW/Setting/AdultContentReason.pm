package DW::Setting::AdultContentReason;
use base 'LJ::Setting';
use strict;
use warnings;
use LJ::Global::Constants;

sub should_render {
    my ( $class, $u ) = @_;

    return !LJ::is_enabled('adult_content') || !$u || $u->is_identity ? 0 : 1;
}

sub label {
    return $_[0]->ml('setting.adultcontentreason.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    $ret .= LJ::html_text(
        {
            name      => "${key}reason",
            id        => "${key}reason",
            class     => "text",
            value     => $errs ? $class->get_arg( $args, "reason" ) : $u->adult_content_reason,
            size      => 60,
            maxlength => 255,
        }
    );

    my $errdiv = $class->errdiv( $errs, "reason" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $txt = $class->get_arg( $args, "reason" ) || '';
    $txt = LJ::text_trim( $txt, 0, 255 );
    $u->set_prop( "adult_content_reason", $txt );
    return 1;
}

1;
