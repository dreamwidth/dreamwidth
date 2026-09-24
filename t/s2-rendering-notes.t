#!/usr/bin/perl
# Native request-note contracts for S2 rendering helpers.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';
use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::S2;

sub request {
    my ($journalid) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    my $r = DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        }
    );
    $r->note( journalid => $journalid ) if defined $journalid;
    return $r;
}
{

    package S2RenderingNotes::Journal;
    sub new { bless { id => $_[1], timezone => $_[2] }, $_[0] }
    sub id       { $_[0]{id} }
    sub timezone { $_[0]{timezone} }

    package S2RenderingNotes::Date;
    sub new { bless {}, shift }
    sub year        { 2026 }
    sub month       { 9 }
    sub day         { 22 }
    sub hour        { 7 }
    sub minute      { 8 }
    sub second      { 9 }
    sub day_of_week { 1 }

    package S2RenderingNotes::Apache;
    sub status       { }
    sub content_type { }
}

subtest 'cleaner expands embeds only for the current request journal' => sub {
    my %journal = (
        A => S2RenderingNotes::Journal->new( 'A', 0 ),
        B => S2RenderingNotes::Journal->new( 'B', 0 )
    );
    my @expanded;
    my $run = sub {
        my ($id) = @_;
        request($id) if defined $id;
        DW::Request->reset unless defined $id;
        my $safe;
        my $out = '';
        local $LJ::S2::ret_ref = \$out;
        local *LJ::load_userid = sub { $journal{ $_[0] } };
        local *LJ::EmbedModule::expand_entry =
            sub { push @expanded, $_[1]->id; ${ $_[2] } = "expanded:" . $_[1]->id };
        local *S2::set_output      = sub { };
        local *S2::set_output_safe = sub { $safe = $_[0] };
        local *S2::function_exists = sub { 1 };
        local *S2::run_code        = sub { $safe->('<lj-embed id="x"></lj-embed>') };
        local *S2::check_depth     = sub { };
        my $ctx = [];
        $ctx->[S2::SCRATCH] = {};
        ok( LJ::S2::s2_run( bless( {}, 'S2RenderingNotes::Apache' ), $ctx, {}, 'entry', {} ),
            'S2 cleaner completes' );
        return $out;
    };
    like( $run->('A'), qr/\A(?:expanded:A)+\z/, 'cleaner uses journal A native request note' );
    like( $run->('B'), qr/\A(?:expanded:B)+\z/,
        'sequential cleaner uses journal B without leakage' );
    my $expanded_before_no_request = scalar @expanded;
    my $none                       = $run->(undef);
    is( scalar @expanded, $expanded_before_no_request,
        'no-request cleaner does not expand embeds' );
    like( $none, qr/lj-embed/i, 'no-request cleaner retains unexpanded embed output' );
};

subtest 'control-strip hooks and current datetime use only native journal notes' => sub {
    my %journal = (
        A => S2RenderingNotes::Journal->new( 'A', 5.5 ),
        B => S2RenderingNotes::Journal->new( 'B', -3 )
    );
    my @hooks;
    my @zones;
    no warnings 'redefine';
    local *LJ::load_userid     = sub { $journal{ $_[0] } };
    local *LJ::Hooks::run_hook = sub { push @hooks, [@_]; return "hook:$_[1]{id}" };
    local *DateTime::now       = sub { push @zones, $_[2]; return S2RenderingNotes::Date->new };
    request('A');
    is( S2::Builtin::LJ::control_strip_logged_out_userpic_css(),
        'hook:A', 'first userpic hook uses journal A' );
    is( S2::Builtin::LJ::journal_current_datetime( [] )->{hour}, 7, 'A datetime is populated' );
    request('B');
    is( S2::Builtin::LJ::control_strip_logged_out_full_userpic_css(),
        'hook:B', 'second userpic hook uses journal B' );
    is( S2::Builtin::LJ::journal_current_datetime( [] )->{hour}, 7, 'B datetime is populated' );
    DW::Request->reset;
    is( S2::Builtin::LJ::control_strip_logged_out_userpic_css(),
        '', 'no request has empty userpic CSS fallback' );
    is_deeply(
        S2::Builtin::LJ::journal_current_datetime( [] ),
        { _type => 'DateTime' },
        'no request has type-only datetime fallback'
    );
    is_deeply(
        \@zones,
        [ '05' . '30', '-03' . '00' ],
        'A and B timezone offsets are independently selected'
    );
    is_deeply(
        [ map { $_->[1]->id } @hooks ],
        [ 'A', 'B' ],
        'hooks receive only their request journals'
    );
};

subtest 'ordinary Entry and control-strip visibility work without any active request' => sub {
    no warnings 'redefine';
    local *LJ::currents        = sub { return () };
    local *LJ::Hooks::run_hook = sub { return 1 };
    my $journal = bless {}, 'S2RenderingNotes::Journal';
    my $entry   = LJ::S2::Entry(
        $journal,
        {
            userpic             => {},
            poster              => {},
            journal             => { _u => $journal },
            security            => 'public',
            adult_content_level => '',
            props               => {},
            dateparts           => {},
            system_dateparts    => {},
            group_names         => [],
            text                => '',
            itemid              => 1,
        }
    );
    isa_ok( $entry, 'HASH', 'ordinary Entry renders without any active request' );
    ok( S2::Builtin::LJ::viewer_sees_control_strip(),
        'ordinary control-strip hook remains callable without any active request' );
};

done_testing;
