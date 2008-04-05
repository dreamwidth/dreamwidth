package LJ::SMS::MessageHandler::PostComm;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text = $msg->body_text;

    my ($commname, $sec, $subject, $body) = $text =~ /
        ^\s*
        p(?:ost)?c(?:omm)?        # post full or short

        (?:\.([^\s\.]+))          # community username

        (?:\.                     # optional security setting
         (
          (?:\"|\').+?(?:\"|\')   # single or double quoted security
          |
          \S+
          )                       # single word security
         )?

         \s+

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
        } elsif ($sec =~ /^(fr|me)/i) { #friends or members
            $sec = 'usemask';
            $secmask = 1;
        } else {
            # fall back to posting members-only if we can't identify it
            $sec = 'usemask';
            $secmask = 1;
        }
    }

    # initiate a protocol request to post this message
    my $err;
    my $default_subject = "Posted using <a href='$LJ::SITEROOT/manage/sms/'>$LJ::SMS_TITLE</a>";
    my $res = LJ::Protocol::do_request
        ("postevent",
         { 
             ver         => 1,
             username    => $u->{user},
             usejournal  => $commname,
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

    # try to load the community object so that we can add the
    # postcomm_journalid prop below if it was actually a valid
    # community... otherwise the prop will not be set and 
    # we'll error with whatever the protocol returned.
    my $commu = LJ::load_user($commname);

    # set metadata on this sms message indicating the 
    # type of handler used and the jitemid of the resultant
    # journal post
    $msg->meta
        ( postcomm_journalid => ($commu ? $commu->id : undef),
          postcomm_jitemid   => $res->{itemid},
          postcomm_error     => $err,
          );

    $msg->status($err ? 
                 ('error' => "Error posting to community: $err") : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*p(?:ost)?c/i ? 1 : 0;
}

1;
