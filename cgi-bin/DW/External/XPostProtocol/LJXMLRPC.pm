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
    return bless { protocolid => "LJ-XMLRPC", };
}

# internal xml-rpc call method.
# FIXME we should probably combine this with the similar method in
# DW::Worker::ContentImporter::LiveJournal, and move it to a general
# LJ-XMLRPC library class.
sub _call_xmlrpc {
    my ( $self, $xmlrpc, $mode, $req ) = @_;

    my $result = eval { $xmlrpc->call( "LJ.XMLRPC.$mode", $req ) };

    if ($result) {
        if ( $result->fault ) {

            # error from server
            return {
                success => 0,
                error   => $result->faultstring,
                code    => $result->faultcode eq '302' ? 'entry_deleted' : ''
            };
        }
        else {
            # success
            return {
                success => 1,
                result  => $result->result
            };
        }
    }
    else {
        # connection error
        return {
            success => 0,
            error   => LJ::Lang::ml( "xpost.error.connection", { url => $xmlrpc->proxy->endpoint } )
        };
    }
}

# does the authentication call.
# FIXME we should probably combine this with the similar method in
# DW::Worker::ContentImporter::LiveJournal, and move it to a general
# LJ-XMLRPC library class.
sub do_auth {
    my ( $self, $xmlrpc, $auth ) = @_;

    # if we've already set up an ljsession, just use it.
    if ( $auth->{ljsession} ) {
        return $auth;
    }

    # challenge/response for user validation
    if ( $auth->{auth_challenge} && $auth->{auth_response} ) {

        # if we already have a challenge and response, then do a login.

        my $challengecall = $self->_call_xmlrpc(
            $xmlrpc,
            "sessiongenerate",
            {
                ver            => 1,
                auth_method    => 'challenge',
                username       => $auth->{username},
                auth_challenge => $auth->{auth_challenge},
                auth_response  => $auth->{auth_response},
                expiration     => 'short'
            }
        );

        if ( $challengecall->{success} ) {
            $auth->{success}   = 1;
            $auth->{ljsession} = $challengecall->{result}->{ljsession};
            return $auth;
        }
        else {
            # just return the result hashref (with error)
            return $challengecall;
        }

    }
    else {
        my $challengecall = $self->_call_xmlrpc( $xmlrpc, 'getchallenge', {} );
        if ( $challengecall->{success} ) {
            my $challenge = $challengecall->{result}->{challenge};
            return {
                username       => $auth->{username},
                auth_challenge => $challenge,
                auth_response  => md5_hex( $challenge . $auth->{encrypted_password} ),
                success        => 1
            };
        }
        else {
            # just return the result hashref (with error)
            return $challengecall;
        }
    }
}

# public xml-rpc call method.
# FIXME we should probably combine this with the similar method in
# DW::Worker::ContentImporter::LiveJournal, and move it to a general
# LJ-XMLRPC library class.
sub call_xmlrpc {
    my ( $self, $proxyurl, $mode, $req, $auth ) = @_;

    my $xmlrpc = eval {
        XMLRPC::Lite->proxy(
            $proxyurl,
            agent   => "$LJ::SITENAME XPoster ($LJ::ADMIN_EMAIL)",
            timeout => 90,
        );
    };

    # connection error if no proxy
    return {
        success => 0,
        error   => LJ::Lang::ml( "xpost.error.connection", { url => $proxyurl } )
        }
        unless $xmlrpc;

    # get the auth information
    my $authresp = $self->do_auth( $xmlrpc, $auth );

    # fail if no auth available
    return $authresp unless $authresp->{success};

    # return the results of the call
    if ( $authresp->{ljsession} ) {

        # do an ljsession login
        $xmlrpc->transport->http_request->push_header( 'X-LJ-Auth', 'cookie' );
        $xmlrpc->transport->http_request->push_header(
            Cookie => "ljsession=" . $authresp->{ljsession} );

        return $self->_call_xmlrpc(
            $xmlrpc, $mode,
            {
                ver         => 1,
                auth_method => 'cookie',
                username    => $authresp->{username},
                %{ $req || {} }
            }
        );
    }
    else {
        # do a standalone challenge/response login.
        return $self->_call_xmlrpc(
            $xmlrpc, $mode,
            {
                ver            => 1,
                auth_method    => 'challenge',
                username       => $authresp->{username},
                auth_challenge => $authresp->{auth_challenge},
                auth_response  => $authresp->{auth_response},
                %{ $req || {} }
            }
        );
    }
}

