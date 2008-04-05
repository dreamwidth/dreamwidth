# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
use HTMLCleaner;

sub clean {
    my $output = '';
    my $cleaner = HTMLCleaner->new(
        output => sub { $output .= $_[0] },
        valid_stylesheet => sub { $_[0] eq 'http://www.example.com/valid.css' },
    );

    my $input = shift;
    $cleaner->parse( $input );
    $cleaner->eof;
    
    return $output;
}

sub is_cleaned {
    my $input = shift;
    my $type = shift;
    my $output = clean($input);
    is( $output, '', $type );
}

sub not_cleaned {
    my $input = shift;
    my $type = shift;
    my $output = clean($input);
    is( $output, $input, $type );
}

not_cleaned(
    '<link rel="alternate" href="http://www.livejournal.com">',
    "html link rel=alternate"
);

not_cleaned(
    '<link rel="shortcut" href="http://www.livejournal.com/favicon.ico">',
    "html link with single valid rel attribute"
);

not_cleaned(
    '<link rel="shortcut icon" href="http://www.livejournal.com/favicon.ico">',
    "html link with two valid rel attributes"
);

not_cleaned(
    '<link>http://example.com/foo.html</link>',
    "rss style link"
);

not_cleaned(
    '<link href="http://example.com/foo.html" />',
    "html/atom link, rel is implied 'alternate' in this form"
);

is_cleaned(
    '<link rel="stylesheet" href="http://www.example.com/bar.css">',
    "html link with disallowed stylesheet href"
);

is_cleaned(
    '<link rel="alternate fox" href="http://www.example.com/bar.css">',
    "html link with one good and one bad rel value"
);

not_cleaned(
    '<link rel="stylesheet" href="http://www.example.com/valid.css">',
    "html link with good stylesheet"
);

is_cleaned(
    '<link rel="script">',
    "html link with script rel, this is not allowed ever",
);
