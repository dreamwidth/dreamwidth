# t/comment-create.t
#
# Test LJ::Comment creation.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use LJ::Comment;

my $ju = temp_user();
my $pu = temp_user();

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => undef,
        poster  => undef,
    );

    ok( !$c, "No comment created: invalid journal" );
    is( $err_ref->{code}, "bad_journal" );
}

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => $ju,
        poster  => undef,
    );

    ok( !$c, "No comment created: invalid poster" );
    is( $err_ref->{code}, "bad_poster" );
}

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => $ju,
        poster  => $pu,

        extra_args => undef
    );

    ok( !$c, "No comment created: invalid args" );
    is( $err_ref->{code}, "bad_args" );
}
