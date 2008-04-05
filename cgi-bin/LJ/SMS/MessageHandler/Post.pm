package LJ::SMS::MessageHandler::Post;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text = $msg->body_text;

    my ($sec, $subject, $body) = $text =~ /
        ^\s*
        (?:                       # the "post" portion is optional
         p(?:ost)?                # post full or short

        (?:\.                     # optional security setting
         (
          (?:\"|\').+?(?:\"|\')   # single or double quoted security
          |
          \S+)                    # single word security
         )?

         \s+
         )?

         (?:                      # optional subject
          (?:\[|\()(.+?)(?:\]|\)) # [...] or (...) subject
          )?

         \s*

         (.+)                     # teh paylod!

         \s*$/isx;

    # for quoted strings, the 'sec' segment will still have single or double quotes
    if ($sec) {
        $sec =~ s/^(?:\"|\')//;
        $sec =~ s/(?:\"|\')$//;
    }

    my $u = $msg->from_u;
    my $secmask = 0;

    if ($sec) {
        if ($sec =~ /^pu/i) {
            $sec = 'public';
        } elsif ($sec =~ /^fr/i) {
            $sec = 'usemask';
            $secmask = 1;
        } elsif ($sec =~ /^pr/i) {
            $sec = 'private';
        } else {
            my $groups = LJ::get_friend_group($u);

            my $found = 0;
            while (my ($bit, $grp) = each %$groups) {
                next unless $grp->{groupname} =~ /^\Q$sec\E$/i;

                # found the security group the user is asking for
                $sec = 'usemask';
                $secmask = 1 << $bit;

                $found++;
                last;
            }

            # if the given security arg was an invalid friends group,
            # post the entry as private
            $sec = 'private' unless $found;
        }
    }

    # initiate a protocol request to post this message
    my $err;
    my $default_subject = "Posted using <a href='$LJ::SITEROOT/manage/sms/'>$LJ::SMS_TITLE</a>";
    my $res = LJ::Protocol::do_request
        ("postevent",
         { 
             ver        => 1,
             username   => $u->{user},
             lineendings => 'unix',
             subject     => $subject || $default_subject,
             event       => $body,
             props       => { 
                 sms_msgid => $msg->id,
                 useragent => 'sms',
             },
             security    => $sec,
             allowmask   => $secmask,
             tz          => 'guess' 
         },
         \$err, { 'noauth' => 1 }
         );

    # set metadata on this sms message indicating the 
    # type of handler used and the jitemid of the resultant
    # journal post
    $msg->meta
        ( post_jitemid => $res->{itemid},
          post_error   => $err,
          );

    # if we got a jitemid and the user wants to be automatically notified
    # of new comments on this post via SMS, add a subscription to it
    my $post_notify = $u->prop('sms_post_notify');
    if ($res->{itemid} && $post_notify eq 'SMS') {

        # get an entry object to subscribe to
        my $entry = LJ::Entry->new($u, jitemid => $res->{itemid})
            or die "Could not load entry object";

        $u->subscribe_entry_comments_via_sms($entry);
    }

    $msg->status($err ? 
                 ('error' => "Error posting to journal: $err") : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*p(?:ost)?[\.\s]/i ? 1 : 0;
}

1;
