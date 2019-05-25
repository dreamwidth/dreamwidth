#!/usr/bin/perl
#
# LJ::Global::Secrets
#
# This module provides a list of definitions for
# items in %LJ::SECRETS
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;

package LJ::Secrets;
our %secret;

# Potential flags
#   desc -- english description, only showed in internal tools
#   required -- requred for basic site operation, v.s. additional features
#
#   rec_len -- recommended length, implies rec_min_len/rec_max_len
#   rec_min_len -- recommended minumum length
#   rec_max_len -- recommended maximum length
#
#   len -- required len, implies min_len/max_len
#   min_len -- required minimim length
#   max_len -- required maximum length

$secret{invite_img_auth} = {
    desc    => "Auth code for invite code status images",
    rec_len => 64,
};

$secret{oauth_consumer} = {
    desc    => "Sign consumer token to make secret token",
    rec_len => 64,
};

$secret{oauth_access} = {
    desc    => "Sign access token to make secret token",
    rec_len => 64,
};

$secret{oauth_request} = {
    desc    => "Sign request token to make secret token",
    rec_len => 64,
};

