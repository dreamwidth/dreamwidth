#!/usr/bin/perl
#
# DW::External::XPostProtocol::LJXMLRPC
#
# LJ XML-RPC client for crossposting.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::External::XPostProtocol::LJXMLRPC;
use base 'DW::External::XPostProtocol';
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);  
use XMLRPC::Lite;

# create a new instance of LJXMLRPC
sub instance {
    my ($class) = @_;
    my $acct = $class->_skeleton();
    return $acct;
}
*new = \&instance;

sub _skeleton {
    my ($class) = @_;
    # starts out as a skeleton and gets loaded in over time, as needed:
    return bless {
        protocolid  => "LJ-XMLRPC",
    };
}

# does a crosspost using the LJ XML-RPC protocol.  returns a hashref
# with success => 1 and url => the new url on success, or success => 0
# and error => the error message on failure.
sub crosspost {
    my ($self, $extacct, $auth, $entry, $itemid, $delete) = @_;

    # get the xml-rpc proxy and start the connection.
    # use the custom serviceurl if available, or the default using the hostname
    my $proxyurl = $extacct->serviceurl || "http://" . $extacct->serverhost . "/interface/xmlrpc";
    

    my $xmlrpc = eval { XMLRPC::Lite->proxy($proxyurl); };
    # connection error if no proxy
    return {
        success => 0,
        error => LJ::Lang::ml("xpost.error.connection", { url => $proxyurl })
    } unless $xmlrpc;

    # challenge/response for user validation
    my $challenge;
    my $response;
    if ($auth->{auth_challenge} && $auth->{auth_response}) {
        # just use these.
        $challenge = $auth->{auth_challenge};
        $response = $auth->{auth_response};
    } else {
        my $challengecall = eval { $xmlrpc->call("LJ.XMLRPC.getchallenge"); };

        if ($challengecall) {
            if ($challengecall->fault) {
                # error from the server
                return {
                    success => 0,
                    error => $challengecall->faultstring
                }
            } else {
                # success
                $challenge = $challengecall->result->{challenge};
            }
        } else {
            # connection error
            return {
                success => 0,
                error => LJ::Lang::ml("xpost.error.connection", { url => $proxyurl })
            } 
        }
    
        # create the response to the challenge
        $response = md5_hex($challenge . $auth->{encrypted_password});  
    }
    
    # load up the req.  if it's a delete, just set event as blank
    my $req;
    if ($delete) {
        $req = { event => '' };
    } else {
        # if it's a post or edit, fully populate the request.
        $req = $self->entry_to_req($entry);
        # handle disable comments
        if ($extacct->owner->prop('opt_xpost_disable_comments')) {
            if ($req->{props}->{opt_nocomments}) {
                $req->{event} = $req->{event} . "\n\n" . LJ::Lang::ml("xpost.redirect", { postlink => $entry->url });
            } else {
                $req->{event} = $req->{event} . "\n\n" . LJ::Lang::ml("xpost.redirect.comment", { postlink => $entry->url });
                $req->{props}->{opt_nocomments} = 1;
            }
        }
    }
    
    # update the message with the appropriate remote settings
    $req->{username} = $extacct->username;
    $req->{auth_method} = 'challenge';
    $req->{auth_challenge} = $challenge;
    $req->{auth_response} = $response;

    # get the correct itemid for edit
    $req->{itemid} = $itemid if $itemid;

    # crosspost, update, or delete
    my $xpostcall = eval { $xmlrpc->call($itemid ? 'LJ.XMLRPC.editevent' : 'LJ.XMLRPC.postevent', $req) };

    if ($xpostcall) {
        if ($xpostcall->fault) {
            # error from server
            return {
                success => 0,
                error => $xpostcall->faultstring
            }
        } else {
            # success
            return {
                success => 1,
                url => $xpostcall->result->{url},
                reference => $xpostcall->result->{itemid}
            }
        }
    } else {
        # connection error
        return {
            success => 0,
            error => LJ::Lang::ml("xpost.error.connection", { url => $proxyurl })
        } 
    }

}

# validates that the given server is running a LJ XML-RPC server.
# must be run in an eval block.  returns 1 on success, dies with an error
# message on failure.
sub validate_server {
    my ($self, $proxyurl) = @_;

    # get the xml-rpc proxy and start the connection.
    my $xmlrpc = eval { XMLRPC::Lite->proxy($proxyurl); };
    # fail if no proxy
    return 0 unless $xmlrpc;

    # assume if we respond to LJ.XMLRPC.getchallenge, then we're good
    # on the server.
    # note:  this will die on a failed connection with an error.
    my $challengecall = $xmlrpc->call("LJ.XMLRPC.getchallenge");
    if ($challengecall->fault) {
        # error from the server
        #die($challengecall->faultstring);
        return 0;
    }

    # otherwise success.  
    return 1;
}

# translates at Entry object into a request for crossposting
sub entry_to_req {
    my ($self, $entry) = @_;

    # basic parts of the request
    my $req = {
        'subject' => $entry->subject_text,
        'event' => $self->clean_entry_text($entry),
        'security' => $entry->security,
    };

    # if set to usemask, we really can only go general friends-lock,
    # since it's not like our friends groups will match
    $req->{allowmask} = "1" if $req->{security} eq 'usemask';

    # set the date.
    my $eventtime = $entry->eventtime_mysql;
    $eventtime =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)/;
    $req->{year} = $1;
    $req->{mon} = $2+0;
    $req->{day} = $3+0;
    $req->{hour} = $4+0;
    $req->{min} = $5+0;

    # properties
    my $entryprops = $entry->props;
    $req->{props} = {};
    # only bring over these properties
    for my $entrykey (qw ( adult_content current_coords current_location current_mood current_music opt_backdated opt_nocomments opt_noemail opt_preformatted opt_screening picture_keyword qotdid taglist used_rte pingback )) {
        $req->{props}->{$entrykey} = $entryprops->{$entrykey} if defined $entryprops->{$entrykey};
    }

    # and set the useragent - FIXME put this somewhere else?
    $req->{props}->{useragent} = "Dreamwidth Crossposter";

    return $req;
}

sub protocolid {
    my $self = shift;
    return $self->{protocolid};
}

# hash the password in a protocol-specific manner
sub encrypt_password { 
    my ($self, $password) = @_;

    if ($password) {
        return md5_hex($password);  
    } else {
        # don't hash blank passwords
        return $password;
    }
}

# get a challenge for this server.  returns 0 on failure.
sub challenge { 
    my ($self, $extacct) = @_;

    # get the xml-rpc proxy and start the connection.
    # use the custom serviceurl if available, or the default using the hostname
    my $proxyurl = $extacct->serviceurl || "http://" . $extacct->serverhost . "/interface/xmlrpc";
    my $xmlrpc = eval { XMLRPC::Lite->proxy($proxyurl); };
    return 0 unless $xmlrpc;

    my $challengecall = eval { $xmlrpc->call("LJ.XMLRPC.getchallenge"); };
    return 0 unless $challengecall;

    if ($challengecall->fault) {
        # error from the server
        #die($challengecall->faultstring);
        return 0;
    }

    # otherwise return the challenge
    return $challengecall->result->{challenge};
}

# checks to see if this account supports challenge/response authentication
sub supports_challenge { 
    return 1;
}

1;
