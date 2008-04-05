# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'cleanhtml.pl';
use HTMLCleaner;

my $lju_sys = LJ::ljuser("system");

my $all = sub {
    my $raw = shift;
    LJ::CleanHTML::clean_subject_all(\$raw);
    return $raw;
};

is($all->("<span class='ljuser' lj:user='burr86' style='white-space: nowrap;'><a href=''><img src='http://www.henry.lj/img/userinfo.gif' alt='[info]' width='17' height='17' style='vertical-align: bottom; border: 0;' /></a><a href='http://www.henry.lj/userinfo.bml?user=burr86'><b>burr86</b></a></span> kicks butt"),
   "burr86 kicks butt",
   "only text");

is($all->("This is a <b>test</b>"),
   "This is a test",
   "only text");


