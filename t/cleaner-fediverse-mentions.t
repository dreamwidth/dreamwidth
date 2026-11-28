# t/cleaner-fediverse-mentions.t
#
# Test that fediverse handles survive automatic user mention conversion.
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

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;

my $system = LJ::ljuser('system');
my $github = DW::External::User->new( user => 'system', site => 'github.com' )->ljuser_display;

for my $format (qw(html_casual1 markdown0)) {
    subtest $format => sub {
        my $check = sub {
            my ( $input, $expected, $description ) = @_;
            my $text = $input;
            LJ::CleanHTML::clean_event( \$text, { editor => $format } );
            chomp $text;
            $expected = "<p>$expected</p>" if $format eq 'markdown0';
            is( $text, $expected, $description );
        };

        for my $handle (
            '@cocoa@thread.seam.rip',          '@first-last@social.example',
            '@first.last@social.example',      '@first_last@social.example',
            '@first-last@social-host.example', '@first.last@social-host.example',
            )
        {
            $check->( $handle,          $handle,          "handle at start: $handle" );
            $check->( "Hello $handle!", "Hello $handle!", "handle in prose: $handle" );
        }

        $check->(
            '@system and @cocoa@thread.seam.rip',
            "$system and \@cocoa\@thread.seam.rip",
            'ordinary mention before a fediverse handle'
        );
        $check->(
            '@cocoa@thread.seam.rip and @system',
            "\@cocoa\@thread.seam.rip and $system",
            'ordinary mention after a fediverse handle'
        );
        $check->( '\@cocoa@thread.seam.rip', '@cocoa@thread.seam.rip', 'escaped handle' );
        $check->( '@system', $system, 'ordinary mention' );
        $check->( 'Hello @system!',         "Hello $system!",   'ordinary mention in prose' );
        $check->( 'hi @system.github.com.', "hi $github.",      'supported external site' );
        $check->( '\@system',               '@system',          'escaped ordinary mention' );
        $check->( 'user@example.com',       'user@example.com', 'email address' );
        $check->(
            'https://medium.com/@username/title-of-page',
            $format eq 'markdown0'
            ? 'https://medium.com/@username/title-of-page'
            : '<a href="https://medium.com/@username/title-of-page">https://medium.com/@username/title-of-page</a>',
            'URL containing a username'
        );
        is(
            do {
                my $text = '<pre>@cocoa@thread.seam.rip</pre>';
                LJ::CleanHTML::clean_event( \$text, { editor => $format } );
                chomp $text;
                $text;
            },
            '<pre>@cocoa@thread.seam.rip</pre>',
            'handle in a preformatted element'
        );
        $check->(
            'inline `@cocoa@thread.seam.rip` code',
            'inline <code>@cocoa@thread.seam.rip</code> code',
            'handle in a Markdown code span'
        ) if $format eq 'markdown0';
        done_testing;
    };
}
done_testing;
