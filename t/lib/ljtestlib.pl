package LJ;

use v5.10;
use strict;
no warnings 'uninitialized';

BEGIN {
    # ugly hack to shutup dependent libraries which sometimes want to bring in
    # ljlib.pl (via require, ick!).  so this lets them know if it's recursive.
    # we REALLY need to move the rest of this crap to .pm files.

    # ensure we have $LJ::HOME, or complain very vigorously
    $LJ::HOME ||= $ENV{LJHOME};
    die "No \$LJ::HOME set, or not a directory!\n"
        unless $LJ::HOME && -d $LJ::HOME;

    # Please do not change this to "LJ::Directories"
    require $LJ::HOME . "/cgi-bin/LJ/Directories.pm";
}

use Test::MockObject;
my $mock = Test::MockObject->new();

# Fake some context functions from ljlib.pl

sub is_enabled {
    return 1;
}

sub is_web_context {
    return 0;
}

# Fake user object support

sub load_user_or_identity {
    return undef;
}

sub canonical_username {
    my ($user) = @_;
    return $user;
}

sub ljuser {
    my ( $user, $opts ) = @_;
    return
          "<span style='white-space: nowrap;'>"
        . "<a href='http://lj.example/userprofile'><img src='http://lj.example/img.png' alt='[alttext]' width='60' height='80'"
        . " style='vertical-align: text-bottom; border: 0; padding-right: 1px;' /></a>"
        . "<a href='http://lj.example/url'>$user</a></span>";
}

sub fake_external_user {
    my ( $user, $site ) = @_;
    my $u = Test::MockObject->new();
    $u->mock( 'user',           sub { return $user; } );
    $u->mock( 'site',           sub { return $site; } );
    $u->mock( 'ljuser_display', sub { return ljuser($user); } );
    return $u;
}

$mock->fake_module(
    'DW::External::User' => (
        new => \&fake_external_user
    )
);

# TODO: These two fake modules are here because several HTMLCleaner tests
# require them. Consider moving them to their own file once ljtestlib is
# used for other tests.

$mock->fake_module( 'LJ::EmbedModule' => () );

sub fake_get_proxy_url {
    return "http://proxy.url";
}

$mock->fake_module(
    'DW::Proxy' => (
        get_proxy_url => \&fake_get_proxy_url
    )
);

# Mock objects that are used as test helpers, not overriding LJ::foo functions

package LJ::Mock;

sub temp_user {
    my $u = Test::MockObject->new();
    $u->mock( 'user',           sub { return 'temp'; } );
    $u->mock( 'ljuser_display', sub { return LJ::ljuser('temp'); } );
    return $u;
}

1;
