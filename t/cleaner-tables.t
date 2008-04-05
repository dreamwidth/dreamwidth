# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'cleanhtml.pl';
use HTMLCleaner;

my $orig_post;
my $clean_post;

my $clean = sub {
    $clean_post = $orig_post;
    LJ::CleanHTML::clean_event(\$clean_post, {tablecheck => 1});
};

# VALID: standard table
$orig_post = "<table><tr><td>Cell 1</td><td>Cell 2</td></tr><tr><td>Cell 3</td><td>Cell 4</td></tr></table>";
$clean->();
ok($orig_post eq $clean_post, "Table okay if all tags are closed");

# VALID: table without closing tr/td tags
$orig_post = "<table><tr><td>Cell 1<td>Cell 2<tr><td>Cell 3<td>Cell 4</table>";
$clean->();
ok($orig_post eq $clean_post, "Table okay if td and tr tags aren't closed");

# INVALID: table without opening table tag, should escape all tags
$orig_post = "<tr><td>Cell 1</td><td>Cell 2</td></tr><tr><td>Cell 3</td><td>Cell 4</td></tr></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<td></td></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<tr></tr></table>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<td></td>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

$orig_post = "<tr></tr>";
$clean->();
ok($clean_post !~ '<t', "All tags escaped");

# INVALID: table without opening tr tags, should escape all td tags
$orig_post = "<table><td>Cell 1</td><td>Cell 2</td><td>Cell 3</td><td>Cell 4</td></table>";
$clean->();
ok($clean_post !~ '<td' && $clean_post =~ '<table', "All td tags escaped");

$orig_post = "<table><tbody><tr><td>foo</td></tr></table>";
$clean->();
ok($clean_post eq "<table><tbody><tr><td>foo</td></tr></table>"
   || $clean_post eq  "<table><tbody><tr><td>foo</td></tr></tbody></table>", "Fixed tbody -- optional");
