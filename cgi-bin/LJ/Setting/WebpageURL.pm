package LJ::Setting::WebpageURL;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(webpage homepage url) }

sub prop_name { "url" }
sub text_size { 40 }
sub question  { "Webpage URL:" }

1;



