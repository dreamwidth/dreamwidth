# t/formats.t
#
# Test resolution and validation of available text formats. This just tests
# which ones get chosen under which circumstances; the actual display behavior
# of them is handled in the HTML cleaner tests.
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2017-2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 16;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Formats;

note("Format ID validation/canonicalization tests");

is( DW::Formats::validate('html_casual1'), 'html_casual1', "Normal validation." );

is( DW::Formats::validate('markdown'),
    'markdown0', "Uses canonical name for legacy markdown format value." );

is( DW::Formats::validate('nuthin'), '',
    "Returns empty string when validating unknown format ID." );

note("HTML select items tests");

my $select = DW::Formats::select_items();
is( $select->{selected}, $DW::Formats::default_format,
    "Without args, default format is selected." );
is(
    scalar @{ $select->{items} },
    scalar @DW::Formats::active_formats,
    "Without args, only active formats are offered."
);

$select = DW::Formats::select_items( preferred => 'invalid' );
is( $select->{selected}, $DW::Formats::default_format,
    "w/ invalid preference, default format is selected." );
is(
    scalar @{ $select->{items} },
    scalar @DW::Formats::active_formats,
    "w/ invalid preference, only active formats are offered."
);

$select = DW::Formats::select_items( preferred => 'html_casual0' );
is( $select->{selected}, $DW::Formats::default_format,
    "w/ obsolete preference, default format is selected." );
is(
    scalar @{ $select->{items} },
    scalar @DW::Formats::active_formats,
    "w/ obsolete preference, only active formats are offered."
);

$select = DW::Formats::select_items( preferred => 'markdown0' );
is( $select->{selected}, 'markdown0', "w/ active preference, preference is selected." );

$select = DW::Formats::select_items( current => 'invalid', preferred => 'markdown0' );
is( $select->{selected}, 'markdown0',
    "w/ invalid current format and active preference, preference is selected." );
is(
    scalar @{ $select->{items} },
    scalar @DW::Formats::active_formats,
    "w/ invalid current format, only active formats are offered."
);

$select = DW::Formats::select_items( current => 'html_casual1', preferred => 'markdown0' );
is( $select->{selected}, 'html_casual1',
    "w/ active current format and active preference, current is selected." );
is(
    scalar @{ $select->{items} },
    scalar @DW::Formats::active_formats,
    "w/ active current format, only active formats are offered."
);

$select = DW::Formats::select_items( current => 'html_casual0', preferred => 'markdown0' );
is( $select->{selected}, 'html_casual0',
    "w/ obsolete current format and active preference, current is selected." );
is(
    scalar @{ $select->{items} },
    1 + scalar @DW::Formats::active_formats,
    "w/ obsolete current format, that obsolete format is added to the list."
);
