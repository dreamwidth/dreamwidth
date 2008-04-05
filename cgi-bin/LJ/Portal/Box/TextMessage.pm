package LJ::Portal::Box::TextMessage; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "TextMessage";
our $_box_description = "Send a text message to other $LJ::SITENAMESHORT users who have enabled this feature.";
our $_box_name = "Text Message";

sub handle_request {
    my ($self, $get, $post) = @_;

    my $pboxid = $self->pboxid;
    my $user = $post->{'user'};

    my $genjs = sub {
        my ($html, $showmsg, $maxlen) = @_;
        $html = LJ::ejs($html);
        $showmsg ||= 0;
        $maxlen ||= '0';
        my $returncode = qq {
            tmbox = xGetElementById("tmresult$pboxid");
            if (tmbox) {
                tmbox.innerHTML = "$html";
                xDisplay(tmbox, "block");
            }

            if ($showmsg) {
                tmmsg = xGetElementById("tmmsg$pboxid");
                if (tmmsg) {
                    xDisplay(tmmsg, "block");
                    var messagefield = xGetElementById('textmessagebody$pboxid');
                    if (messagefield) {
                        messagefield.maxLength = $maxlen;
                    }
                }
            } else {
                tmmsg = xGetElementById("tmmsg$pboxid");
                if (tmmsg)
                    xDisplay(tmmsg, "none");
            }
        };
        return $returncode;
    };

    my $u = LJ::load_user($user);
    return $genjs->("No such user $user", 0) if !$u;

    my $tminfo;
    if ($u->{'txtmsg_status'} eq "on") {
        $tminfo = LJ::TextMessage->tm_info($u);
    }

    unless ($tminfo) {
        return $genjs->("<p>This user has not set up their text messaging information at $LJ::SITENAMESHORT, or they've turned it off.</p>", 0);
    }

    # are they authorized?

    if ($tminfo->{'security'} ne "all") {
        my $remote = $self->{'u'};

        if ($tminfo->{'security'} eq "friends" && $u->{'userid'} != $remote->{'userid'}) {
            unless (LJ::is_friend($u->{'userid'}, $remote->{'userid'})) {
                return $genjs->("<p>User <B>$u->{'user'}</B> has selected \"friends only\" as the security level required to send text messages to them.</p>", 0);
            }
        }
    }

    # send the message?
    my $message = $post->{'message'};
    if ($message) {
        my $inputfrom = $post->{'from'};
        my $from = $tminfo->{'security'} eq "all" ? $inputfrom : $self->{'u'}->{'user'};

        my $phone = new LJ::TextMessage { 'provider' => $tminfo->{'provider'},
                                          'number' => $tminfo->{'number'},
                                          'mailcommand' => $LJ::SENDMAIL,
                                          'smtp' => $LJ::SMTP_SERVER,
                                      };
        my @errors;
        $phone->send({ 'from' => $from,
                       'message' => $message, },
                     \@errors);

        # strip numbers from error messages
        s/(\d{3,})/'x'x length $1/eg foreach @errors;

        return $genjs->(LJ::bad_input(@errors)) if @errors;

        return $genjs->("<h2>Success</h2><p>Your text message was sent.</p>");
    }

    my $pinfo = LJ::TextMessage::provider_info($tminfo->{'provider'});

    my $maxlen = $pinfo->{'totlimit'};
    if ($pinfo->{'msglimit'} < $maxlen) {
        $maxlen = $pinfo->{'msglimit'};
    }
    $maxlen -= length($self->{'u'}->{'user'});

    # code to send message request
    my $jssubmit = qq {
        var userfield = xGetElementById('textmessageuser$pboxid');
        var messagefield = xGetElementById('textmessagebody$pboxid');
        if (userfield && messagefield) {
            return evalXrequest('portalboxaction=$pboxid&user='+userfield.value+'&message='+messagefield.value);
        }
        return true;
    };

    return $genjs->( qq {
        <p>(max <tt>$maxlen</tt> characters ... type until it stops you)<br />
            <p><input type='submit' value="Send Message!" onclick="$jssubmit" /></p>
        }, 1, $maxlen );
}

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};
    my $helplink = LJ::Portal->get_faq_link('textmessage');

    my $jssubmit = qq {
        var userfield = xGetElementById('textmessageuser$pboxid');
        if (userfield) {
            return evalXrequest('portalboxaction=$pboxid&user='+userfield.value);
        }
        return true;
    };

    my $form_auth = LJ::form_auth();

    $content = qq {
<form method='POST' action='$LJ::SITEROOT/tools/textmessage.bml' id='tmform$pboxid'>
$form_auth
Username: <input type='text' size='15' maxlength='15' name='user' id='textmessageuser$pboxid'/>
<input type='submit' value="Proceed..." onclick="$jssubmit" />
<div id="tmmsg$pboxid" style="display: none;">
<b>Message:</b><br /><input type="text" id="textmessagebody$pboxid" maxlength=42 />
</div>
<div id="tmresult$pboxid" class="tmform"></div>
<input type="hidden" name="from" value="$u->{'user'}" />
</form>
<div class="TextMessageDisclaimer">$helplink <B>Disclaimer:</B> The reliability of text messaging should not be trusted in dealing with emergencies.</div>
    };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

1;
