#!/usr/bin/perl
# t/customtextmodule.t
#
# Custom text module headings can be deliberately empty without changing defaults.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use Test::More;
use HTML::Parser;
use HTTP::Request::Common qw(GET POST);
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Cache;
use DW::Request;
use DW::Request::Standard;
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Widget::CustomTextModule;
use LJ::S2;
use S2;

sub prepare_blank_heading_prop {
    my $reader = LJ::get_db_reader();
    local $reader->{RaiseError} = 1;
    my ($propid) = $reader->selectrow_array( 'SELECT upropid FROM userproplist WHERE name = ?',
        undef, 'customtext_title_blank' );
    return if defined $propid;

    $reader->do('CREATE TEMPORARY TABLE userproplist SELECT * FROM userproplist');
    my ($next_propid) = $reader->selectrow_array('SELECT MAX(upropid) + 1 FROM userproplist');
    $reader->do(
        q{INSERT INTO userproplist (upropid, name, indexed, cldversion, datatype)
          VALUES (?, ?, '0', 4, 'bool')}, undef, $next_propid, 'customtext_title_blank'
    );
}

prepare_blank_heading_prop();
my $u = temp_user();
$u->set_prop( stylesys => 1 );
my @context;
$context[S2::LAYERLIST] = [];
$context[S2::PROPS]     = {
    text_module_customtext         => 'Custom Text',
    text_module_customtext_url     => '',
    text_module_customtext_content => ''
};

sub start_widget_request {
    my ($http_request) = @_;
    DW::Request->reset;
    DW::Cache->request->clear;
    DW::Request::Standard->new($http_request);
    LJ::set_remote($u);
}

sub heading {
    my ( $expected, $description ) = @_;
    start_widget_request( GET 'http://localhost/customize/options' );
    my $html = LJ::Widget::CustomTextModule->render_body( count => 0 );
    my $value;
    my $parser = HTML::Parser->new(
        api_version => 3,
        start_h     => [
            sub {
                my ( $tag, $attr ) = @_;
                $value = $attr->{value}
                    if $tag eq 'input'
                    && ( $attr->{name} || '' ) eq
                    'Widget[CustomTextModule]_module_customtext_title';
            },
            'tagname, attr'
        ],
    );
    $parser->parse($html);
    is( $value, $expected, "$description in editor" );
    LJ::set_remote(undef);
    local $u->{_s2styleid}   = 0;
    local $u->{_journalbase} = $u->journal_base;
    my $page = LJ::S2::Page( $u, { getargs => {}, ctx => \@context } );
    is( $page->{customtext_title}, $expected, "$description in journal page" );
}

sub save_heading {
    my ( $title, $reset ) = @_;
    start_widget_request(
        POST 'http://localhost/customize/options',
        Content => [
            'Widget[CustomTextModule]_module_customtext_title'   => $title,
            'Widget[CustomTextModule]_module_customtext_url'     => '',
            'Widget[CustomTextModule]_module_customtext_content' => 'Custom text body',
            ( $reset ? ( 'Widget[CustomizeTheme]_reset' => 1 ) : () ),
        ]
    );
    LJ::Widget::CustomTextModule->handle_post( LJ::Widget::CustomTextModule->post_fields );
}

with_fake_memcache {
    heading( 'Custom Text', 'unset heading keeps default' );
    save_heading('');
    heading( '', 'saved blank heading remains blank' );
    heading( '', 'rendering does not restore default' );
    with_fake_memcache {
        DW::Cache->request->clear;
        $u = LJ::load_userid( $u->id, 'force' );
        heading( '', 'blank heading persists after a database reload' );
    };
    save_heading('A custom heading');
    heading( 'A custom heading', 'named heading still works' );
    save_heading('');
    heading( '', 'named heading can be cleared' );
    save_heading( '', 1 );
    heading( 'Custom Text', 'reset restores default' );
    save_heading('Another heading');
    heading( 'Another heading', 'heading can be set after reset' );
    is( $u->prop('customtext_content'), 'Custom text body', 'body is retained' );
};
done_testing();
