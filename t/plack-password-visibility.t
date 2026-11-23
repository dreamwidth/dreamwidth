# t/plack-password-visibility.t
#
# Verify password controls on login and password change forms.
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

use Test::More;
use HTML::Parser;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub tags {
    my ( $html, $tag ) = @_;
    my @matches;
    my $parser = HTML::Parser->new( api_version => 3 );
    $parser->report_tags($tag);
    $parser->handler( start => sub { push @matches, $_[0]; }, 'attr' );
    $parser->parse($html);
    $parser->eof;
    return @matches;
}

test_psgi $app, sub {
    my $client = shift;
    subtest 'standalone header login modal' => sub {
        my $response = $client->( GET 'http://localhost/site/opensource' );
        is( $response->code, 200, 'page loads' );
        my $html      = $response->content;
        my ($head)    = $html =~ m{<head\b[^>]*>(.*?)</head>}is;
        my @passwords = grep { ( $_->{type} // '' ) eq 'password' } tags( $html, 'input' );
        is_deeply( [ map { $_->{id} } @passwords ],
            ['nav_login_password'], 'the header modal supplies the only password field' );
        ok(
            scalar grep( { ( $_->{href} // '' ) =~ m{css/components/password-visibility\.css\b} }
                tags( $head // '', 'link' ) ),
            'password visibility stylesheet is included in the head'
        );
        ok(
            scalar grep( { ( $_->{src} // '' ) =~ m{components/password-visibility\.js\b} }
                tags( $html, 'script' ) ),
            'password visibility script is included in the page'
        );
    };

    for my $case (
        [ '/login',          'password' ],
        [ '/changepassword', qw(password newpass1 newpass2) ],
        [ '/mobile/login',   'password' ]
        )
    {
        my ( $path, @names ) = @$case;
        subtest $path => sub {
            my $response = $client->( GET "http://localhost$path" );
            is( $response->code, 200, 'form loads' );
            my $html    = $response->content;
            my @inputs  = tags( $html, 'input' );
            my @buttons = grep { exists $_->{'data-password-visibility'} } tags( $html, 'button' );

            for my $name (@names) {
                my @fields = grep { ( $_->{name} // '' ) eq $name } @inputs;
                ok( @fields, "$name is present" );
                for my $field (@fields) {
                    my $id      = $field->{id};
                    my @with_id = grep { ( $_->{id} // '' ) eq $id } @inputs;
                    is( scalar @with_id,       1,          "$id identifies only one input" );
                    is( $field->{type},        'password', "$id initially masks the password" );
                    is( $field->{value} // '', '',         "$id does not echo a password" );
                    my @controls = grep { ( $_->{'aria-controls'} // '' ) eq $id } @buttons;
                    is( scalar @controls, 1, "$id has exactly one visibility control" );
                    my $button = $controls[0] // {};
                    is( $button->{type}, 'button', "$id visibility control cannot submit" );
                    like( $button->{'aria-label'} // '', qr/\bshow\b/i, "$id control has a name" );
                    ok( exists $button->{hidden}, "$id control is hidden until script runs" );
                }
            }
            ok(
                scalar grep( { ( $_->{src} // '' ) =~ m{components/password-visibility\.js\b} }
                    tags( $html, 'script' ) ),
                'password visibility script is included'
            );
            ok(
                scalar
                    grep( { ( $_->{href} // '' ) =~ m{css/components/password-visibility\.css\b} }
                    tags( $html, 'link' ) ),
                'password visibility stylesheet is included'
            );

            if ( $path eq '/login' ) {
                my @checkboxes = grep     { ( $_->{name} // '' ) eq 'remember_me' } @inputs;
                my @ids        = sort map { $_->{id} // '' } @checkboxes;
                is_deeply(
                    \@ids,
                    [qw(login_remember_me nav_login_remember_me)],
                    'the page and header remember-me checkboxes have distinct IDs'
                );
                my @labels = sort grep { /\A(?:nav_)?login_remember_me\z/ }
                    map { $_->{for} // '' } tags( $html, 'label' );
                is_deeply( \@labels, \@ids, 'each remember-me checkbox has its own label' );
            }
        };
    }
};

subtest 'legacy password input' => sub {
    my $id   = qq{password"<sample>&};
    my $html = LJ::html_text( { type => 'password', id => $id, autocomplete => 'new-password' } );
    my ($input)  = tags( $html, 'input' );
    my ($button) = tags( $html, 'button' );
    is( $input->{id},               $id,            'input ID round-trips through escaping' );
    is( $input->{autocomplete},     'new-password', 'password-manager hint is preserved' );
    is( $button->{'aria-controls'}, $id,            'button references the escaped input ID' );
    unlike( $html, qr/<sample>/, 'input ID cannot become markup' );

    my $compact = LJ::html_text( { type => 'password', no_password_visibility => 1 } );
    my ($compact_input) = tags( $compact, 'input' );
    is( $compact_input->{type}, 'password', 'compact input remains masked' );
    ok( !exists $compact_input->{no_password_visibility}, 'opt-out is not an HTML attribute' );
    ok( !tags( $compact, 'button' ), 'compact input opts out of the button' );
};

done_testing();
