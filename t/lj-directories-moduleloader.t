# t/lj-directories-moduleloader.t
#
# Test standalone directory lookup, module loading, and temporary directory cleanup.
#
# Authors:
#      Alex Southwell <saphid@gmail.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

sub write_fixture {
    my ( $path, $content ) = @_;
    open my $file, '>', $path or die "Cannot open $path: $!";
    print {$file} $content or die "Cannot write $path: $!";
    close $file or die "Cannot close $path: $!";
}

my ( $checkout_home, $home, $override, $site );

BEGIN {
    $checkout_home = $ENV{LJHOME};
    $home          = abs_path( tempdir( TMPDIR => 1, CLEANUP => 1 ) );
    $override      = "$home/ext/override";
    $site          = "$home/ext/site";
    make_path( "$home/cgi-bin", "$override/cgi-bin", $site );
    write_fixture( "$override/.dir_scope", "private\n" );
    write_fixture( "$site/.dir_scope",     "local\n" );
    $ENV{LJHOME} = $home;
}

use LJ::Directories;
BEGIN { $ENV{LJHOME} = $checkout_home; }

use LJ::ModuleLoader qw(module_subclasses);
use LJ::TempDir;

subtest 'directory scopes and entry types' => sub {
    local $LJ::HOME = $home;
    my $name = 'standalone-entry';
    write_fixture( "$home/$name",     'core' );
    write_fixture( "$override/$name", 'private' );
    make_path("$site/$name");

    is_deeply(
        [ LJ::get_all_paths($name) ],
        [ "$override/$name", "$site/$name", "$home/$name" ],
        'scope order includes both entry types'
    );
    is_deeply(
        [ LJ::get_all_paths( $name, home_first => 1 ) ],
        [ "$home/$name", "$override/$name", "$site/$name" ],
        'home first does not duplicate home'
    );
    is_deeply(
        [ LJ::get_all_files($name) ],
        [ "$override/$name", "$home/$name" ],
        'file lookup excludes directories'
    );
    is_deeply( [ LJ::get_all_directories($name) ],
        ["$site/$name"], 'directory lookup excludes files' );
    is( LJ::resolve_file($name), "$override/$name", 'file resolution takes the highest scope' );
    is( LJ::resolve_file( $name, home_first => 1 ), "$home/$name",
        'home first changes resolution' );
    is( LJ::resolve_directory($name),
        "$site/$name", 'directory resolution skips higher-scope files' );
    is_deeply( [ LJ::get_all_paths('missing') ], [], 'nonexistent entries are not listed' );
    is( LJ::resolve_file('missing'),      undef, 'missing file does not resolve' );
    is( LJ::resolve_directory('missing'), undef, 'missing directory does not resolve' );
};

