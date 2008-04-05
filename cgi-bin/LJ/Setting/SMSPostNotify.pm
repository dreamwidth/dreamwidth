package LJ::Setting::SMSPostNotify;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;
no warnings 'redefine';

sub tags { qw(sms post notify notification) }

sub label {
    return "Subscribe to SMS posts";
}

sub des {
    return "When posting with SMS, automatically subscribe to comments via SMS";
}

sub is_selected {
    my ($class, $u) = @_;
    return $u->prop('sms_post_notify');
}

sub prop_name { "sms_post_notify" }
sub checked_value { "SMS" }
sub unchecked_value { "N" }

1;
