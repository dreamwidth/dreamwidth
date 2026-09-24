#!/usr/bin/perl
# Disposable configured spellcheck server for browser acceptance only.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);
use Starman::Server;

my ( $port, $state_file ) = @ARGV;
die "usage: $0 PORT STATE_FILE\n" unless $port && $state_file;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::SpellCheck;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $configured_app = sub {
    my ($env) = @_;
    local $LJ::SPELLER = 'browser-stub';
    no warnings 'redefine';
    local *LJ::SpellCheck::check_html = sub {
        my ( $self, $body ) = @_;
        open my $fh, '>', $state_file or die "write $state_file: $!";
        print {$fh} encode_json( { checked_body => $$body } );
        close $fh;
        return '<em class="spell-suggestion">browser suggestion</em>';
    };
    return $app->($env);
};

Starman::Server->new->run( $configured_app, { port => $port, host => '127.0.0.1', workers => 1 } );