subtest 'subclass discovery and eager loading' => sub {
    my $base         = 'StandaloneLoaderFixture::Eager';
    my $core_dir     = "$home/cgi-bin/StandaloneLoaderFixture/Eager";
    my $override_dir = "$override/cgi-bin/StandaloneLoaderFixture/Eager";
    make_path( "$core_dir/Nested", "$core_dir/.hidden", $override_dir );
    write_fixture( "$core_dir/Top.pm", "package ${base}::Top; sub marker { 'top' } 1;\n" );
    write_fixture( "$core_dir/Nested/Deep.pm",
        "package ${base}::Nested::Deep; sub marker { 'nested' } 1;\n" );
    write_fixture( "$override_dir/Extra.pm",
        "package ${base}::Extra; sub marker { 'extension' } 1;\n" );
    write_fixture( "$core_dir/.Hidden.pm",        "die 'hidden file was loaded';\n" );
    write_fixture( "$core_dir/.hidden/Hidden.pm", "die 'hidden directory was searched';\n" );
    write_fixture( "$core_dir/Notes.txt",         "die 'non-module file was loaded';\n" );

    is_deeply(
        [ sort( module_subclasses($base) ) ],
        [ "${base}::Extra", "${base}::Nested::Deep", "${base}::Top" ],
        'discovery walks roots and nested namespaces but ignores hidden and non-module entries'
    );
    is_deeply( [ LJ::ModuleLoader->module_subclasses('StandaloneLoaderFixture::Missing') ],
        [], 'unknown namespace has no subclasses' );

    LJ::ModuleLoader->require_subclasses($base);
    is( "${base}::Top"->marker,          'top',       'root module is usable' );
    is( "${base}::Nested::Deep"->marker, 'nested',    'nested module is usable' );
    is( "${base}::Extra"->marker,        'extension', 'extension module is usable' );

    my $broken_dir = "$home/cgi-bin/StandaloneLoaderFixture/Broken";
    make_path($broken_dir);
    write_fixture( "$broken_dir/Invalid.pm", "die 'fixture load failed';\n" );
    eval { LJ::ModuleLoader->require_subclasses('StandaloneLoaderFixture::Broken'); };
    like(
        $@,
        qr/Error loading StandaloneLoaderFixture::Broken::Invalid: .*fixture load failed/s,
        'a failed subclass load identifies the module and preserves the underlying error'
    );
};

subtest 'subclass autoloading' => sub {
    my $dir = "$home/cgi-bin/StandaloneLoaderFixture/Lazy";
    make_path($dir);
    write_fixture( "$dir/Deferred.pm",
        "package StandaloneLoaderFixture::Lazy::Deferred; sub marker { 'deferred' } 1;\n" );

    LJ::ModuleLoader->autouse_subclasses('StandaloneLoaderFixture::Lazy');
    is( StandaloneLoaderFixture::Lazy::Deferred->marker,
        'deferred', 'an autoloaded subclass is callable without an explicit use' );
};

subtest 'optional library loading' => sub {
    local $LJ::HOME = $home;
    write_fixture( "$home/cgi-bin/standalone-relative.pl", "'relative';\n" );
    write_fixture( "$home/standalone-absolute.pl",         "'absolute';\n" );
    write_fixture( "$home/cgi-bin/standalone-broken.pl",   "die 'optional fixture failed';\n" );

    is( LJ::ModuleLoader->require_if_exists('standalone-relative.pl'),
        'relative', 'bare filenames resolve under the home cgi-bin' );
    is( LJ::ModuleLoader->require_if_exists("$home/standalone-absolute.pl"),
        'absolute', 'absolute paths are used as given' );
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    is( LJ::ModuleLoader->require_if_exists('standalone-missing.pl'),
        0, 'missing libraries return false' );
    is_deeply( \@warnings, [], 'missing libraries do not warn' );
    is( LJ::ModuleLoader->require_if_exists('standalone-broken.pl'),
        undef, 'an existing but broken library yields no value' );
    like( join( '', @warnings ), qr/optional fixture failed/, 'the evaluation error is reported' );
};

subtest 'temporary directory lifetime' => sub {
    my $scalar_dir;
    {
        my $temp = LJ::TempDir->new;
        $scalar_dir = $temp->directory;
        ok( -d $scalar_dir, 'scalar constructor gives an object with an existing directory' );
        make_path("$scalar_dir/nested");
        write_fixture( "$scalar_dir/nested/content", 'temporary data' );
    }
    ok( !-e $scalar_dir, 'leaving scope removes the directory and its nested contents' );

    my ( $list_dir, $temp ) = LJ::TempDir->new;
    is( $list_dir, $temp->directory,
        'list constructor returns the owned directory and its object' );
    ok( -d $list_dir, 'list-context directory exists while the object is held' );
    undef $temp;
    ok( !-e $list_dir, 'retaining only the path does not prevent cleanup' );
};

my @bootstrap = grep { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC );
is_deeply( \@bootstrap, [], 'the application bootstrap was not loaded' );

done_testing();
