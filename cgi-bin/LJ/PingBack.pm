package LJ::PingBack;
use strict;
use LJ::Entry;

# Add comment to pinged post, if allowed.
# returns comment object in success,
# error string otherwise.
sub ping_post {
    my $class = shift;
    my %args  = @_;
    my $targetURI = $args{targetURI};
    my $sourceURI = $args{sourceURI};
    my $context   = $args{context};
    my $title     = $args{title};

    #
    my $target_entry = LJ::Entry->new_from_url($targetURI);
    unless ($target_entry){
        warn "Unknown entry";
        return "Unknown entry";
    }

    # empty object means, that sourceURI is not LJ.com's page.
    # it's an usual case.
    my $source_entry = LJ::Entry->new_from_url($sourceURI);

    # can we add pingback comment to post?
    return "pingbacks are forbidden for the target." 
        unless $class->should_entry_recieve_pingback($target_entry, $source_entry);

    # bot: pingback_bot
    # pass: test4test
    my $poster_u = LJ::load_user($LJ::PINGBACK->{comments_bot_username});
    unless ($poster_u){
        warn "Pingback bot user does not exists";
        return "Pingback bot user does not exists";
    }


    #
    my $subject = $source_entry
                    ? ($source_entry->subject_raw || BML::ml("pingback.sourceURI.default_title"))
                    : ($title || BML::ml("pingback.sourceURI.default_title"));

    my $comment = LJ::Comment->create(
                    journal      => $target_entry->journal,
                    ditemid      => $target_entry->ditemid,
                    poster       => $poster_u,

                    body         => ($source_entry
                                        ? BML::ml("pingback.ljping.comment.text2",
                                            { context   => $context,
                                              subject   => $subject,
                                              sourceURI => $sourceURI,
                                              poster    => $source_entry->poster->username,
                                              })
                                        : BML::ml("pingback.public.comment.text",
                                            { sourceURI => $sourceURI,
                                              title     => $subject,
                                              context   => $context
                                              })
                                    ),
                    subject      => $subject,

                    );

    return $comment;
    
}

sub should_entry_recieve_pingback {
    my $class        = shift;
    my $target_entry = shift;
    my $source_entry = shift;

    return 0 unless $target_entry->journal->is_in_beta("pingback");
    return 0 if $target_entry->is_suspended;

    return 0 unless $target_entry->journal->get_cap('pingback');

    # not RO?
    return 0 if $target_entry->journal->readonly; # Check "is_readonly".

    # are comments allowed?
    return 0 if $target_entry->prop('opt_nocomments');

    # did user allow to add pingbacks?
    # journal's default. We do not store "J" value in DB.
    my $entry_pb_prop = $target_entry->prop("pingback") || 'J';
    return 0 if $entry_pb_prop eq 'D';  # disabled

    return 0 if $entry_pb_prop eq 'L'   # author allowed PingBacks only from LJ
                and not $source_entry;  # and sourceURI is not LJ.com's post

    if ($entry_pb_prop eq 'J'){             
        my $journal_pb_prop = $target_entry->journal->prop("pingback") || 'D';
        return 0 if $journal_pb_prop eq 'D'       # pingback disabled
                    or ($journal_pb_prop eq 'L'   # or allowed from LJ only
                        and not $source_entry     #    but sourceURI is not LJ page
                        );
    }
    
    return 1;

}


# Send notification to PingBack server
sub notify {
    my $class = shift;
    my %args  = @_;

    my $uri  = $args{uri};
    my $text = $args{text};
    my $mode = $args{mode};

    return unless $mode =~ m!^[LO]$!; # (L)ivejournal only, (O)pen.
    my $sclient = LJ::theschwartz();
    unless ($sclient){
        warn "LJ::PingBack: Could not get TheSchwartz client";
        return;
    }

    # 
    my $job = TheSchwartz::Job->new(
                  funcname  => "TheSchwartz::Worker::NotifyPingbackServer",
                  arg       => { uri => $uri, text => $text, mode => $mode },
                  );
    $sclient->insert($job);

}


1;
