# t/headings-admin.t
#
# Check the heading structure of Dreamwidth's admin templates.
#
# Authors:
#      Alex (@saphid)
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
use DW::VirtualGift;
use HTML::Parser;
use HTTP::Request;
use LJ::Lang;
use LJ::UniqCookie;

{

    package Local::Artist;
    sub display_name   { 'Paper artist' }
    sub ljuser_display { 'Paper artist' }

    package Local::Gift;
    use parent 'DW::VirtualGift';

    sub creator  { bless {}, 'Local::Artist' }
    sub approver { bless {}, 'Local::Artist' }
    sub tags     { [] }
    sub checksum { 'test-checksum' }
    sub num_sold { 0 }
    sub can_be_approved_by { $_[1] eq 'reviewer' && !$_[0]->is_active }
    sub can_be_edited_by   { $_[1] eq 'artist'   && !$_[0]->is_active }
}

sub check_headings {
    my ( $template, $state, $vars, $count, $expected, $body_match ) = @_;
    subtest "$template: $state" => sub {
        LJ::start_request();
        DW::Request->reset;
        DW::Request::Standard->new( HTTP::Request->new( GET => "http://www.dw.test/$template" ) );
        LJ::UniqCookie->set_current_uniq('headingsadmin01');
        LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
        my $sections = {};
        my $body     = DW::Template->template_string( "admin/$template.tt", $vars, $sections );

        my ( @levels, @headings );
        my $inside;
        my $parser = HTML::Parser->new( api_version => 3 );
        $parser->handler(
            start => sub {
                return unless $_[0] =~ /^h([1-6])$/;
                push @levels,   $1;
                push @headings, '';
                $inside = 1;
            },
            'tagname'
        );
        $parser->handler( text => sub { $headings[-1] .= $_[0] if $inside }, 'dtext' );
        $parser->handler( end => sub { $inside = 0 if $_[0] =~ /^h[1-6]$/ }, 'tagname' );
        $parser->parse("<h1>$sections->{title}</h1>$body");
        $parser->eof;

        is( scalar( grep { $_ == 1 } @levels ), 1, 'only the site-scheme title is an h1' );
        my @skips = grep { $levels[$_] > $levels[ $_ - 1 ] + 1 } 1 .. $#levels;
        is_deeply( [ map { "h$levels[ $_ - 1 ] to h$levels[$_]" } @skips ],
            [], 'no heading level is skipped' );
        is( scalar @headings, $count + 1, 'expected number of headings including the title' );
        like( join( ' ', @headings ), $expected, 'expected heading text is present' );
        like( $body, $body_match, 'the requested state was rendered' ) if $body_match;
    };
}

my $categories = {
    account => { faqcat => 'account', faqcatname => 'Accounts',       catorder => 1 },
    empty   => { faqcat => 'empty',   faqcatname => 'Empty category', catorder => 2 },
    ''      => { faqcat => '',        faqcatname => '<No Category>' },
};
my $question    = { id => 42, faqid => 42, question_html => 'How do I post?', sortorder => 1 };
my $display_faq = sub { $_[0] };
check_headings( 'faq/faqedit', 'add form', {}, 2, qr/Question Answer/ );
check_headings(
    'faq/faqedit',
    'preview and summary',
    {
        id              => 42,
        preview_faq     => $question,
        preview_summary => 1,
        show_summary    => 1,
        display_faq     => $display_faq,
        s_html          => 'Preview summary',
        a_html          => 'Preview answer',
    },
    4,
    qr/How do I post\? Question Summary Answer/,
    qr/Preview summary.*Preview answer/s
);
check_headings(
    'faq/faqedit',
    'preview without summary',
    {
        id          => 42,
        preview_faq => $question,
        display_faq => $display_faq,
        a_html      => 'Preview answer',
    },
    3,
    qr/How do I post\? Question Answer/,
    qr/Preview answer/
);
check_headings(
    'faq/faqedit', 'saved', { success => 'FAQ saved' },
    0, qr/Edit FAQ|Add to FAQ/,
    qr/FAQ saved/
);

check_headings(
    'faq/faqcat', 'no categories',
    {}, 2,
    qr/Edit existing FAQ categories.*Add a new FAQ category/s,
    qr/no existing FAQ categories/
);
check_headings(
    'faq/faqcat',
    'existing categories',
    {
        faqcat  => $categories,
        catlist => [qw(account empty)],
        success => 'Category saved',
    },
    2,
    qr/Edit existing FAQ categories.*Add a new FAQ category/s,
    qr/Category saved.*Accounts/s
);

for my $can_edit ( 0, 1 ) {
    check_headings(
        'faq/index',
        "categories with edit access $can_edit",
        {
            can_add_any => $can_edit,
            can_manage  => $can_edit,
            can_edit    => sub { $can_edit },
            faqcat      => $categories,
            catlist     => [ 'account', 'empty', '' ],
            faq         => { account => [$question] },
            faqlist     => sub { [$question] },
            display_faq => $display_faq,
        },
        3,
        qr/Accounts\s+Empty category\s+<No Category>/,
        qr/How do I post\?/
    );
}

check_headings(
    'importer/detail', 'no imports', { username => 'tester' },
    0,
    qr/Pending Import Details/,
    qr/No pending imports/
);
my $import = { status => 'waiting', created => 1_700_000_000, source => 'file' };
check_headings(
    'importer/detail',
    'multiple imports',
    {
        username     => 'tester',
        errmsg       => 'error.invalidform',
        import_items => { 7 => { entries => $import }, 8 => { comments => $import } },
    },
    2,
    qr/Import #7 Import #8/,
    qr/class='error-box'/
);

