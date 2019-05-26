#
# Hooks to allow posting to Changelog.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::Changelog;

use strict;
use LJ::Hooks;

LJ::Hooks::register_hook(
    'post_noauth',
    sub {
        my $req = shift;

        # enable or not
        return 0 unless $LJ::CHANGELOG{enabled};

        # the user must be posting TO the changelog journal and the
        # username must be in the allow list
        return 0 unless $req->{usejournal} eq $LJ::CHANGELOG{community};
        return 0 unless grep { $_ eq $req->{username} } @{ $LJ::CHANGELOG{allowed_posters} || [] };

        # we also enforce that the IP the request is coming from be one of
        # some small list of IPs
        my $ip = BML::get_remote_ip();
        return 0 unless grep { $_ eq $ip } @{ $LJ::CHANGELOG{allowed_ips} || [] };

        # looks good
        return 1;
    }
);

1;
