#!/usr/bin/perl
#
# DW::Controller::Poll
#
# This controller is for the poll feature
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2009-2024 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Poll;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::Poll;

DW::Routing->register_string( '/poll',  \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/poll/', \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/poll/create', \&create_handler, app => 1 );

sub index_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $form   = $r->did_post ? $r->post_args : $r->get_args;
    my $remote = $rv->{remote};

    # answers to checkbox questions are null-separated sequences
    # since our inout correctness check rules out nulls, we change them
    # to commas here rather than inside LJ::Poll::submit() .
    foreach ( values %$form ) {
        s/\0/,/g;
    }
    unless ( LJ::text_in($form) ) {

        #    $body = "<?badinput?>";
        return;
    }

    my $pollid = ( $form->{'id'} || $form->{'pollid'} ) + 0;

    unless ($pollid) {
        return $r->redirect("$LJ::SITEROOT/poll/create");
    }

    my $poll = LJ::Poll->new($pollid);

    return error_ml('/poll/index.tt.pollnotfound') unless ( $poll && $poll->valid );

    my $u = $poll->journal;

    my $mode = "";
    $mode = $form->{'mode'}
        if ( defined $form->{'mode'} && $form->{'mode'} =~ /(enter|results|ans|clear)/ );

    # Handle opening and closing of polls
    # We do this first because a closed poll will alter how a poll is displayed
    if ( $poll->is_owner($remote) || $remote && $remote->can_manage($u) ) {
        if ( defined $form->{'mode'} && $form->{'mode'} =~ /(close|open)/ ) {
            $mode = $form->{'mode'};
            $poll->close_poll if ( $mode eq 'close' );
            $poll->open_poll  if ( $mode eq 'open' );
            $mode = 'results';
        }
    }

    # load the item being shown
    my $entry = $poll->entry;
    return error_ml('/poll/index.tt.error.postdeleted') unless ($entry);

    return error_ml('/poll/index.tt.error.cantview') unless ( $entry->visible_to($remote) );

    # bundle variables to be passed to the template
    my $vars = {
        remote    => $remote,
        u         => $u,
        poll      => $poll,
        pollid    => $pollid,
        poll_form => $form,
        mode      => $mode,
        entry     => $entry,
    };

    if ( defined $form->{'poll-submit'} && $r->did_post ) {
        my $error;
        my $error_code = LJ::Poll->process_submission( $form, \$error );
        if ($error) {
            $vars->{error}      = $error;
            $vars->{error_code} = $error_code;
        }
        else {
            return $r->redirect( $entry->url( style_opts => LJ::viewing_style_opts(%$form) ) );
        }
    }

    return DW::Template->render_template( 'poll/index.tt', $vars );
}

