# t/user-editor-prefs.t
#
# Stored default-format preferences for entries and comments. A preference for
# the retired rte0 format has to be read as something sensible, but must never
# be rewritten: the stored value is left exactly as it was.
#
# Authors:
#      Mark Smith <mark@qq.is>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 10;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $u = temp_user();

# Set the stored value directly, the way an account from before the change has it.
sub stored {
    my ( $prop, $value ) = @_;
    $u->set_prop( $prop => $value );
    $u->clear_prop_cache if $u->can('clear_prop_cache');
    return $u;
}

stored( entry_editor2 => 'rte0' );
is( $u->entry_editor2,             'rte1', 'an rte0 entry preference is read as rte1' );
is( $u->raw_prop('entry_editor2'), 'rte0', '...without rewriting the stored value' );

stored( comment_editor => 'rte0' );
is( $u->comment_editor, $DW::Formats::default_format,
    'an rte0 comment preference is read as the default format' );
is( $u->raw_prop('comment_editor'), 'rte0', '...without rewriting the stored value' );

stored( comment_editor => 'rte1' );
is( $u->comment_editor, $DW::Formats::default_format,
    'an rte1 comment preference is read as the default format' );
is( $u->raw_prop('comment_editor'), 'rte1', '...without rewriting the stored value' );

stored( comment_editor => 'markdown0' );
is( $u->comment_editor, 'markdown0', 'a plain comment preference is used as stored' );

# Other obsolete formats are still upgraded in place, as before.
stored( entry_editor2 => 'html_casual0' );
is( $u->entry_editor2,             'html_casual1', 'an obsolete casual preference is upgraded' );
is( $u->raw_prop('entry_editor2'), 'html_casual1', '...and that upgrade is stored' );

stored( entry_editor2 => 'rte1' );
is( $u->entry_editor2, 'rte1', 'an rte1 entry preference is used as stored' );
