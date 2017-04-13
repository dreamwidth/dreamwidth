#!/usr/bin/perl
#
# DW::BlobStore::S3
#
# Library for storing blobs in S3.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BlobStore::S3;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );


1;