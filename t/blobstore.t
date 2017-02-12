# t/blobstore.t
#
# Test some BlobStore functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

plan tests => 12;

use DW::BlobStore;

my $test = eval { DW::BlobStore::ensure_namespace_is_valid( "succeeds" ); return 1; };
ok( $test == 1 && ! $@, "Namespace checker failed" );

eval { DW::BlobStore::ensure_namespace_is_valid( "!fails" ); return 1; };
ok( $@, "Namespace checker failed to fail" );

my $test2 = eval { DW::BlobStore::ensure_key_is_valid( "yes/path/ok" ); return 1; };
ok( $test == 1 && ! $@, "Key checker failed" );

eval { DW::BlobStore::ensure_key_is_valid( "alsofails" ); return 1; };
ok( $@, "Key checker failed to fail" );

eval { DW::BlobStore::ensure_key_is_valid( "!fails" ); return 1; };
ok( $@, "Key checker failed to fail" );

my $fileref = \"file contents";

# Check for non-existant file
ok( DW::BlobStore->exists( test => 'no/exist' ) == 0, "Found file that doesn't exist" );
ok( DW::BlobStore->delete( test => 'no/exist' ) == 0, "Deleter deleted something?!" );

# Now create a file
ok( DW::BlobStore->store( test => 'yes/exist', $fileref ) == 1, "Failed to store" );
ok( DW::BlobStore->exists( test => 'yes/exist' ) == 1, "Failed to find extant file" );
ok( ${DW::BlobStore->retrieve( test => 'yes/exist' )} eq $$fileref, "File contents wrong" );

# Now delete and ensure it's gone
ok( DW::BlobStore->delete( test => 'yes/exist' ) == 1, "Deleter failed to delete" );
ok( DW::BlobStore->exists( test => 'yes/exist' ) == 0, "Found file that doesn't exist" );

1;