# does a crosspost using the LJ XML-RPC protocol.  returns a hashref
# with success => 1 and url => the new url on success, or success => 0
# and error => the error message on failure.
sub crosspost {

    my ( $self, $extacct, $auth, $entry, $itemid, $delete ) = @_;

    # get the xml-rpc proxy and start the connection.
    # use the custom serviceurl if available, or the default using the hostname
    my $proxyurl = $extacct->serviceurl || "https://" . $extacct->serverhost . "/interface/xmlrpc";

    # load up the req.  if it's a delete, just set event as blank
    my $req;
    if ($delete) {
        $req = { event => '' };
    }
    else {
        # if it's a post or edit, fully populate the request.
        $req = $self->entry_to_req( $entry, $extacct, $auth );

        # FIXME: temporary hack to limit crossposts to one level, avoiding an infinite loop
        $req->{xpost} = 0;

        # are we disabling comments on the remote entry?
        my $disabling_comments = $extacct->owner->prop('opt_xpost_disable_comments') ? 1 : 0;

        # append the footer, if any
        my $footer_text = $self->create_footer( $entry, $extacct, $req->{props}->{opt_nocomments},
            $disabling_comments );

        # set the value for comments on the crossposted entry
        $req->{props}->{opt_nocomments} =
            $disabling_comments || $req->{props}->{opt_nocomments} || 0;

        $req->{event} = $req->{event} . $footer_text if $footer_text;
    }

    # get the correct itemid for edit
    $req->{itemid} = $itemid if $itemid;

    # crosspost, update, or delete
    my $xpost_result =
        $self->call_xmlrpc( $proxyurl, $itemid ? 'editevent' : 'postevent', $req, $auth );
    if ( $xpost_result->{success} ) {
        my $reference = { itemid => $xpost_result->{result}->{itemid} };
        if ( $extacct->recordlink ) {
            $reference->{url} = $xpost_result->{result}->{url};
        }
        return {
            success   => 1,
            url       => $xpost_result->{result}->{url},
            reference => $reference,
        };
    }
    else {
        return $xpost_result;
    }
}

# returns a hash of friends groups.
sub get_friendgroups {
    my ( $self, $extacct, $auth ) = @_;

    # use the custom serviceurl if available, or the default using the hostname
    my $proxyurl = $extacct->serviceurl || "https://" . $extacct->serverhost . "/interface/xmlrpc";

    my $xpost_result = $self->call_xmlrpc( $proxyurl, 'getfriendgroups', {}, $auth );
    if ( $xpost_result->{success} ) {
        return {
            success      => 1,
            friendgroups => $xpost_result->{result}->{friendgroups},
        };
    }
    else {
        return $xpost_result;
    }
}

# validates that the given server is running a LJ XML-RPC server.
# must be run in an eval block.  returns 1 on success, dies with an error
# message on failure.
sub validate_server {
    my ( $self, $proxyurl, $depth ) = @_;
    $depth ||= 1;

    # get the xml-rpc proxy and start the connection.
    my $xmlrpc = eval { XMLRPC::Lite->proxy( $proxyurl, timeout => 3 ); };

    # fail if no proxy
    return 0 unless $xmlrpc;

    # assume if we respond to LJ.XMLRPC.getchallenge, then we're good
    # on the server.
    # note:  this will die on a failed connection with an error.
    my $challengecall = eval { $xmlrpc->call("LJ.XMLRPC.getchallenge"); };
    if ( $challengecall && $challengecall->fault ) {

        # error from the server
        #die($challengecall->faultstring);
        return 0;
    }

    # error; URL probably wrong. Guess and try again
    if ($@) {
        return 0 if $depth > 2;
        eval "use URI;";
        return 0 if $@;

        my $uri = URI->new($proxyurl);

        my $path = $uri->path;

        # don't try to guess further if user actually gave us a path
        return 0 if $path && $path ne "/";

        # user didn't provide us a path, so let's guess
        $uri->path("/interface/xmlrpc");
        return $self->validate_server( $uri->as_string, $depth + 1 );
    }

    # otherwise success. (proxyurl has possibly been updated)
    return ( 1, $proxyurl );
}

