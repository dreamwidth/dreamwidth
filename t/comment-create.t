use strict;
use Test::More tests => 6;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Test qw( temp_user );
use LJ::Comment;

my $ju = temp_user();
my $pu = temp_user();

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => undef,
        poster => undef,
    );

    ok( ! $c, "No comment created: invalid journal" );
    is( $err_ref->{code}, "bad_journal" );
}

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => $ju,
        poster => undef,
    );

    ok( ! $c, "No comment created: invalid poster" );
    is( $err_ref->{code}, "bad_poster" );
}

{
    my $err_ref;
    my $c = LJ::Comment->create(
        err_ref => \$err_ref,

        journal => $ju,
        poster => $pu,

        extra_args => undef
    );

    ok( ! $c, "No comment created: invalid args" );
    is( $err_ref->{code}, "bad_args" );
}
