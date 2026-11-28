#!/usr/bin/perl
#
# t/template-filters-rules.t
#
# Test JavaScript and date filters, country code mappings, and business rule
# overrides without loading ljlib.pl. Test translation debug output in a
# separate process with the web request dependencies loaded.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use HTTP::Date ();
use Test::More;

my ( $checkout_home, $rules_dir );

BEGIN {
    $checkout_home = $ENV{LJHOME};
    my $fixture_home = tempdir( TMPDIR => 1, CLEANUP => 1 );
    $rules_dir = "$fixture_home/cgi-bin/DW/BusinessRules/TemplateFiltersTest";
    make_path( "$fixture_home/ext", $rules_dir );
    $ENV{LJHOME} = $fixture_home;
}

use LJ::Directories;
BEGIN { $ENV{LJHOME} = $checkout_home; }

use DW::BusinessRules;
use DW::Countries;
use DW::Template::Filters;
use LJ::TextUtil;
use LJ::Time;

subtest 'translation debug output uses the current request scope' => sub {
    open my $output, '-|', $^X, '-e', <<'PERL' or die "Cannot start translation test: $!";
use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use HTTP::Request;
use DW::Request;
use DW::Request::Standard;
use DW::Template::Filters;
use LJ::Lang;

my $filter = DW::Template::Filters::ml();
DW::Request->reset;
my $request = DW::Request::Standard->new( HTTP::Request->new( GET => '/first?uselang=debug' ) );
$request->note( ml_scope => '/first.tt' );
print $filter->('.title'), "\n";
print $filter->('/shared.tt.title'), "\n";

DW::Request->reset;
$request = DW::Request::Standard->new( HTTP::Request->new( GET => '/second?uselang=debug' ) );
print $filter->('.title'), "\n";
$request->note( ml_scope => '/second.tt' );
print $filter->('.title'), "\n";
PERL

    chomp( my @codes = <$output> );
    ok( close $output, 'translation process exits successfully' ) or return;
    is( $codes[0], '/first.tt.title',  'relative code uses the first template scope' );
    is( $codes[1], '/shared.tt.title', 'absolute code stays absolute' );
    is( $codes[2], '.title', 'relative code stays unqualified when the new request has no scope' );
    is( $codes[3], '/second.tt.title', 'reused filter does not retain the old scope' );
};

subtest 'JavaScript strings and HTTP dates' => sub {
    my $filter = DW::Template::Filters::js();
    is(
        $filter->("say \"hi\"\r\nnext"),
        q{"say \"hi\"\nnext"},
        'quotes and CRLF stay in one literal'
    );
    is( $filter->('</script>'), q{"</scri" + "pt>"}, 'closing script tag cannot end the script' );
    is( $filter->(undef), q{""}, 'missing value becomes an empty string literal' );

    is(
        DW::Template::Filters::time_to_http(0),
        'Thu, 01 Jan 1970 00:00:00 GMT',
        'zero is the epoch, not the current time'
    );
    is(
        DW::Template::Filters::time_to_http(784111777),
        'Sun, 06 Nov 1994 08:49:37 GMT',
        'timestamp becomes an HTTP date in GMT'
    );
};

subtest 'active country codes and legacy aliases' => sub {
    my %countries = ( ZZ => 'stale' );
    DW::Countries->load( \%countries );
    is( $countries{JP}, 'Japan', 'active alpha-2 code resolves to its country' );
    ok( exists $countries{GB},  'the canonical code for the United Kingdom is present' );
    ok( !exists $countries{ZZ}, 'loading replaces stale entries' );
    is_deeply( [ grep { !/\A[A-Z]{2}\z/ || !length( $countries{$_} // '' ) } keys %countries ],
        [], 'all active codes are uppercase alpha-2 with nonempty names' );
    ok( !exists $countries{UK}, 'legacy alpha-2 alias is not an active code' );

    my %active = %countries;
    DW::Countries->load_legacy( \%countries );
    is_deeply(
        \%countries,
        { %active, UK => $active{GB}, LJSC => $active{GB} },
        'legacy load retains canonical names and supplies both historical aliases'
    );

    DW::Countries->load( \%countries );
    is_deeply( \%countries, \%active, 'an active-only reload removes legacy aliases' );
};

{

    package DW::BusinessRules::TemplateFiltersTest;

    sub limit        { 10 }
    sub default_only { 5 }
}

sub write_rules {
    my ( $name, $rules ) = @_;
    open my $file, '>', "$rules_dir/$name.pm" or die "Cannot open $name.pm: $!";
    print {$file} "package DW::BusinessRules::TemplateFiltersTest::$name;\n$rules\n1;\n"
        or die "Cannot write $name.pm: $!";
    close $file or die "Cannot close $name.pm: $!";
}

subtest 'site rules replace only requested defaults and reject conflicts' => sub {
    my $rule_package = 'DW::BusinessRules::TemplateFiltersTest';
    write_rules( 'Site', <<'RULES' );
sub limit { $_[0] * 2 }
sub site_only { 20 }
sub unrequested { 99 }
RULES

    DW::BusinessRules::install_overrides( $rule_package, qw(limit default_only site_only) );
    is( DW::BusinessRules::TemplateFiltersTest::limit(7), 14, 'site rule receives caller input' );
    is( DW::BusinessRules::TemplateFiltersTest::default_only(), 5,
        'unmatched default is retained' );
    is( DW::BusinessRules::TemplateFiltersTest::site_only(), 20,
        'requested new rule is installed' );
    ok( !$rule_package->can('unrequested'), 'unrequested rule is not installed' );

    write_rules( 'OtherSite', 'sub limit { 30 }' );
    eval { DW::BusinessRules::install_overrides( $rule_package, 'limit' ); };
    like(
        $@,
        qr/limit defined in both .*::(?:OtherSite and .*::Site|Site and .*::OtherSite)/,
        'two providers of the same rule are rejected regardless of discovery order'
    );

    eval { DW::BusinessRules::install_overrides( 'Unrelated::Rules', 'limit' ); };
    like( $@, qr/Unrelated::Rules not a descendent/, 'an unrelated rule package is rejected' );
};

ok( !grep( { defined && m{(?:^|/)ljlib[.]pl\z} } keys %INC, values %INC ),
    'ljlib.pl was not loaded' );

done_testing();
