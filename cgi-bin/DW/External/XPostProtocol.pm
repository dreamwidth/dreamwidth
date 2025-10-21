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
LJ::ModuleLoader->require_subclasses("DW::External::XPostProtocol");

my %protocols;
eval { $protocols{"lj"} = DW::External::XPostProtocol::LJXMLRPC->new; };

# returns the given protocol, if configured.
sub get_protocol {
    my ( $class, $protocol ) = @_;

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
        error   => "Crossposting not implemented for this protocol."
    };
}

# cleans the entry text for crossposting
# default implementation; does a full clean of the entry text.
sub clean_entry_text {
    my ( $self, $entry ) = @_;

    my $event_text = $entry->event_text;

    # clean up any embedded objects
    LJ::EmbedModule->expand_entry( $entry->journal, \$event_text, expand_full => 1 );

    # remove polls, then return the text
    return $self->scrub_polls($event_text);
}

# replaces <poll> tags with a link to the original poll
sub scrub_polls {
    my ( $self, $entry_text ) = @_;

    # taken more or less from cgi-bin/LJ/Feed.pm
    while ( $entry_text =~ /<(?:lj-)?poll-(\d+)>/g ) {
        my $pollid = $1;

        my $name = LJ::Poll->new($pollid)->name;
        if ($name) {
            LJ::Poll->clean_poll( \$name );
        }
        else {
            $name = "#$pollid";
        }

        my $view_poll = LJ::Lang::ml( "xpost.poll.view", { name => $name } );

        $entry_text =~
s!<(lj-)?poll-$pollid>!<div><a href="$LJ::SITEROOT/poll/?id=$pollid">$view_poll</a></div>!g;
    }
    return $entry_text;
}

# creates the footer
sub create_footer {
    my ( $self, $entry, $extacct, $local_nocomments, $disabling_remote_comments ) = @_;

    # are we adding a footer?
    my $xpostfootprop =
          $extacct->owner->prop('crosspost_footer_append')
        ? $extacct->owner->prop('crosspost_footer_append')
        : "D";    # assume old behavior if undefined

    if ( ( $xpostfootprop eq "A" ) || ( ( $xpostfootprop eq "D" ) && $disabling_remote_comments ) )
    {
        # get the default custom footer text
        my $custom_footer_template;
        if ($local_nocomments) {
            $custom_footer_template = $extacct->owner->prop('crosspost_footer_nocomments')
                || $extacct->owner->prop('crosspost_footer_text');
        }
        else {
            $custom_footer_template = $extacct->owner->prop('crosspost_footer_text');
        }

        if ($custom_footer_template) {
            return $self->create_footer_text( $entry, $custom_footer_template );
        }
        else {
            # did we disable comments on the local entry? tweak language string to match
            my $footer_text_redirect_key =
                $local_nocomments ? 'xpost.redirect' : 'xpost.redirect.comment2';

            return "\n\n"
                . LJ::Lang::ml( $footer_text_redirect_key,
                { postlink => $entry->url, openidlink => "$LJ::SITEROOT/openid/" } );
        }
    }
    elsif (( $xpostfootprop eq "N" )
        || ( ( $xpostfootprop eq "D" ) && ( !$disabling_remote_comments ) ) )
    {
        return "";
    }
    else {
        # fallthrough. shouldn't get here, but in case we do for
        # some crazy reason, let's assume the old behavior.
        my $footer_text_redirect_key =
            $local_nocomments ? 'xpost.redirect' : 'xpost.redirect.comment2';

        return "\n\n"
            . LJ::Lang::ml( $footer_text_redirect_key,
            { postlink => $entry->url, openidlink => "$LJ::SITEROOT/openid/" } );
    }
}

# creates the footer text
sub create_footer_text {
    my ( $self, $entry, $footer_text ) = @_;

    my $url           = $entry->url;
    my $comment_url   = $entry->url( anchor => "comments" );
    my $reply_url     = $entry->reply_url;
    my $comment_image = $entry->comment_imgtag;

    # note:  if you change any of these, be sure to change the preview
    # javascript in DW/Setting/XPostAccounts.pm, too.
    $footer_text =~ s/%%url%%/$url/gi;
    $footer_text =~ s/%%reply_url%%/$reply_url/gi;
    $footer_text =~ s/%%comment_url%%/$comment_url/gi;
    $footer_text =~ s/%%comment_image%%/$comment_image/gi;
    $footer_text = "\n\n" . $footer_text;

    return $footer_text;
}

# validates that the given server is running the appropriate protocol.
# must be run in an eval block.  returns ( 1, $validurl ) on success, 0 on failure
sub validate_server { return ( 1, $_[0] ); }

# hash the password in a protocol-specific manner
sub encrypt_password {
    my ( $self, $password ) = @_;

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

# returns the options for this protocol
sub protocol_options {
    return ();
}

1;
