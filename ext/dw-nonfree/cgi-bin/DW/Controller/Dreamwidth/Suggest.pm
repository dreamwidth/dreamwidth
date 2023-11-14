#!/usr/bin/perl
#
# DW::Controller::Dreamwidth::Suggest
#
# Controller for the site suggestion form.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org> -- original version
#      Jen Griffin <kareila@livejournal.com> -- controller conversion
#
# Copyright (c) 2009-2016 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Controller::Dreamwidth::Suggest;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use DW::Controller;

DW::Routing->register_string( "/site/suggest", \&suggestion_handler, app => 1 );

sub suggestion_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $fatal_err = sub {
        return DW::Template->render_template( 'error.tt', { message => $_[0] } );
    };

    # the community to post to:
    my $destination = LJ::load_user($LJ::SUGGESTIONS_COMM);
    $rv->{destination} = $destination;    # used in template

    # the user (which should also be an admin of the community)
    # to post the maintainer-only address as:
    my $suggestions_bot = LJ::load_user($LJ::SUGGESTIONS_USER);

    # verify proper configuration
    return $fatal_err->("This feature has not been configured for your site.")
        unless $destination
        && $suggestions_bot
        && $destination->is_community
        && $suggestions_bot->can_manage_other($destination);

    # make sure the remote user is OK to post
    my $remote = $rv->{remote};
    return $fatal_err->("Sorry, you must have confirmed your email to make a suggestion.")
        unless $remote->is_validated;
    return $fatal_err->("Sorry, suspended accounts can't make suggestions.")
        if $remote->is_suspended;

    my $r         = DW::Request->get;
    my $post_args = $r->post_args;
    my $errors    = DW::FormErrors->new;

    if ( $r->did_post ) {
        my @pieces = qw( title area summary description );
        my %ehtml_args;

        if ( $post_args->{post} ) {

            # verify that all fields are filled out:
            foreach my $field (@pieces) {
                if ( $post_args->{$field} ) {
                    $ehtml_args{$field} = LJ::ehtml( $post_args->{$field} );
                }
                else {
                    $errors->add_string( $field, "You need to fill out the $field section." );
                    $ehtml_args{$field} = '';
                }
            }

            # build out the post body including poll
            my $suggestion = DW::Template->template_string( "site/suggest_entry.tt",
                { post => \%ehtml_args, include_poll => 1 } );

            # We have all the pieces, so let's build the post for DW.
            # For this, we're going to post as the user (so they get
            # any comments, etc), and we're going to auto-tag it as
            # "bugzilla: unmigrated", so the suggestions maintainer
            # can find new/untagged posts when they want to.

            my ( $response, $response2 );    # for errors returned from postevent
            my $journalpost;

            unless ( $errors->exist ) {
                $journalpost = LJ::Protocol::do_request(
                    'postevent',
                    {
                        'ver'             => $LJ::PROTOCOL_VER,
                        'username'        => $remote->user,
                        'subject'         => $post_args->{title},
                        'event'           => $suggestion,
                        'usejournal'      => $destination->user,
                        'security'        => 'public',
                        'usejournal_okay' => 1,
                        'props'           => {
                            taglist          => 'bugzilla: unmigrated',
                            opt_noemail      => !$post_args->{email},
                            opt_preformatted => 1,
                        },
                        'tz' => 'guess',
                    },
                    \$response,
                    {
                        'nopassword' => 1,
                    }
                );
            }

            if ($journalpost) {

                # having built the post for public display, we now do
                # a second post containing the link to create the new bug
                # for the suggestion. we can't use $suggestion that we built,
                # because we need to use a different escaping function, but
                # that's okay, because we want to format this a little
                # differently anyway.

                my ( $ghi_subject, $ghi_desc, $ghi_args );

                $ghi_subject = LJ::eurl( $post_args->{title} );

                $ghi_desc = "Summary%3A%0D%0A%0D%0A";
                $ghi_desc .= LJ::eurl( $post_args->{summary} );
                $ghi_desc .= "%0D%0A%0D%0ADescription%3A%0D%0A%0D%0A";
                $ghi_desc .= LJ::eurl( $post_args->{description} );
                $ghi_desc .= "%0D%0A%0D%0ASuggested by%3A%0D%0A%0D%0A";
                $ghi_desc .= LJ::eurl( $remote->user );

                $ghi_args = "body=$ghi_desc&title=$ghi_subject";

                my $ghi_post = DW::Template->template_string( "site/suggest_ghi.tt",
                    { ghi_args => $ghi_args, title => $post_args->{title} } );

                # and we post that post to the community. (the suggestions_bot
                # account should have unmoderated posting ability, so that the
                # post is posted directly to the comm without having to go
                # through moderation.) for this post, we tag it as
                # "admin: unmigrated", so the suggestions maintainer can find
                # any/all unposted GitHub links.

                # get the user's timzeone and put it into +/-0800 format
                # if we can't figure it out, then just guess based on suggestions bot
                my ( $remote_tz_sign, $remote_tz_offset ) =
                    ( $remote->timezone =~ m/([+|-])?(\d+)/ );
                my $remote_tz =
                    defined $remote_tz_offset
                    ? sprintf( "%s%02d00", $remote_tz_sign || "+", $remote_tz_offset )
                    : "guess";

                LJ::Protocol::do_request(
                    'postevent',
                    {
                        'ver'             => $LJ::PROTOCOL_VER,
                        'username'        => $suggestions_bot->user,
                        'subject'         => $post_args->{title},
                        'event'           => $ghi_post,
                        'usejournal'      => $destination->user,
                        'security'        => 'private',
                        'usejournal_okay' => 1,
                        'props'           => {
                            taglist          => 'admin: unmigrated',
                            opt_preformatted => 1,
                        },
                        'tz' => $remote_tz,
                    },
                    \$response2,
                    {
                        'nopassword' => 1,
                    }
                );
            }

            # once all of that's done, let's tell the user it worked.
            # (or, if it didn't work, tell them why.)

            if ( $response || $response2 ) {
                $errors->add_string( '', LJ::Protocol::error_message( $response || $response2 ) );
            }

            unless ( $errors->exist ) {
                return DW::Controller->render_success(
                    'site/suggest.tt',
                    { commname => $destination->ljuser_display },
                    [
                        {
                            text_ml => ".success.link.another",
                            url     => "$LJ::SITEROOT/site/suggest"
                        },
                        {
                            text_ml => ".success.link.view",
                            url     => $destination->journal_base
                        },
                    ]
                );
            }

        }
        elsif ( $post_args->{preview} ) {

            # make preview: first preview the title and text as
            # it would show up in the entry later; we don't need
            # the poll in here, as the user can't influence it anyway
            $ehtml_args{$_} = LJ::html_newlines( LJ::ehtml( $post_args->{$_} ) ) foreach @pieces;

            my $suggestion = DW::Template->template_string( "site/suggest_entry.tt",
                { post => \%ehtml_args, include_poll => 0 } );

            $rv->{preview}    = 1;
            $rv->{suggestion} = $suggestion;

            if ($LJ::SPELLER) {
                my $s = new LJ::SpellCheck {
                    spellcommand => $LJ::SPELLER,
                    class        => "searchhighlight",
                };
                my $spellcheck_html = $s->check_html( \$suggestion );

                # unescape the <br />s for readability. All other HTML remains untouched.
                $spellcheck_html =~ s/&lt;br \/&gt;/<br \/>/g;

                $rv->{spellcheck} = $spellcheck_html;
            }
        }
    }

    $rv->{errors}   = $errors;
    $rv->{formdata} = $post_args;

    return DW::Template->render_template( 'site/suggest.tt', $rv );
}

1;
