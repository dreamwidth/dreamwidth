package LJ::Setting::Display::SMSHistory;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.smshistory.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return "<a href='$LJ::SITEROOT/manage/sms/status.bml'>" . $class->ml('setting.display.smshistory.option', { sms_title => $LJ::SMS_TITLE }) . "</a>";
}

1;
