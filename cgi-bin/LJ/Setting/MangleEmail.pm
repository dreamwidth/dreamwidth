package LJ::Setting::MangleEmail;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;

sub tags { qw(email hide obscure mangle spam) }

sub label {
    local $BML::ML_SCOPE = "/editinfo.bml";
    return $BML::ML{'.mangleaddress.header'};
}

sub des {
    local $BML::ML_SCOPE = "/editinfo.bml";
    return $BML::ML{'.mangleaddress.about'};
}

sub user_field { "opt_mangleemail" }
sub checked_value { "Y" }
sub unchecked_value { "N" }

1;



