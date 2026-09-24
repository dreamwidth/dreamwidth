#!/usr/bin/perl
# Legacy-schema decoding and the native preview route; the retired
# /preview/entry legacy route itself is gone.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use LJ::Session;
use DW::Entry::Legacy;
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use LJ::Customize;
use LJ::Userpic;
plan skip_all => 'Preview integration requires a development server' unless $LJ::IS_DEV_SERVER;

sub file_contents {
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!";
    binmode $fh;
    local $/;
    my $contents = <$fh>;
    close $fh or die "$path: $!";
    return \$contents;
}

sub decoder_request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'POST',
            PATH_INFO         => '/entry/preview',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        },
    );
}

subtest 'legacy decoder uses native request language for the global subject placeholder' => sub {
    decoder_request();
    LJ::Lang::set_request_context(
        lang   => 'marker',
        getter => sub {
            my ( $lang, $key ) = @_;
            return 'LEGACY-PLACEHOLDER-MARKER' if $key eq 'entryform.subject.hint2';
            return "unexpected:$key";
        },
    );
    my $placeholder_prepared = DW::Entry::Legacy::prepare_entry_form(
        {
            subject       => 'LEGACY-PLACEHOLDER-MARKER',
            event         => 'body',
            security      => 'public',
            date_ymd_mm   => '01',
            date_ymd_dd   => '02',
            date_ymd_yyyy => '2020',
            hour          => 3,
            min           => 4,
            date_diff     => 1,
        }
    );
    is( $placeholder_prepared->{canonical}{subject},
        '', 'custom request getter placeholder is cleared without BML' );
    my $ordinary_prepared = DW::Entry::Legacy::prepare_entry_form(
        {
            subject       => 'Ordinary legacy subject',
            event         => 'body',
            security      => 'public',
            date_ymd_mm   => '01',
            date_ymd_dd   => '02',
            date_ymd_yyyy => '2020',
            hour          => 3,
            min           => 4,
            date_diff     => 1,
        }
    );
    is(
        $ordinary_prepared->{canonical}{subject},
        'Ordinary legacy subject',
        'ordinary subject is retained'
    );
    DW::Request->reset;
};

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u = temp_user();
$u->update_self( { status => 'A' } );
my $userpic =
    LJ::Userpic->create( $u, data => file_contents("$ENV{LJHOME}/t/data/userpics/good.jpg"), );
ok( $userpic, 'disposable preview userpic is created' )
    or BAIL_OUT('cannot create preview userpic');
$userpic->set_keywords('legacy-preview-pic');
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
my ($before) = $u->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $u->id );
test_psgi $app, sub {
    my $send = shift;
    my $res  = $send->(
        POST 'http://localhost/entry/preview',
        [
            usejournal           => $u->user,
            security             => 'private',
            subject              => 'Native preview subject',
            event                => 'Native preview body',
            editor               => 'html_casual1',
            entrytime_date       => '2020-01-02',
            entrytime_time       => '03:04',
            trust_datetime       => 1,
            taglist              => 'native-preview-tag',
            current_music        => 'Native music',
            prop_picture_keyword => 'legacy-preview-pic',
            age_restriction      => 'discretion',
        ],
        Cookie => $cookie
    );
    is( $res->code, 200, '/entry/preview renders' );
    like( $res->content, qr/Native preview subject/, '/entry/preview preserves subject' );
    like( $res->content, qr/This is a preview only/, '/entry/preview renders preview warning' );
    like( $res->content, qr/03:04/,                  '/entry/preview preserves timestamp' );
    like( $res->content, qr/native-preview-tag/,     '/entry/preview renders tag metadata' );
    like( $res->content, qr/Native music/,           '/entry/preview renders current music' );
    like(
        $res->content,
        qr/\Q@{[ $userpic->url ]}\E/,
        '/entry/preview renders the selected userpic URL'
    );
};
subtest 'native preview invokes the spam hook' => sub {
    my $calls = 0;
    local $LJ::HOOKS{spam_check} = [ sub { ++$calls; } ];
    test_psgi $app, sub {
        my $send = shift;
        my $request =
            sub { my ($req) = @_; $req->header( Cookie => $cookie ); return $send->($req); };
        my $native = $request->(
            POST 'http://localhost/entry/preview',
            [
                usejournal     => $u->user,
                security       => 'public',
                subject        => 'hook native',
                event          => 'body',
                editor         => 'html_raw0',
                entrytime_date => '2020-01-02',
                entrytime_time => '03:04',
                trust_datetime => 1
            ]
        );
        is( $native->code, 200, 'native hook fixture renders' );
        is( $calls,        1,   'native preview invokes spam_check exactly once' );
    };
};

subtest 'native preview retains its own request translation scope' => sub {
    LJ::Customize->verify_and_load_style($u);
    my $s2_style = $u->prop('s2_style');
    ok( $s2_style, 'fixture has an existing nonzero S2 style' )
        or BAIL_OUT('temporary preview user has no S2 style');
    $u->set_prop( use_journalstyle_entry_page => 'N' );

    no warnings 'redefine';
    local *LJ::Lang::get_text = sub {
        my ( $lang, $key ) = @_;
        return 'NATIVE-SUBJECT-PLACEHOLDER' if $key eq 'entryform.subject.hint2';
        return "preview-key:$key";
    };
    test_psgi $app, sub {
        my $send    = shift;
        my $request = sub {
            my ($req) = @_;
            $req->header( Cookie => $cookie );
            return $send->($req);
        };
        my $native = $request->(
            POST 'http://localhost/entry/preview',
            [
                usejournal     => $u->user,
                security       => 'public',
                subject        => 'Native translation subject',
                event          => 'native translation body',
                editor         => 'html_casual1',
                entrytime_date => '2020-01-02',
                entrytime_time => '03:04',
                trust_datetime => 1,
            ]
        );
        is( $native->code, 200, 'native preview renders with a custom request getter' );
        like(
            $native->content,
            qr/preview-key:\/entry\/preview\.tt\.title/,
            'native preview title retains its TT key'
        );
        like(
            $native->content,
            qr/preview-key:\/entry\/preview\.tt\.entry\.preview_warn_text/,
            'native preview warning retains its TT key'
        );
    };
};

