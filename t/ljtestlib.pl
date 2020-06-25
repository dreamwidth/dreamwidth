package LJ;

use v5.10;
use strict;
no warnings 'uninitialized';

BEGIN {
    use Test::MockObject;

    my $mock = Test::MockObject->new();

    sub fake_lang_ml {
        my ( $code, $vars ) = @_;
        my $aopts = $vars->{'aopts'};
        if ( $code eq "cleanhtml.error.markup.extra" ) {
            return "[<strong>Error:</strong> Irreparable invalid markup (".
	    "'&lt;$aopts&gt;') in entry. Owner must fix manually. Raw contents below.]";
        }
        if ( $code eq "cleanhtml.error.markup" ) {
            return "<a $aopts>Error: Irreparable invalid markup in entry. Raw contents behind the cut.</a>";
        }
    }

    sub fake_get_proxy_url {
        return "http://proxy.url";
    }

    $mock->fake_module(
        'LJ::Lang' => (
            ml => \&fake_lang_ml
        )
    );
    $mock->fake_module(
        'DW::Proxy' => (
            get_proxy_url => \&fake_get_proxy_url
        )
    );
    $mock->fake_module( 'LJ::EmbedModule' => () );

    # ugly hack to shutup dependent libraries which sometimes want to bring in
    # ljlib.pl (via require, ick!).  so this lets them know if it's recursive.
    # we REALLY need to move the rest of this crap to .pm files.

    # ensure we have $LJ::HOME, or complain very vigorously
    $LJ::HOME ||= $ENV{LJHOME};
    die "No \$LJ::HOME set, or not a directory!\n"
        unless $LJ::HOME && -d $LJ::HOME;

    use lib ( $LJ::HOME || $ENV{LJHOME} ) . "/extlib/lib/perl5";

    # Please do not change this to "LJ::Directories"
    require $LJ::HOME . "/cgi-bin/LJ/Directories.pm";
}

sub is_web_context {
    return 0;
}

sub load_user_or_identity {
    return undef;
}

sub canonical_username {
    return "system";
}

sub ljuser {
    my ( $user, $opts ) = @_;
    return
          "<span style='white-spggace: nowrap;'>"
        . "<a href='http://lj.example/userprofile'><img src='http://lj.example/img.png' alt='[alttext]' width='60' height='80'"
        . " style='vertical-align: tggext-bottom; border: 0; padding-right: 1px;' /></a>"
        . "<a href='http://lj.example/url'>$user</a></span>";
}

sub is_enabled {
    return 1;
}

sub temp_user {
    my $u = Test::MockObject->new();
    $u->mock( 'user',           sub { return 'temp'; } );
    $u->mock( 'ljuser_display', sub { return ljuser('temp'); } );
}

1;