# translates at Entry object into a request for crossposting
sub entry_to_req {
    my ( $self, $entry, $extacct, $auth ) = @_;

    # basic parts of the request
    my $req = {
        'subject'  => $entry->subject_text,
        'event'    => $self->clean_entry_text( $entry, $extacct ),
        'security' => $entry->security,
    };

    # usemask is either full access list, or custom groups.
    if ( $req->{security} eq 'usemask' ) {

        # if allowmask is 1, then it means full access list
        if ( $entry->allowmask == 1 ) {
            $req->{allowmask} = "1";
        }
        else {
            my $allowmask = $self->translate_allowmask( $extacct, $auth, $entry );
            if ($allowmask) {
                $req->{allowmask} = $allowmask;
            }
            else {
                $req->{security} = "private";
            }
        }
    }

    # check minsecurity if set
    if ( my $minsecurity = $extacct->options->{minsecurity} ) {
        if ( $minsecurity eq "private" ) {
            $req->{security} = "private";
        }
        elsif ( ( $minsecurity eq "friends" ) && ( $req->{security} eq "public" ) ) {
            $req->{security}  = 'usemask';
            $req->{allowmask} = 1;
        }
    }

    # set the date.
    my $eventtime = $entry->eventtime_mysql;
    $eventtime =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)/;
    $req->{year} = $1;
    $req->{mon}  = $2 + 0;
    $req->{day}  = $3 + 0;
    $req->{hour} = $4 + 0;
    $req->{min}  = $5 + 0;

    # properties
    my $entryprops = $entry->props;
    $req->{props} = {};

    # only bring over these properties
    for my $entrykey (
        qw ( adult_content current_coords current_location current_music opt_backdated opt_nocomments opt_noemail opt_screening used_rte pingback )
        )
    {
        $req->{props}->{$entrykey} = $entryprops->{$entrykey} if defined $entryprops->{$entrykey};
    }

    # always set opt_preformatted -- we pre-process all DW-style autoformatting,
    # markdown, etc. before crossposting.
    $req->{props}->{opt_preformatted} = 1;

    # remove html from current location
    if ( $req->{props}->{current_location} ) {
        $req->{props}->{current_location} = LJ::strip_html( $req->{props}->{current_location} );
    }

# the taglist entryprop stored in the DB is not canonical, and may be truncated if there are too many tags
# so let's grab the actual tag items and rebuild a string
    my @tags = $entry->tags;
    $req->{props}->{taglist} = join( ', ', @tags );

    # and regenerate this one from data
    $req->{props}->{picture_keyword} = $entry->userpic_kw;

    # figure out what current_moodid and current_mood to pass to the crossposted entry
    my ( $siteid, $moodid, $mood ) =
        ( $extacct->siteid, $entryprops->{current_moodid}, $entryprops->{current_mood} );
    my $external_moodid;
    if ( $moodid && $mood ) {

        # use the mood text that was given
        $req->{props}->{current_mood} = $mood;

        # try these in order:
        # 1. use the mood icon that matches the given mood id
        # 2. use the mood icon that matches the given mood text
        # 3. don't use an icon
        $external_moodid = DW::Mood->get_external_moodid( siteid => $siteid, moodid => $moodid );
        unless ($external_moodid) {
            $external_moodid = DW::Mood->get_external_moodid( siteid => $siteid, mood => $mood );
        }
    }
    elsif ($moodid) {

        # try these in order:
        # 1. use the mood icon that matches the given mood id
        # 2. use the mood text that matches the given mood id (no icon)
        $external_moodid = DW::Mood->get_external_moodid( siteid => $siteid, moodid => $moodid );
        unless ($external_moodid) {
            $req->{props}->{current_mood} = DW::Mood->mood_name($moodid);
        }
    }
    elsif ($mood) {

        # try these in order:
        # 1. use the mood icon that matches the given mood text
        # 2. use the mood text that was given (no icon)
        $external_moodid = DW::Mood->get_external_moodid( siteid => $siteid, mood => $mood );
        unless ($external_moodid) {
            $req->{props}->{current_mood} = $mood;
        }
    }
    $req->{props}->{current_moodid} = $external_moodid if $external_moodid;

    # and set the useragent - FIXME put this somewhere else?
    $req->{props}->{useragent} = "Dreamwidth Crossposter";

    # do any per-site preprocessing
    $req = $extacct->externalsite->pre_crosspost_hook($req)
        if $extacct->externalsite;

    return $req;
}

