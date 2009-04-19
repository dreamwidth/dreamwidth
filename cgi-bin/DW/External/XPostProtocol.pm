#!/usr/bin/perl
#
# DW::External::XPostProtocol
#
# Base class for crosspost protocols.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::External::XPostProtocol;
use strict;
use warnings;
use LJ::ModuleLoader;
LJ::ModuleLoader->autouse_subclasses("DW::External::XPostProtocol");

my %protocols;
$protocols{"lj"} = DW::External::XPostProtocol::LJXMLRPC->new;

# returns the given protocol, if configured.
sub get_protocol {
    my ($class, $protocol) = @_;
    
    return $protocols{$protocol};
}

# returns a map of all available protocols.
sub get_all_protocols {
    return %protocols;
}


# instance methods for subclasses.

# does a crosspost using this protocol.  implementations should return a hash 
# reference with success => 1 and url => the new post url on success, 
# success => 0 and error => the error message on failure.
#
# usage:  $protocol->crosspost($extacct, $auth, $entry, $itemid, $delete);
sub crosspost { 
    return {
        success => 0,
        error => "Crossposting not implemented for this protocol."
    }
 }

# cleans the entry text for crossposting
# default implementation; does a full clean of the entry text.
sub clean_entry_text {
    my ($self, $entry) = @_;

    return $self->scrub_polls($entry->event_text);
}

# replaces <poll> tags with a link to the original poll
sub scrub_polls {
    my ($self, $entry_text) = @_;
    
    # taken more or less from cgi-bin/ljfeed.pl
    while ($entry_text =~ /<(?:lj-)?poll-(\d+)>/g) {
        my $pollid = $1;
        
        my $name = LJ::Poll->new($pollid)->name;
        if ($name) {
            LJ::Poll->clean_poll(\$name);
        } else {
            $name = "#$pollid";
        }

        my $view_poll = LJ::Lang::ml("xpost.poll.view", { name => $name });
        
        $entry_text =~ s!<(lj-)?poll-$pollid>!<div><a href="$LJ::SITEROOT/poll/?id=$pollid">$view_poll</a></div>!g;
    }
    return $entry_text;
}

# validates that the given server is running the appropriate protocol.
# must be run in an eval block.  returns 1 on success, 0 on failure
sub validate_server { 1 }

# hash the password in a protocol-specific manner
sub encrypt_password { 
    my ($self, $password) = @_;
    
    # default implementation; just return the password in plaintext
    return $password;
}

# get a challenge for this protocol
sub challenge { 
    # don't support challenges by default.  subclasses will have to override.
    return 0;
}

# checks to see if this account supports challenge/response authentication
sub supports_challenge { 
    # don't support challenges by default.  subclasses will have to override.
    return 0;
}

1;
