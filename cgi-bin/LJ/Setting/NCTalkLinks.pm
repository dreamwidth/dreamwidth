package LJ::Setting::NCTalkLinks;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;

sub tags { qw(nc comment links counts count) }

sub label {
    local $BML::ML_SCOPE = "/editinfo.bml";
    return $BML::ML{'.numcomments.header'};
}

sub des {
    local $BML::ML_SCOPE = "/editinfo.bml";
    return $BML::ML{'.numcomments.about'};
}

sub prop_name { "opt_nctalklinks" }
sub checked_value { 1 }
sub unchecked_value { 0 }

1;



