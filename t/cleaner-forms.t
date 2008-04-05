# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'cleanhtml.pl';
use HTMLCleaner;

my $post;
my $clean = sub {
    LJ::CleanHTML::clean_event(\$post);
};

# plain form
$post = "<form><input name='foo' value='plain'></form>";
$clean->();
ok($post =~ /<input/, "has input");

# password input
$post = "<form><input name='foo' type='password'></form>";
$clean->();
ok($post !~ /password/, "can't do password element");

$post = "<form><input name='foo' type='PASSWORD'></form>";
$clean->();
ok($post !~ /PASSWORD/, "can't do password element in uppercase");

# other types
$post = "<form><input name='foo' type='foobar'></form>";
$clean->();
ok($post =~ /foobar/, "can do foobar type");

# bad types
$post = "<form><input name='foo' type='some space'></form>";
$clean->();
ok($post !~ /some space/, "can't do spaces in input type");

# password input
$post = "raw: <input name='foo' type='this_is_raw'> end";
$clean->();
ok($post !~ /this_is_raw/, "can't do bare input");



