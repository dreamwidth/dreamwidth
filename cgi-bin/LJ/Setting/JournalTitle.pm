package LJ::Setting::JournalTitle;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(journal name title heading) }
sub max_chars { 80 }

sub prop_name { "journaltitle" }
sub text_size { 40 }
sub question { "Journal Title" }

1;

