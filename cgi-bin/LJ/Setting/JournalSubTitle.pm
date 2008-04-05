package LJ::Setting::JournalSubTitle;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(journal heading title name subtitle) }
sub max_chars { 80 }

sub prop_name { "journalsubtitle" }
sub text_size { 40 }
sub question { "Journal Subtitle" }

1;

