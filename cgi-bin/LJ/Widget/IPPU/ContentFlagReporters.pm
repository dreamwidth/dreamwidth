use strict;

package LJ::Widget::IPPU::ContentFlagReporters;
use base "LJ::Widget::IPPU";

sub render_body {
    my ($class, %opts) = @_;

    my $remote = LJ::get_remote();

    return "Unauthorized" unless $remote && $remote->can_admin_content_flagging;
    return "invalid params" unless $opts{journalid} && $opts{typeid} && $opts{catid};

    my $ret = '';

    my @reporters = LJ::ContentFlag->get_reporters(journalid => $opts{journalid},
                                                   typeid    => $opts{typeid},
                                                   itemid    => $opts{itemid});
    my $usernames = '';

    my @userids = map { $_->{reporterid} } @reporters;
    my $users = LJ::load_userids(@userids);

    my %support_requests_for_uid;
    foreach my $uid (keys %$users) {
        foreach my $reporter (@reporters) {
            if ($reporter->{reporterid} eq $uid) {
                next unless $reporter->{supportid};
                push @{$support_requests_for_uid{$uid}}, $reporter->{supportid};
            }
        }
    }

    $ret .= $class->start_form(id => 'banreporters_form');
    $ret .= $class->html_hidden("journalids", join(',', keys %$users));

    $usernames .= '<table class="alternating-rows" width="100%">';
    $usernames .= "<tr><th>Ban?</th><th>User</th><th>Name</th><th>Requests</th></tr>";

    my $i = 0;
    foreach my $u (values %$users) {
        my $row = $i++ % 2 == 0 ? 1 : 2;

        $usernames .= "<tr class='altrow$row'>";
        $usernames .= '<td>' . $class->html_check(name => "ban_" . $u->id) . '</td>';
        $usernames .= '<td>' . $u->ljuser_display . '</td>';
        $usernames .= '<td>' . $u->name_html . '</td>';
        if ($support_requests_for_uid{$u->id}) {
            $usernames .= "<td>";
            foreach my $spid (@{$support_requests_for_uid{$u->id}}) {
                $usernames .= "<a href='$LJ::SITEROOT/support/see_request.bml?id=$spid'>$spid</a> ";
            }
            $usernames .= "</td>";
        } else {
            $usernames .= "<td>(no request)</td>";
        }
    }

    $usernames .= '</table>';

    $ret .= qq {
        <div class="su_username_list" style="overflow-y: scroll; max-height: 20em; margin: 4px; border: 1px solid #EEEEEE;">
            $usernames
        </div>
    };

    $ret .= '<p>' . $class->html_check(name => "ban", id => 'banreporters', label => 'Ban selected users') . '</p>';

    $ret .= '<input type="button" name="doban" value="Ban" disabled="1" id="banreporters_do" />';
    $ret .= '<input type="button" name="cancel" value="Cancel" id="banreporters_cancel" />';

    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ($class, $post) = @_;

    my $remote = LJ::get_remote();
    die "Unauthorized" unless $remote && $remote->can_admin_content_flagging;

    return unless $post->{ban};

    my $journalids = $post->{journalids} or return;
    my @jids = split(',', $journalids) or return;

    my @to_ban;

    foreach my $journalid (@jids) {
        next unless $post->{"ban_$journalid"};
        push @to_ban, $journalid;
    }

    my $to_ban_users = LJ::load_userids(@to_ban);
    my @banned;

    foreach my $u (values %$to_ban_users) {
        push @banned, $u;
        LJ::sysban_create(
                          'what'    => "contentflag",
                          'value'   => $u->user,
                          'bandays' => $LJ::CONTENT_FLAG_BAN_LENGTH || 7,
                          'note'    => "contentflag ban by " . $remote->user,
                          );
    }

    return (banned => [map { $_->user } @banned]);
}

1;
