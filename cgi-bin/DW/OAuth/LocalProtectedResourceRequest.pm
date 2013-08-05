#!/usr/bin/perl
#
# DW::OAuth::LocalProtectedResourceRequest
#
# Add some extension specs.
# 
#   Request Body Hash:
#       http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/oauth-bodyhash.html
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::OAuth::LocalProtectedResourceRequest;
use warnings;
use strict;
use base 'Net::OAuth::ProtectedResourceRequest';

__PACKAGE__->add_optional_message_params(qw/body_hash/);

1;