use strict;
use warnings;

use Test::More;
use Test::Code::TidyAll 0.20;

tidyall_ok( no_cache => 1, verbose => 1 );