# translates the given allowmask to
sub translate_allowmask {
    my ( $self, $extacct, $auth, $entry ) = @_;

    my $result = $self->get_friendgroups( $extacct, $auth );
    return 0 unless $result->{success};

    # make a name/id map for the extgroups.
    my %namemap;
    foreach my $extgroup ( @{ $result->{friendgroups} || [] } ) {
        $namemap{ $extgroup->{name} } = $extgroup->{id};
    }

    # get the trusted group id list from the given allowmask
    my %selected_group_ids = ( map { $_ => 1 } grep { $entry->allowmask & ( 1 << $_ ) } 1 .. 60 );
    return 0 unless keys %selected_group_ids;

    # get all of the available groups for the poster
    my $groups = $entry->poster->trust_groups || {};
    return 0 unless keys %$groups;

    # now try to map them
    my $extmask = 0;
    foreach my $groupid ( keys %$groups ) {

        # skip the groups not selected for this entry
        next unless $selected_group_ids{$groupid};

        # if there is a matching group name on the external
        # account, then add its group id to the mask.
        if ( my $id = $namemap{ $groups->{$groupid}->{groupname} } ) {
            $extmask |= ( 1 << $id );
        }
    }

    return $extmask;
}

# cleans the entry text for crossposting
# overrides default implementation for use with LJ-based sites
sub clean_entry_text {
    my ( $self, $entry, $extacct ) = @_;

    my $event_text = $entry->event_raw;

    # pre-process all of our own formatting, but preserve <lj user=...> and
    # <lj-cut> tags, since we're posting to a site that understands them.
    my $clean_opts = {
        editor               => $entry->prop('editor'),
        preformatted         => $entry->prop('opt_preformatted'),
        preserve_lj_tags_for => $extacct->externalsite,
        to_external_site     => 1,
    };
    LJ::CleanHTML::clean_event( \$event_text, $clean_opts );

    # clean up any embedded objects
    LJ::EmbedModule->expand_entry( $entry->journal, \$event_text, expand_full => 1 );

    # remove polls, then return the text
    return $self->scrub_polls($event_text);
}

sub protocolid {
    my $self = shift;
    return $self->{protocolid};
}

# hash the password in a protocol-specific manner
sub encrypt_password {
    my ( $self, $password ) = @_;

    if ($password) {
        return md5_hex($password);
    }
    else {
        # don't hash blank passwords
        return $password;
    }
}

# get a challenge for this server.  returns 0 on failure.
sub challenge {
    my ( $self, $extacct ) = @_;

    # get the xml-rpc proxy and start the connection.
    # use the custom serviceurl if available, or the default using the hostname
    my $proxyurl = $extacct->serviceurl || "https://" . $extacct->serverhost . "/interface/xmlrpc";
    my $xmlrpc   = eval { XMLRPC::Lite->proxy( $proxyurl, timeout => 3 ); };
    return 0 unless $xmlrpc;

    my $challengecall = eval { $xmlrpc->call("LJ.XMLRPC.getchallenge"); };
    return 0 unless $challengecall;

    if ( $challengecall->fault ) {

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

# returns the options for this protocol
sub protocol_options {
    my ( $self, $extacct, $POST ) = @_;
    my $option = {
        type        => 'select',
        description => BML::ml('.protocol.ljxmlrpc.minsecurity.desc'),
        opts        => {
            id       => 'minsecurity',
            name     => 'minsecurity',
            selected => $POST ? $POST->{minsecurity}
            : ( $extacct && $extacct->options && $extacct->options->{minsecurity} )
            ? $extacct->options->{minsecurity}
            : 'public',
        },
        options => [
            'public',  BML::ml('.protocol.ljxmlrpc.minsecurity.public'),
            'friends', BML::ml('.protocol.ljxmlrpc.minsecurity.friends'),
            'private', BML::ml('.protocol.ljxmlrpc.minsecurity.private'),
        ],
    };
    my @return_value = ($option);
    return @return_value;
}

1;