sub create_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r        = $rv->{r};
    my $get      = $r->get_args;
    my $post     = $r->post_args;
    my $remote   = $rv->{remote};
    my $vars     = { remote => $remote };
    my $ml_scope = "/poll/create.tt";

    # some rules used for error checking
    my %RULES = (
        "elements" => {
            "max" => 255,    # maximum total number of elements allowed
        },
        "items" => {
            "min"       => 1,       # minimum number of options
            "start"     => 5,       # number of items shown at start
            "max"       => 255,     # max number of options
            "maxlength" => 1000,    # max length of an option's textual value, min is implicitly 0
            "more"      => 5,       # number of items to add when requesting more
        },
        "question" => {
            "maxlength" => 1000,    # maximum length of question allowed
        },
        "pollname" => {
            "maxlength" => 1000,    # maximum length of poll name allowed
        },
        "text" => {
            "size"      => 50,      # default size of a text element
            "maxlength" => 255,     # default maxlength of a text element
        },
        "size" => {
            "min" => 1,             # minimum allowed size value for a text element
            "max" => 100,           # maximum allowed size value for a text element
        },
        "maxlength" => {
            "min" => 1,             # minimum allowed maxlength value for a text element
            "max" => 255,           # maximum allowed maxlength value for a text element
        },
        "scale" => {
            "from"     => 1,        # default from value for a scale
            "to"       => 10,       # default to value for a scale
            "by"       => 1,        # default by value for a scale
            "maxitems" => 21,       # maximum number of items allowed in a scale
        },
        "checkbox" => {
            "checkmin" =>
                0,    # number of checkboxes a user must tick in that question (default 0: no limit)
            "checkmax" =>
                255,    # maximum number of checkboxes a user is allowed to tick in that question
        },
    );

    $vars->{rules} = \%RULES;
    my $remote_can_make_polls = $remote->can_create_polls;

    my $authas = $get->{'authas'} || $remote->{'user'};
    my $u;

    # If remote can make polls, make sure they can post to the authas journal
    # If remote can't make polls, make sure they maintain the authas journal
    if ($remote_can_make_polls) {
        my $authas_u = LJ::load_user($authas);
        $u = $authas_u if $authas_u and $remote->can_post_to($authas_u);
    }
    else {
        $u = LJ::get_authas_user($authas);
    }

    # Return error if previous check was unsuccessful
    return error_ml('error.invalidauth') unless ($u);

    # first pageview, show authas
    if ( !$r->did_post || $post->{'start_over'} ) {

        # postto switcher form
        # If remote can make polls, show all communities they have posting access to
        # If remote can't make polls, show only paid communities they maintain
        my $postto_html = "<form method='get' action='create'>\n";
        if ($remote_can_make_polls) {
            $postto_html .= LJ::make_authas_select(
                $remote,
                {
                    'authas'   => $get->{'authas'},
                    foundation => 1,
                    'label'    => LJ::Lang::ml('web.postto.label'),
                    'button'   => LJ::Lang::ml('web.postto.btn')
                }
            ) . "\n";
        }
        else {
            $postto_html .= LJ::make_authas_select(
                $remote,
                {
                    'authas'   => $get->{'authas'},
                    foundation => 1,
                    'label'    => LJ::Lang::ml('web.postto.label'),
                    'button'   => LJ::Lang::ml('web.postto.btn'),
                    'cap'      => 'makepoll',
                }
            ) . "\n";
        }
        $postto_html .= "</form>\n\n";
        $vars->{postto_html} = $postto_html;
    }

    # does the remote or selected user have the 'makepoll' cap?
    unless ( $remote_can_make_polls || $u->can_create_polls ) {

        # $body .= "<?h1 $ML{'Sorry'} h1?><?p $ML{'.error.accttype2'} p?>";
        # return;
    }

    # extra arguments for get requests
    my $getextra = $authas ne $remote->{'user'} ? "?authas=$authas" : '';
    $vars->{getextra} = $getextra;

    # variable to store what question the last action took place in
    my $focuson = "";

    #######################################################
    #
    # Function definitions
    #

    # builds a %poll object
    my $build_poll = sub {
        my $err = shift;

        # initialize the hash
        my $poll = {
            "name"    => "",
            "count"   => "0",
            "isanon"  => "no",
            "whoview" => "all",
            "whovote" => "all",
            "pq"      => [],
        };

        # make sure they don't plug in an outrageous count
        my $post_count = $post->{count} || 0;
        $post->{count} = 0 if $post_count < 0;
        $post->{count} = $RULES{elements}->{max}
            if $post_count > $RULES{elements}->{max};

        # form properties
        foreach my $it (qw(count name isanon whoview whovote)) {
            $poll->{$it} = $post->{$it} if $post->{$it};
        }

        # go through the count to build our hash
        foreach my $q ( 0 .. $poll->{'count'} - 1 ) {

            # sanify 'opts' form elements at this level
            # so we don't have to do it later
            my $opts = "pq_${q}_opts";
            $post->{$opts} = 0 if $post->{$opts} && $post->{$opts} < 0;
            $post->{$opts} = $RULES{'items'}->{'max'}
                if $post->{$opts} > $RULES{'items'}->{'max'};

            # question record
            my $qrec = {};

            # validate question attributes
            foreach my $atr (
                qw(type question opts size maxlength from to by checkmin checkmax lowlabel highlabel)
                )
            {
                my $val = $post->{"pq_${q}_$atr"};
                next
                    unless defined $val
                    || $atr eq 'question';    # 'question' is required, so always check it

                # ignore invalid types?
                next if $atr eq 'type' && $val !~ /^(radio|check|drop|text|scale)$/;

                # question too long/nonexistant
                if ( $atr eq 'question' ) {
                    if ( !$val ) {
                        $qrec->{$atr} = $val;
                        $err->{$q}->{$atr} = LJ::Lang::ml("$ml_scope.error.notext");
                    }
                    elsif ( length($val) > $RULES{$atr}->{'maxlength'} ) {
                        $qrec->{$atr} = substr( $val, 0, $RULES{$atr}->{'maxlength'} );
                    }
                    else {
                        $qrec->{$atr} = $val;
                    }

                    next;
                }

                # opts too long?
                if ( $atr eq 'opts' ) {
                    $qrec->{$atr} = int($val);
                    next;
                }

                # size too short/long?
                if ( $atr eq 'size' ) {
                    $qrec->{$atr} = int($val);

                    if (   $qrec->{$atr} > $RULES{$atr}->{'max'}
                        || $qrec->{$atr} < $RULES{$atr}->{'min'} )
                    {
                        $err->{$q}->{$atr} = LJ::Lang::ml( "$ml_scope.error.pqsizeinvalid2",
                            { 'min' => $RULES{$atr}->{'min'}, 'max' => $RULES{$atr}->{'max'} } );
                    }

                    next;
                }

                # maxlength too short/long?
                if ( $atr eq 'maxlength' ) {
                    $qrec->{$atr} = int($val);

                    if (   $qrec->{$atr} > $RULES{$atr}->{'max'}
                        || $qrec->{$atr} < $RULES{$atr}->{'min'} )
                    {
                        $err->{$q}->{$atr} = LJ::Lang::ml(
                            "$ml_scope.error.pqmaxlengthinvalid2",
                            {
                                'min' => $RULES{'maxlength'}->{'min'},
                                'max' => $RULES{'maxlength'}->{'max'}
                            }
                        );
                    }

                    next;
                }

                # from/to/by -- scale
                if ( $atr eq 'from' ) {
                    $qrec->{'to'}   = int( $post->{"pq_${q}_to"} )   || 0;
                    $qrec->{'from'} = int( $post->{"pq_${q}_from"} ) || 0;
                    $qrec->{'by'} =
                        int( $post->{"pq_${q}_by"} ) >= 1 ? int( $post->{"pq_${q}_by"} ) : 1;

                    if ( $qrec->{'by'} < $RULES{'by'}->{'min'} ) {
                        $err->{$q}->{'by'} = LJ::Lang::ml( "$ml_scope.error.scalemininvalid",
                            { 'min' => $RULES{'by'}->{'min'} } );
                    }

                    if ( $qrec->{'from'} >= $qrec->{'to'} ) {
                        $err->{$q}->{'from'} = LJ::Lang::ml("$ml_scope.error.scalemaxlessmin");
                    }

                    my $scaleoptions = ( ( $qrec->{to} - $qrec->{from} ) / $qrec->{by} ) + 1;
                    if ( $scaleoptions > $RULES{scale}->{maxitems} ) {
                        $err->{$q}->{to} = LJ::Lang::ml(
                            "$ml_scope.error.scaletoobig1",
                            {
                                'maxselections' => $RULES{scale}->{maxitems},
                                'selections'    => $scaleoptions - $RULES{scale}->{maxitems}
                            }
                        );
                    }

                    next;
                }

                if ( $atr eq 'checkmin' ) {
                    $qrec->{'checkmin'} = int( $post->{"pq_${q}_checkmin"} ) || 0;
                    $qrec->{'checkmax'} = int( $post->{"pq_${q}_checkmax"} ) || 255;
                    next;
                }

                # otherwise, let it by.
                $qrec->{$atr} = $val;
            }

            # insert record into poll structure
            $poll->{'pq'}->[$q] = $qrec;

            my $num_opts = 0;
            foreach my $o ( 0 .. $qrec->{'opts'} - 1 ) {
                next unless defined $post->{"pq_${q}_opt_$o"};

                if ( length( $post->{"pq_${q}_opt_$o"} ) > $RULES{'items'}->{'maxlength'} ) {
                    $qrec->{'opt'}->[$o] =
                        substr( $post->{"pq_${q}_opt_$o"}, 0, $RULES{'items'}->{'maxlength'} );
                    $err->{$q}->{$o}->{'items'} = LJ::Lang::ml("$ml_scope.error.texttoobig");
                    $num_opts++;
                }
                elsif ( length( $post->{"pq_${q}_opt_$o"} ) > 0 ) {

                    # no change necessary
                    $qrec->{'opt'}->[$o] = $post->{"pq_${q}_opt_$o"};
                    $num_opts++;
                }
            }

            # too few options specified?
            if ( $num_opts < $RULES{'items'}->{'min'} && $qrec->{'type'} =~ /^(drop|check|radio)$/ )
            {
                $err->{$q}->{'items'} = LJ::Lang::ml("$ml_scope.error.allitemsblank");
            }

            # checks if minimum and maximum options for checkboxes are OK

            if ( $qrec->{type} eq 'check' ) {
                my $checkmin = $qrec->{'checkmin'};
                if ( $checkmin > $num_opts ) {
                    $err->{$q}->{'checkmin'} = LJ::Lang::ml("$ml_scope.error.checkmintoohigh2");
                }

                my $checkmax = $qrec->{'checkmax'};
                if ( $checkmax < $checkmin ) {
                    $err->{$q}->{'checkmax'} = LJ::Lang::ml("$ml_scope.error.checkmaxtoolow2");
                }
            }
        }

        # closure to apply action to poll object, given 'type', 'item', and 'val'
        my $do_action = sub {
            my ( $type, $item, $val ) = @_;
            return unless $type && defined $item && defined $val;

            # move action
            if ( $type eq "move" ) {

                # up or down?
                my $adj = undef;
                if ( $val eq 'up' && $item - 1 >= 0 ) {
                    $adj = $item - 1;
                }
                elsif ( $val eq 'dn' && $item + 1 <= $poll->{'count'} ) {
                    $adj = $item + 1;
                }

                # invalid action
                return unless $adj;

                # swap poll items and error references
                my $swap = sub { return ( $_[1], $_[0] ) };

                ( $poll->{'pq'}->[$adj], $poll->{'pq'}->[$item] ) =
                    $swap->( $poll->{'pq'}->[$adj], $poll->{'pq'}->[$item] );

                ( $err->{$adj}, $err->{$item} ) =
                    $swap->( $err->{$adj}, $err->{$item} );

                # focus on the new position
                $focuson = $adj;

                return;
            }

            # delete action
            if ( $type eq "delete" ) {

                # delete from poll and decrement question count
                splice( @{ $poll->{"pq"} }, $item, 1 );
                $poll->{'count'}--;
                delete $err->{$item};

# focus on the previous item, unless this one was the top one, in which case we will focus on the new first
                $focuson = $item > 0 ? $item - 1 : 0;

                return;
            }

            # request more options
            if ( $type eq "request" ) {

                # add more items
                $poll->{"pq"}->[$item]->{'opts'} += $RULES{'items'}->{'more'};
                $poll->{'pq'}->[$item]->{'opts'} = $RULES{'items'}->{'max'}
                    if @{ $poll->{'pq'} }[$item]->{'opts'} > $RULES{'items'}->{'max'};

                # focus on the item we just added more options for
                $focuson = $item;

                return;
            }

            # insert
            if ( $type eq "insert" ) {

                # increase poll count
                $poll->{'count'}++;

                # splice new item in
                splice(
                    @{ $poll->{'pq'} },
                    $item, 0,
                    {
                        "question" => '',
                        "type"     => $val,
                        "opts"     => ( $val =~ /^(radio|drop|check)$/ )
                        ? $RULES{'items'}->{'start'}
                        : 0,
                        "opt" => [],
                    }
                );

                # focus on the new item
                $focuson = $item;

                return;
            }
        };

        # go through the count again, this time apply requested actions
        foreach my $q ( 0 .. $poll->{'count'} ) {

            # if there is an action, perform the action
            foreach my $act (qw(move delete insert request)) {

                # images stick an .x and .y on inputs
                my $do = $post->{"$act:$q:do.x"} ? "$act:$q:do.x" : "$act:$q:do";

                # catches everything but move
                if ( $post->{$do} ) {

                    # catches deletes, requests, etc
                    if ( $act ne 'insert' ) {
                        $do_action->( $act, $q, $act );
                        next;
                    }

                    # catches inserts
                    if ( $post->{"$act:$q"} =~ /^(radio|check|drop|text|scale)$/ ) {
                        $do_action->( $act, $q, $1 );
                        next;
                    }
                }

                # catches moves
                if ( defined $post->{"$act:$q:up.x"} && $post->{"$act:$q:up.x"} =~ /\d+/
                    || ( defined $post->{"$act:$q:dn.x"} && $post->{"$act:$q:dn.x"} =~ /\d+/ ) )
                {
                    $do_action->( $act, $q, $post->{"$act:$q:up.x"} ? 'up' : 'dn' );
                    next;
                }

            }
        }

        # all arguments are refs, nothing to return
        return $poll;
    };

    # variables to pass around
    my $poll = {};
    my $err  = {};

    # create poll code given a %poll object
    my $make_code = sub {
        my $poll = shift;

        my $ret;

        # start out the tag
        $ret .=
              "<poll name='"
            . LJ::ehtml( $poll->{'name'} )
            . "' isanon='"
            . $poll->{'isanon'}
            . "' whovote='"
            . LJ::ehtml( $poll->{'whovote'} )
            . "' whoview='"
            . LJ::ehtml( $poll->{'whoview'} ) . "'>\n";

        # go through and make <poll-question> tags
        foreach my $q ( 0 .. $poll->{'count'} - 1 ) {
            my $elem = $poll->{'pq'}->[$q];
            $ret .= "<poll-question type='$elem->{'type'}'";

            # fill in attributes
            if ( $elem->{'type'} eq 'text' ) {
                foreach my $el (qw(size maxlength)) {
                    $ret .= " $el='" . LJ::ehtml( $elem->{$el} ) . "'";
                }
            }
            elsif ( $elem->{'type'} eq 'scale' ) {
                foreach my $el (qw(from to by lowlabel highlabel)) {
                    $ret .= " $el='" . LJ::ehtml( $elem->{$el} ) . "'";
                }
            }
            elsif ( $elem->{'type'} eq 'check' ) {
                foreach my $el (qw(checkmin checkmax)) {
                    $ret .= " $el='" . LJ::ehtml( $elem->{$el} ) . "'";
                }
            }
            $ret .= ">\n";
            $ret .= $elem->{'question'} . "\n" if $elem->{'question'};

            if ( $elem->{'type'} =~ /^(radio|drop|check)$/ ) {

                # make <poll-item> tags
                foreach my $o ( 0 .. $elem->{'opts'} ) {
                    $ret .= "<poll-item>$elem->{'opt'}->[$o]</poll-item>\n"
                        if defined $elem->{'opt'}->[$o] && $elem->{'opt'}->[$o] ne '';
                }
            }
            $ret .= "</poll-question>\n";
        }

        # close off the poll
        $ret .= "</poll>";

        # escape html on this because it'll currently be sent to user so they can copy/paste
        return $ret;
    };

    # generates html for the hidden elements necessary to maintain
    # the state of the given poll
    my $poll_hidden = sub {
        my $poll = shift;

        my @elements = ();
        foreach my $k ( keys %$poll ) {

            # poll attributes
            unless ( ref $poll->{$k} eq 'ARRAY' ) {
                push @elements, ( $k, $poll->{$k} );
                next;
            }

            # poll questions
            my $q_idx = 0;
            foreach my $q ( @{ $poll->{$k} } ) {

                # question attributes
                foreach my $atr ( keys %$q ) {
                    unless ( ref $q->{$atr} eq 'ARRAY' ) {
                        push @elements, ( "${k}_${q_idx}_$atr", $q->{$atr} );
                        next;
                    }

                    # radio/text/drop options
                    my $opt_idx = 0;
                    foreach my $o ( @{ $q->{$atr} } ) {
                        push @elements, ( "${k}_${q_idx}_${atr}_$opt_idx", $o );
                        $opt_idx++;
                    }
                }

                $q_idx++;
            }
        }

        return \@elements;
    };

    # process post input
    if ( $r->did_post() && !$post->{'start_over'} ) {

        # load poll hash from $post and get action and error info
        $poll                = $build_poll->($err);
        $vars->{poll}        = $poll;
        $vars->{err}         = $err;
        $vars->{poll_hidden} = $poll_hidden;

        # generate poll preview for them
        if ( ( $post->{'see_preview'} || $post->{'see_code'} ) && !%$err ) {

            # generate code for preview
            my $code = $make_code->($poll);

            # parse code into a fake poll object so we can call "preview" on it
            my $err;
            my $codecopy = $code;    # parse function will eat the code
            my $pollobj = ( LJ::Poll->new_from_html( \$codecopy, \$err, {} ) )[0];

            return error_ml( "$ml_scope.error.parsing2", { 'err' => $err } ) if $err;

            my $update_url =
                LJ::BetaFeatures->user_in_beta( $remote => "updatepage" )
                ? "$LJ::SITEROOT/entry/new"
                : "$LJ::SITEROOT/update";
            my $usejournal = $getextra ? "?usejournal=$authas" : '';
            $vars->{update_url} = $update_url . $usejournal;
            $vars->{pollobj}    = $pollobj;
            $vars->{err}        = $err;
            $vars->{see_code}   = $post->{see_code} ? 1 : 0;
            $vars->{code}       = $code;
            return DW::Template->render_template( 'poll/preview.tt', $vars );
        }
    }

    return DW::Template->render_template( 'poll/create.tt', $vars );
}

1;
