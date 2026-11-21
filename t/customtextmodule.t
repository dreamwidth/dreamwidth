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
use HTTP::Request;
use HTML::Parser;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Widget::CustomTextModule;
use LJ::S2;

my $u = temp_user();
$u->set_prop( stylesys => 1 );
$u->{_s2styleid}   = 0;
$u->{_journalbase} = $u->journal_base;
my $request = DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );
my @context;
$context[S2::PROPS] = {
    text_module_customtext         => 'Custom Text',
    text_module_customtext_url     => '',
    text_module_customtext_content => ''
};
my $reset = 0;

sub heading {
    my ( $expected, $description ) = @_;
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
    my $page = LJ::S2::Page( $u, { getargs => {}, ctx => \@context } );
    is( $page->{customtext_title}, $expected, "$description in journal page" );
}

sub save_heading {
    my ($title) = @_;
    LJ::Widget::CustomTextModule->handle_post(
        {
            module_customtext_title   => $title,
            module_customtext_url     => '',
            module_customtext_content => 'Custom text body',
        }
    );
}

{
    no warnings 'redefine';
    local *LJ::Widget::CustomTextModule::get_effective_remote = sub { $u };
    local *LJ::Widget::post_fields_of_widget                  = sub { { reset => $reset } };
    local *LJ::get_remote                                     = sub { undef };
    local *S2::get_style_modtime                              = sub { 0 };
    with_fake_memcache {
        heading( 'Custom Text', 'unset heading keeps default' );
        save_heading('');
        heading( '', 'saved blank heading remains blank' );
        heading( '', 'rendering does not restore default' );
        save_heading('A custom heading');
        heading( 'A custom heading', 'named heading still works' );
        save_heading('');
        heading( '', 'named heading can be cleared' );
        $reset = 1;
        save_heading('');
        heading( 'Custom Text', 'reset restores default' );
        $reset = 0;
        save_heading('Another heading');
        heading( 'Another heading', 'heading can be set after reset' );
        is( $u->prop('customtext_content'), 'Custom text body', 'body is retained' );
    };
}
done_testing();