subtest 'native preview content pipeline preserves formatting, ordered polls, and embeds' => sub {
    local $LJ::T_HAS_ALL_CAPS      = 1;
    local $LJ::EMBED_MODULE_DOMAIN = 'embed.localhost';
    $u->set_prop( stylesys                    => 1 );
    $u->set_prop( use_journalstyle_entry_page => 'N' );

    my ($polls_before) =
        $u->selectrow_array( 'SELECT COUNT(*) FROM poll2 WHERE journalid=?', undef, $u->id );
    my ($embeds_before) =
        $u->selectrow_array( 'SELECT COUNT(*) FROM embedcontent WHERE userid=?', undef, $u->id );

    test_psgi $app, sub {
        my $send    = shift;
        my $request = sub {
            my ($req) = @_;
            $req->header( Cookie => $cookie );
            return $send->($req);
        };

        for my $native_case (
            [ 'raw HTML', 'html_raw0', "<strong>Native raw HTML preview</strong>\nRAW-LINE-TWO" ],
            [
                'casual HTML', 'html_casual1',
                "<strong>Native casual HTML preview</strong>\nCASUAL-LINE-TWO"
            ],
            )
        {
            my ( $name, $editor, $event ) = @$native_case;
            my $res = $request->(
                POST 'http://localhost/entry/preview',
                [
                    usejournal     => $u->user,
                    security       => 'public',
                    subject        => "Native $name subject",
                    event          => $event,
                    editor         => $editor,
                    entrytime_date => '2020-01-02',
                    entrytime_time => '03:04',
                    trust_datetime => 1,
                ]
            );
            is( $res->code, 200, "native $name preview renders" );
            like(
                $res->content,
                qr/Native \Q$name\E preview/,
                "native $name preview preserves submitted markup"
            );
            my $line    = $editor eq 'html_raw0' ? 'RAW-LINE-TWO' : 'CASUAL-LINE-TWO';
            my $newline = $editor eq 'html_raw0' ? qr/\n/         : qr/<br \/?>/;
            like(
                $res->content,
                qr/<strong>Native \Q$name\E preview<\/strong>$newline\Q$line\E/,
                "native $name preview preserves markup with its mode-specific newline rendering"
            );
        }

        my $pipeline_event = join '',
            'ORDER-before-',
'<poll name="First preview poll" isanon="no" whovote="all" whoview="all"><poll-question type="radio">First preview question',
            '<poll-item>First option</poll-item></poll-question></poll>',
            '-ORDER-middle-',
'<poll name="Second preview poll" isanon="no" whovote="all" whoview="all"><poll-question type="radio">Second preview question',
            '<poll-item>Second option</poll-item></poll-question></poll>',
            '-ORDER-embed-',
            '<iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe>',
            '-ORDER-after';
        my @ordered_markers = (
            'ORDER-before-', 'First preview question',
            'ORDER-middle-', 'Second preview question',
            'ORDER-embed-',  'ORDER-after',
        );

        my $native_pipeline = $request->(
            POST 'http://localhost/entry/preview',
            [
                usejournal     => $u->user,
                security       => 'public',
                subject        => 'Native pipeline subject',
                event          => $pipeline_event,
                editor         => 'html_raw0',
                entrytime_date => '2020-01-02',
                entrytime_time => '03:04',
                trust_datetime => 1
            ]
        );
        is( $native_pipeline->code, 200, 'native two-poll/embed preview renders' );
        my $native_content = $native_pipeline->content;

        for my $marker (@ordered_markers) {
            like( $native_content, qr/\Q$marker\E/, "native pipeline renders $marker" );
        }
        my @native_positions = map { index $native_content, $_ } @ordered_markers;
        ok(
            !grep( { $_ < 0 } @native_positions )
                && join( ',', @native_positions ) eq
                join( ',', sort { $a <=> $b } @native_positions ),
            'native two polls and embed retain submitted order'
        );
        like( $native_content, qr/lj_embedcontent-wrapper/, 'native trusted embed expands' );
        my @native_poll_controls = $native_content =~ /<input type=["']radio["']/g;
        is( scalar @native_poll_controls, 2, 'native preview renders both poll radio controls' );
        unlike(
            $native_content,
            qr/<poll-placeholder>|<(?:lj-)?poll\b/i,
            'native preview leaves no raw poll markup or placeholder'
        );
    };

    my ($polls_after) =
        $u->selectrow_array( 'SELECT COUNT(*) FROM poll2 WHERE journalid=?', undef, $u->id );
    my ($embeds_after) =
        $u->selectrow_array( 'SELECT COUNT(*) FROM embedcontent WHERE userid=?', undef, $u->id );
    is( $polls_after, $polls_before, 'preview does not persist either new poll' );
    is( $embeds_after, $embeds_before,
        'preview does not persist the embed outside preview storage' );
};

my ($entries_after_all) =
    $u->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $u->id );
is( $entries_after_all, $before, 'all previews leave the entry count unchanged' );

subtest 'the retired legacy preview route is gone' => sub {
    test_psgi $app, sub {
        my $send = shift;
        for my $path ( '/preview/entry', '/preview/entry.bml' ) {
            my $get = $send->( GET "http://localhost$path" );
            is( $get->code, 404, "$path GET is no longer routed" );
        }
    };
};

done_testing;
