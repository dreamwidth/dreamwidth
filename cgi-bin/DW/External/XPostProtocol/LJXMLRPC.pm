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
        $req = $self->entry_to_req($entry, $extacct);
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
    $req->{ver} = 1;

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
    my ($self, $entry, $extacct) = @_;

    # basic parts of the request
    my $req = {
        'subject' => $entry->subject_text,
        'event' => $self->clean_entry_text($entry, $extacct),
        'security' => $entry->security,
    };

    # usemask is either full access list, or custom groups.
    if ($req->{security} eq 'usemask') {
        # if allowmask is 1, then it means full access list
        if ($entry->allowmask == 1) {
            $req->{allowmask} = "1";
        } else {
            # otherwise, it's a custom group.  just make it private for now.
            $req->{security} = "private";
        }
    }
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
    # the current_mood above handles custom moods; for standard moods we
    # use current_moodid
    if ($entryprops->{current_moodid}) {
        my $mood = LJ::mood_name($entryprops->{current_moodid});
        $req->{props}->{current_mood} = $mood if $mood;
    }

    # and set the useragent - FIXME put this somewhere else?
    $req->{props}->{useragent} = "Dreamwidth Crossposter";
    
    # do any per-site preprocessing
    $req = $extacct->externalsite->pre_crosspost_hook( $req );

    return $req;
}

# cleans the entry text for crossposting
# overrides default implementation for use with LJ-based sites
sub clean_entry_text {
    my ($self, $entry, $extacct) = @_;

    my $event_text = $entry->event_raw;

    # clean up lj-tags
    $self->clean_lj_tags(\$event_text, $extacct);
    
    # clean up any embedded objects
    LJ::EmbedModule->expand_entry($entry->journal, \$event_text, expand_full => 1);
    
    # remove polls, then return the text
    return $self->scrub_polls($event_text);
}

# cleans up lj-tags for crossposting
sub clean_lj_tags {
    my ($self, $entry_text_ref, $extacct) = @_;
    my $p = HTML::TokeParser->new($entry_text_ref);
    my $newdata = "";

    # this is mostly gakked from cgi-bin/cleanhtml.pl

    # go throught each token.
  TOKEN:
    while (my $token = $p->get_token) {
        my $type = $token->[0];
        # See if this tag should be treated as an alias
        
        if ($type eq "S") {
            my $tag = $token->[1];
            my $hash  = $token->[2]; # attribute hashref
            my $attrs = $token->[3]; # attribute names, in original order

            # we need to rewrite cut tags as lj-cut
            if ($tag eq "cut") {
                $tag = "lj-cut";
                
                # for tags like <name/>, pretend it's <name> and reinsert the slash later
                my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
                $slashclose = 1 if delete $hash->{'/'};
                
                # spit it back out
                $newdata .= "<$tag";
                # output attributes in original order
                foreach (@$attrs) {
                    $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                        if exists $hash->{$_};
                }
                $newdata .= " /" if $slashclose;
                $newdata .= ">";
            } elsif ($tag eq 'lj' || $tag eq 'user') {
                my $user = $hash->{user} = exists $hash->{name} ? $hash->{name} :
                    exists $hash->{user} ? $hash->{user} :
                    exists $hash->{comm} ? $hash->{comm} : undef;
                
                # allow external sites
                if (my $site = $hash->{site}) {
                    # try to load this user@site combination
                    if (my $ext_u = DW::External::User->new( user => $user, site => $site )) {
                        # if the sites match, make this into a standard 
                        # lj user tag
                        if ($ext_u->site == $extacct->externalsite) {
                            $newdata .= "<lj user=\"$user\">";
                        } else {
                            $newdata .= $ext_u->ljuser_display(no_ljuser_class => 1);
                        }
                    } else {
                        # if we hit the else, then we know that this user doesn't appear
                        # to be valid at the requested site
                        $newdata .= "<b>[Bad username or site: " .
                            LJ::ehtml( LJ::no_utf8_flag( $user ) ) . " @ " .
                            LJ::ehtml( LJ::no_utf8_flag( $site ) ) . "]</b>";
                    }
                    # failing that, no site, use the local behavior
                } elsif (length $user) {
                    my $orig_user = $user;
                    $user = LJ::canonical_username($user);
                    if (length $user) {
                        $newdata .= LJ::ljuser( $user, { no_ljuser_class => 1 });
                    } else {
                        $orig_user = LJ::no_utf8_flag($orig_user);
                        $newdata .= "<b>[Bad username: " . LJ::ehtml($orig_user) . "]</b>";
                    }
                } else {
                    $newdata .= "<b>[Unknown LJ tag]</b>";
                }
            } else {
                # if no change was necessary
                $newdata .= $token->[4];
                next TOKEN;
            }
        }
        elsif ($type eq "E") {
            if ($token->[1] eq "cut") {
                $newdata .= "</lj-cut>";
            } else {
                $newdata .= $token->[2];
            }
        }
        elsif ($type eq "D") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "T") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "PI") {
            $newdata .= $token->[2];
        }
    } # end while
    
    $$entry_text_ref = $newdata;
    return undef;
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