my %privilege = ( pname => 'Support', pcode => 'support', limit => 1, skip => 0 );
check_headings(
    'priv/viewpriv',
    'private privilege',
    {
        %privilege,
        pinfo            => { is_public => 0 },
        remote_can_grant => sub { 0 },
    },
    1,
    qr/View Priv.*Support/s,
    qr/not available for public view/
);
check_headings(
    'priv/viewpriv',
    'public privilege without grant access',
    {
        %privilege,
        pinfo            => { is_public => 1 },
        remote_can_grant => sub { 0 },
    },
    1,
    qr/View Priv.*Support/s,
    qr/do not have access to grant/
);
check_headings(
    'priv/viewpriv',
    'grant and revoke',
    {
        %privilege,
        pinfo            => { is_public => 0, des => 'Support team arg=category' },
        privusers        => [ { arg => 'help', user => 'tester', userid => 1, prmid => 3 } ],
        remote_can_grant => sub { 1 },
    },
    2,
    qr/View Priv.*Support.*Grant.*Support/s,
    qr/revoke:3:1/
);

check_headings( 'styleinfo', 'lookup form', {}, 0, qr/Style Info/, qr/name=["']user["']/ );
check_headings( 'styleinfo', 'no style', { u => 1 }, 0, qr/Style Info/, qr/No style is defined/ );
check_headings(
    'styleinfo',
    'S2 style',
    {
        u          => 1,
        s2style    => { name => 'Notebook', styleid => 42, layer => { layout => 3, user => 0 } },
        public     => { 3 => 1 },
        sort_keys  => sub { [ sort keys %{ $_[0] } ] },
        mysql_time => sub { '' },
    },
    1,
    qr/S2 - Notebook/,
    qr/layerbrowse/
);

my @gifts;
for my $status ( '', 'Y', 'N' ) {
    my $id   = 2_147_483_640 + @gifts;
    my $gift = Local::Gift->new($id);
    $gift->absorb_row(
        {
            vgiftid     => $id,
            name        => 'Paper Crane',
            description => 'A folded paper crane.',
            created_t   => time,
            approved    => $status,
            active      => $status eq 'Y' ? 'Y' : 'N',
        }
    );
    push @gifts, $gift;
}
my ( $queued, $approved, $rejected ) = @gifts;
my $artists         = sub { '<li>Paper artist</li>' };
my $list_created_by = sub { [ $queued, $approved, $rejected ] };
my %gift_vars =
    ( remote => 'artist', display_creatorlist => $artists, list_created_by => $list_created_by );
check_headings( 'vgifts/index', 'submitter home',
    \%gift_vars, 5,
    qr/Create a new virtual gift.*Small.*Large image.*pending submissions.*Leaderboard/s );
check_headings(
    'vgifts/index',
    'siteadmin home',
    {
        %gift_vars,
        siteadmin       => 1,
        list_created_by => sub { [] },
    },
    6,
    qr/Create a new virtual gift.*Leaderboard.*Site Admins/s
);
check_headings( 'vgifts/index', 'edit gift', { %gift_vars, mode => 'view', vgift => $queued },
    4, qr/Paper Crane.*Small.*Large image/s );
check_headings(
    'vgifts/index',
    'view only, queued',
    { mode => 'view', remote => 'reader', vgift => $queued },
    1,
    qr/Paper Crane/,
    qr/folded paper crane/
);
check_headings(
    'vgifts/index',
    'view only, approved',
    { mode => 'view', remote => 'reader', vgift => $approved },
    3, qr/Paper Crane.*Review:.*Approved by/s
);
check_headings( 'vgifts/index', 'view artist',
    { %gift_vars, mode => 'view', vu => bless( {}, 'Local::Artist' ), siteadmin => 1 },
    7, qr/Paper Crane.*Approved by.*Rejected by/s );
check_headings(
    'vgifts/index',
    'view own submissions',
    { %gift_vars, mode => 'view', title => 'deleted' },
    7,
    qr/Paper Crane.*Approved by.*Rejected by/s,
    qr/The gift was deleted/
);
check_headings(
    'vgifts/index',
    'review queue',
    {
        remote      => 'reviewer',
        mode        => 'review',
        siteadmin   => 1,
        review_list => sub { \@gifts },
        days        => 14,
    },
    9,
    qr/Review:.*Approved by.*Optional: suggestions.*Rejected by/s
);
check_headings(
    'vgifts/index',
    'review inactive gift',
    {
        remote    => 'reviewer',
        mode      => 'review',
        siteadmin => 1,
        vgift     => $approved,
        inactive  => 1,
    },
    4,
    qr/Review:.*Approved by.*Optional: suggestions/s
);
check_headings(
    'vgifts/index',
    'empty review queue',
    {
        remote      => 'reviewer',
        mode        => 'review',
        siteadmin   => 1,
        review_list => sub { [] },
    },
    0,
    qr/Virtual Gifts.*Review/s,
    qr/no relevant gifts/
);
check_headings(
    'vgifts/index',
    'delete confirmation',
    {
        mode   => 'delete',
        remote => 'artist',
        vgift  => $queued,
    },
    2,
    qr/Are you sure\?.*Paper Crane/s
);
check_headings(
    'vgifts/index',
    'delete denied',
    { mode => 'delete', remote => 'reader', vgift => $approved },
    0,
    qr/Delete A Gift/,
    qr/cannot be deleted/i
);
check_headings(
    'vgifts/index', 'artists list', { %gift_vars, mode => 'artists' },
    0,
    qr/Virtual Gifts/,
    qr/Paper artist/
);

done_testing();
