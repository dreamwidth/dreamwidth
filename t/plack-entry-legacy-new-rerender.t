#!/usr/bin/perl
# Verify old-schema new-entry rerenders use the shared native form without saving.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Controller::Entry;
use DW::Entry::Legacy;
use DW::FormErrors;
use DW::Request;
use DW::Request::Plack;
use Plack::Middleware::DW::RequestWrapper;
use LJ::Test qw(temp_user);
use LJ::Userpic;

plan skip_all => 'Legacy rerender integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

sub file_contents {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    local $/;
    my $contents = <$fh>;
    return \$contents;
}

sub entry_form {
    my ($content) = @_;
    return (
        grep {
                   ( $_->attr('id') || '' ) eq 'js-post-entry'
                && $_->find_input('subject')
                && $_->find_input('event')
        } HTML::Form->parse( $content, 'http://localhost/entry/new' )
    )[0];
}

sub query_values {
    my ($url) = @_;
    my $uri = URI->new($url);
    my %query;
    my @pairs = $uri->query_form;
    while (@pairs) {
        my ( $name, $value ) = splice @pairs, 0, 2;
        push @{ $query{$name} }, $value;
    }
    return ( $uri, \%query );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
$owner->create_trust_group( groupname => 'Legacy rerender group' );
my $userpic =
    LJ::Userpic->create( $owner, data => file_contents("$ENV{LJHOME}/t/data/userpics/good.jpg") );
ok( $userpic, 'disposable owner userpic is created' )
    or BAIL_OUT('cannot exercise legacy rerender userpic control');
$userpic->set_keywords('legacy-keyword');
my $owner_id = $owner->id;
my ($entries_before) =
    $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );

my $app = Plack::Middleware::DW::RequestWrapper->wrap(
    sub {
        my $prepared = DW::Entry::Legacy::prepare_entry_form( DW::Request->get->post_args );
        my $errors   = DW::FormErrors->new;
        $errors->add_string( undef, 'Legacy rerender visible error marker' );
        DW::Controller::Entry::legacy_new_rerender(
            $prepared,
            remote => $owner,
            errors => $errors,
        );
        DW::Request->get->status(200);
        return DW::Request->get->res;
    }
);

test_psgi $app, sub {
    my $request = shift;
    my $uri     = URI->new('http://localhost/legacy-rerender');
    $uri->query_form(
        usejournal => $owner->user,
        encoded    => 'value & slash/value',
        repeated   => 'first value',
        repeated   => 'second/value',
    );

    my $res = $request->(
        POST(
            $uri->path_query,
            [
                usejournal            => $owner->user,
                subject               => 'Legacy rerender subject',
                event                 => '<p>Legacy rerender body</p>',
                security              => 'custom',
                custom_bit_1          => 1,
                date_ymd_mm           => '02',
                date_ymd_dd           => '03',
                date_ymd_yyyy         => '2020',
                hour                  => '04',
                min                   => '05',
                date_diff             => 1,
                prop_taglist          => 'legacy-one, legacy-two',
                prop_current_location => 'Legacy rerender location',
                prop_current_music    => 'Legacy rerender music',
                prop_picture_keyword  => 'legacy-keyword',
                prop_opt_backdated    => 1,
                switched_rte_on       => 1,
                prop_xpost_check      => 0,
            ]
        )
    );

    is( $res->code, 200, 'old-schema rerender returns the shared native form response' );
    like(
        $res->content,
        qr/Legacy rerender visible error marker/,
        'submitted error is visibly rendered through the native template'
    );
    my $form = entry_form( $res->content );
    ok( $form, 'actual shared native entry form parses' ) or BAIL_OUT('shared entry form missing');

    my ( $action_uri, $query ) = query_values( $form->action );
    is( $action_uri->path, '/entry/new', 'rerender form posts to native new-entry route' );
    is( $action_uri->query, $uri->query,
        'native action retains the original encoded query string byte-for-byte' );
    is_deeply(
        $query,
        {
            usejournal => [ $owner->user ],
            encoded    => ['value & slash/value'],
            repeated   => [ 'first value', 'second/value' ],
        },
        'native action preserves encoded and repeated request query context'
    );

    is( $form->value('subject'), 'Legacy rerender subject', 'submitted subject is retained' );
    is( $form->value('event'), '<p>Legacy rerender body</p>', 'submitted body is retained' );
    is( $form->value('editor'),   'rte0',   'legacy RTE conversion selects the native RTE editor' );
    is( $form->value('security'), 'custom', 'legacy custom security is retained' );
    is( $form->value('entrytime_date'),
        '2020-02-03', 'legacy date is retained in native date control' );
    is( $form->value('entrytime_time'), '04:05', 'legacy time is retained in native time control' );
    is( $form->value('entrytime_outoforder'), 1, 'legacy backdating is retained' );
    is( $form->value('taglist'), 'legacy-one, legacy-two', 'legacy tags are retained' );
    is(
        $form->value('current_location'),
        'Legacy rerender location',
        'legacy location is retained'
    );
    is( $form->value('current_music'), 'Legacy rerender music', 'legacy music is retained' );
    is( $form->value('prop_picture_keyword'),
        'legacy-keyword', 'legacy userpic keyword is retained' );
    is( $form->value('usejournal'), $owner->user, 'submitted target journal is retained' );
    ok( $form->find_input('custom_bit'), 'native custom-group controls are rendered' );
    my ($selected_custom_bit) =
        grep { ( $_->name || '' ) eq 'custom_bit' && defined $_->value && $_->value eq '1' }
        $form->inputs;
    ok( $selected_custom_bit,
        'selected legacy custom bit remains selected in native custom-group controls' );
};

my $fresh_owner = LJ::load_userid( $owner_id, 1 );
my ($entries_after) =
    $fresh_owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef,
    $owner_id );
is( $entries_after, $entries_before, 'pure rerender helper does not create an entry' );

done_testing;
