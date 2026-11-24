# t/headings-account-manage.t
#
# Check the heading outline rendered by Account and Manage templates.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use DW::Template;
use HTML::Parser;
use HTTP::Request;
use LJ::Lang;
use LJ::UniqCookie;

sub check_outline {
    my ( $template, $state, $vars, $title, $headings, $content ) = @_;

    subtest "$template: $state" => sub {
        LJ::start_request();
        DW::Request::Standard->new( HTTP::Request->new( GET => 'http://example.test/' ) );
        LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
        LJ::UniqCookie->set_current_uniq('headingsaccountmanage');
        my %sections;
        my $body = DW::Template->template_string( "$template.tt", $vars, \%sections );
        like( $body, $content, 'expected state rendered' );

        my ( @levels, @text, $in_heading );
        my $parser = HTML::Parser->new(
            api_version => 3,
            start_h     => [
                sub {
                    return unless $_[0] =~ /^h([1-6])$/;
                    push @levels, $1;
                    push @text,   '';
                    $in_heading = 1;
                },
                'tagname'
            ],
            end_h => [ sub { $in_heading = 0 if $_[0] =~ /^h[1-6]$/ }, 'tagname' ],
            text_h => [ sub { $text[-1] .= $_[0] if $in_heading }, 'dtext' ],
        );
        $parser->parse( "<h1>$sections{title}</h1>" . $body );
        $parser->eof;

        is_deeply(
            [ map { s/\s+/ /gr =~ s/^ | $//gr } @text ],
            [ $title, @$headings ],
            'page title and expected headings in order'
        );
        is( scalar( grep { $_ == 1 } @levels ), 1, 'only the site-scheme title is an h1' );
        my @skips = grep { $levels[$_] > $levels[ $_ - 1 ] + 1 } 1 .. $#levels;
        ok( !@skips, 'heading levels do not skip: ' . join( ', ', map { "h$_" } @levels ) );
    };
}

my $enabled    = 'settings/manage2fa/index-enabled';
my $disabled   = 'settings/manage2fa/index-disabled';
my $two_factor = 'Manage Two-Factor Authentication';
my $recovery   = [ 'Recovery Codes', 'Disable 2FA' ];
my $codes      = { show_codes => 1, codes => ['example-code'] };
check_outline( $enabled, 'codes hidden', {}, $two_factor, $recovery, qr/Show Recovery Codes/ );
check_outline( $enabled, 'codes revealed',
    {%$codes}, $two_factor, $recovery, qr/<code>example-code/ );
check_outline( $enabled, 'just enabled', { %$codes, just_enabled => 1 },
    $two_factor, $recovery, qr/This browser remains signed in/ );
check_outline( $disabled, 'disabled', {}, $two_factor, [],
    qr/Begin Two-Factor Authentication Setup/ );
check_outline(
    $disabled,
    'just disabled',
    { just_disabled => 1 },
    $two_factor, [], qr/Two-factor authentication has been disabled/
);

my $privacy      = 'Edit Journal Privacy';
my $confirmation = ['Are you sure you want to revise these entries?'];
my $change       = {
    mode     => 'change',
    security => { public => [ 1, 'Public' ], private => [ 2, 'Private' ] },
    POST     => { time => 'all', s_security => 'public', e_security => 'private' },
    s_dt     => { ymd => '2026-01-01', epoch => 1767225600 },
    e_dt     => { ymd => '2026-01-02', epoch => 1767312000 },
};
check_outline(
    'editprivacy', 'initial form', { mode => 'init' },
    $privacy,
    [ 'Timeframe', 'Privacy' ],
    qr/Modify Entries/
);
check_outline(
    'editprivacy',
    'no entries matched',
    { %$change, posts => 0 },
    $privacy, [], qr/0 matching entries/
);
check_outline( 'editprivacy', 'less public', { %$change, posts => 1 },
    $privacy, $confirmation, qr/Yes, Modify these Entries/ );
check_outline(
    'editprivacy',
    'more public in a date range',
    {
        %$change,
        posts       => 1,
        more_public => 1,
        POST        => { time => 'range', s_security => 'private', e_security => 'public' }
    },
    $privacy,
    $confirmation,
    qr/Password Required/
);

for my $mode (qw(amsure secured)) {
    check_outline( 'editprivacy', $mode, { mode => $mode },
        $privacy, [], qr/The security level of your entries will be revised/ );
}

my $personal = {
    is_personal           => 1,
    email_raw             => 'account@example.test',
    is_validated          => 1,
    can_use_esn           => 1,
    can_create_moodthemes => 1
};
my @groups = ( 'Settings and Preferences', 'Customization', 'Journal Entries', 'Access Page',
    'Communities' );
my @accounts = (
    [ 'personal', $personal, $personal, 'Your Account:', qr/account\@example\.test/ ],
    [
        'community', { is_community => 1, email_raw => 'community@example.test' },
        $personal, 'Your Community:',
        qr/community\@example\.test/
    ],
    [
        'identity',
        { is_identity => 1, is_deleted => 1 },
        { is_identity => 1 },
        'Your Account:',
        qr{href=['"][^'"]*/changeemail}
    ],
);
for my $account (@accounts) {
    my ( $state, $user, $remote, $heading, $content ) = @$account;
    check_outline(
        'manage/index',
        $state,
        {
            u           => $user,
            remote      => $remote,
            use_s2      => $user->{is_personal},
            use_invites => $remote->{is_personal},
            use_tags    => !$user->{is_identity}
        },
        'Manage Accounts',
        [ $heading, @groups ],
        $content
    );
}

check_outline(
    'manage/subscriptions/filters', 'filter options',
    { remote => { user => 'example' } }, 'Manage Subscription Filters',
    ['Options for "selected filter"'], qr/id=['"]cf-foname['"]/
);

done_testing;
