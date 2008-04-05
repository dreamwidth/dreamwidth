package LJ::Setting::FriendsPageTitle;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(friends friend title heading) }
sub max_chars { 80 }

sub prop_name { "friendspagetitle" }
sub text_size { 40 }
sub question { "Friends Page Title" }

1;

