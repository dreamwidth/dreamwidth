# t/template-plugin-formhtml.t
#
# Test DW::Template::Plugin::FormHTML.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 15;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Template::Plugin::FormHTML;
use HTML::Parser;

my $form = DW::Template::Plugin::FormHTML->new();

sub _parser_start {
    my ( $parser, $tagname, $attr ) = @_;

    my $tag = {
        tag  => $tagname,
        attr => $attr,
    };

    my $unclosed = $parser->{_parse_results}->{unclosed};
    if ( $parser->{_parse_depth} ) {
        my $current_ele = $unclosed->[-1];
        $current_ele->{children} ||= [];
        push @{ $current_ele->{children} }, $tag;
    }
    else {
        my $parsed = $parser->{_parse_results}->{parsed};
        push @$parsed, $tag;
    }

    push @$unclosed, $tag;
    $parser->{_parse_depth}++;
}

sub _parser_text {
    my ( $parser, $text ) = @_;

    my $unclosed = $parser->{_parse_results}->{unclosed};

    my $current_ele = $unclosed->[-1];
    $current_ele->{text} = LJ::trim($text) if $current_ele;
}

sub _parser_end {
    my ( $parser, $tagname ) = @_;

    my $unclosed = $parser->{_parse_results}->{unclosed};

    my $current_ele = $unclosed->[-1];
    if ( $current_ele && $current_ele->{tag} eq $tagname ) {
        pop @$unclosed;
        $parser->{_parse_depth}--;
    }
}

sub parse {
    my ($in) = @_;
    my $parser = HTML::Parser->new( api_version => 3, );

    # quick and dirty parser which assumes correct nesting
    $parser->handler( "start" => \&_parser_start, "self, tagname, attr" );
    $parser->handler( "text"  => \&_parser_text,  "self, text" );
    $parser->handler( "end"   => \&_parser_end,   "self, tagname" );
    $parser->{_parse_results} = { parsed => [], unclosed => [] };
    $parser->{_parse_depth}   = 0;

    $parser->parse($in);
    return $parser->{_parse_results}->{parsed};
}

$form->{data} = { foo => "bar" };

note("basic generated select");
{
    my $select = parse(
        $form->select(
            {
                label => "Select",
                name  => "foo",
                id    => "foo",
                items => [qw( a apple b "banapple" c <strong>crabapple</strong> bar baz )]
            }
        )
    );

    my $label = $select->[0];
    is( $label->{text}, "Select", "Have label" );
    is( $label->{attr}->{for}, "foo" );

    my $dropdown = $select->[1];
    is( $dropdown->{attr}->{name}, "foo" );
    is( $dropdown->{attr}->{id},   "foo" );

    my @options;
    foreach ( @{ $dropdown->{children} } ) {

        my $option = { text => $_->{text} };
        while ( my ( $k, $v ) = each %{ $_->{attr} } ) {
            $option->{$k} = $v;
        }

        push @options, $option;
    }

    is_deeply(
        \@options,
        [
            { value => "a",   text => "apple" },
            { value => "b",   text => "&quot;banapple&quot;" },                      # escape
            { value => "c",   text => "&lt;strong&gt;crabapple&lt;/strong&gt;" },    # escape
            { value => "bar", text => "baz", selected => "selected" }
            ,    # selected automatically from data source
        ],
        "Correctly escaped / processed / selected options"
    );

}

note("check select where the value is overriden (nothing selected)");
{
    my $select = parse(
        $form->select(
            {
                label    => "Select",
                name     => "foo",
                id       => "foo",
                selected => "",
                items    => [qw( bar baz yes 1 no 2 )]
            }
        )
    );

    my @options;
    foreach ( @{ $select->[1]->{children} } ) {

        my $option = { text => $_->{text} };
        while ( my ( $k, $v ) = each %{ $_->{attr} } ) {
            $option->{$k} = $v;
        }

        push @options, $option;
    }

    is_deeply(
        \@options,
        [
            { value => "bar", text => "baz" },
            { value => "yes", text => "1" },
            { value => "no",  text => "2" },
        ]
    );

}

note("check select where the value is overriden (have something selected)");
{
    my $select = parse(
        $form->select(
            {
                label    => "Select",
                name     => "foo",
                id       => "foo",
                selected => "yes",
                items    => [qw( bar baz yes 1 no 2 )]
            }
        )
    );

    my @options;
    foreach ( @{ $select->[1]->{children} } ) {

        my $option = { text => $_->{text} };
        while ( my ( $k, $v ) = each %{ $_->{attr} } ) {
            $option->{$k} = $v;
        }

        push @options, $option;
    }

    is_deeply(
        \@options,
        [
            { value => "bar", text => "baz" },
            { value => "yes", text => "1", selected => "selected" },
            { value => "no",  text => "2" },
        ]
    );

}

# every start tag in the order it appears, ignoring nesting
sub start_tags {
    my ($in) = @_;
    my @tags;
    my $parser = HTML::Parser->new(
        api_version => 3,
        start_h     => [ sub { push @tags, { tag => $_[0], attr => $_[1] } }, "tagname, attr" ],
    );
    $parser->parse($in);
    $parser->eof;
    return @tags;
}

note("copy_text: read-only field, with a button wired to that field");
{
    my $value = qq{<img src="x.png" alt="it's & more" />};
    my @tags  = start_tags(
        $form->copy_text( { label => "Embed code", id => "embed", value => "  $value\n" } ) );

    my ($label)  = grep { $_->{tag} eq "label" } @tags;
    my ($field)  = grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "text" } @tags;
    my ($button) = grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "button" } @tags;
    my ($status) = grep { ( $_->{attr}->{role} // "" ) eq "status" } @tags;

    is( $label->{attr}->{for}, "embed", "label is paired with the field" );
    is( $field->{attr}->{value},
        $value, "value survives escaping intact, without surrounding whitespace" );
    ok( exists $field->{attr}->{readonly}, "field is read-only" );
    is( $button->{attr}->{"aria-controls"}, "embed", "button copies its own field" );
    is(
        $button->{attr}->{"data-copy-status"},
        $status->{attr}->{id},
        "button reports to its own status region"
    );
}

note("copy_text: two fields with generated ids each get their own button");
{
    my $html = $form->copy_text( { name => "first", value => "one" } )
        . $form->copy_text( { name => "second", value => "two" } );
    my @tags = start_tags($html);

    my %value_of = map { $_->{attr}->{id} => $_->{attr}->{value} }
        grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "text" } @tags;
    my @targets = map { $_->{attr}->{"aria-controls"} }
        grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "button" } @tags;

    is( scalar keys %value_of, 2, "fields have distinct ids" );
    is_deeply(
        [ map { $value_of{$_} } @targets ],
        [ "one", "two" ],
        "each button targets the field before it"
    );
}

note("LJ::html_copy_text works without the template plugin");
{
    my @tags = start_tags( LJ::html_copy_text( { value => "plain" } ) );
    my ($field)  = grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "text" } @tags;
    my ($button) = grep { $_->{tag} eq "input" && $_->{attr}->{type} eq "button" } @tags;
    ok( $field->{attr}->{id} && $button->{attr}->{"aria-controls"} eq $field->{attr}->{id},
        "generated id links the button to the field" );
}
