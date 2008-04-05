#!/usr/bin/perl
#

use strict;

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

use vars qw(%caps_general %caps_local);

# Local caps are placed in file: cap-local.pl.
# Use format in cap2db.pl, substituting 'caps_local' with 'caps_general'

my $LJHOME = $ENV{'LJHOME'};

require "$LJHOME/doc/raw/build/docbooklib.pl";

if (-e "$LJHOME/doc/raw/build/caps/cap-local.pl") {
    require "$LJHOME/doc/raw/build/caps/cap-local.pl";
}

$caps_general{'checkfriends'} = {
    type => 'boolean',
    desc => 'Can use checkfriends.',
};
$caps_general{'checkfriends_interval'} = {
    type => 'integer',
    desc => 'Time, in minutes, before clients can call <quote>checkfriends</quote>.',
};
$caps_general{'synd_create'} = {
    type => 'boolean',
    desc => 'Can create syndicated accounts.',
};
$caps_general{'findsim'} = {
    type => 'boolean',
    desc => 'Can use the similar interests matching feature.',
};
$caps_general{'friendsfriendsview'} = {
    type => 'boolean',
    desc => 'Has <quote>Friends of Friends</quote> /friendsfriends view enabled.',
};
$caps_general{'friendsviewupdate'} = {
    type => 'integer',
    desc => 'Interval in seconds after which user can see new Friends view items.',
};
$caps_general{'makepoll'} = {
    type => 'boolean',
    desc => 'Can make polls.',
};
$caps_general{'maxfriends'} = {
    type => 'integer',
    desc => 'Maximum number of friends allowed per account.',
};
$caps_general{'moodthemecreate'} = {
    type => 'boolean',
    desc => 'Can create new mood themes.',
};
$caps_general{'readonly'} = {
    type => 'boolean',
    desc => 'No writes to the database for this journal are permitted. '.
            '(This is used by the cluster management tool: a journal is read-only '.
            'while it is being moved to another cluster)',
};
$caps_general{'styles'} = {
    type => 'boolean',
    desc => 'User can create &amp; use their own (S1) styles.',
};
$caps_general{'textmessaging'} = {
    type => 'boolean',
    desc => 'Can use text messaging.',
};
$caps_general{'todomax'} = {
    type => 'integer',
    desc => 'Maximum number of todo items allowed.',
};
$caps_general{'todosec'} = {
    type => 'boolean',
    desc => 'Can make non-public todo items.',
};
$caps_general{'userdomain'} = {
    type => 'boolean',
    desc => 'Can view journal at http://user.$LJ::DOMAIN/',
};
$caps_general{'useremail'} = {
    type => 'boolean',
    desc => 'Has &email; address @$LJ::USER_DOMAIN',
};
$caps_general{'userpics'} = {
    type => 'integer',
    desc => 'Maximum number of userpics allowed.',
};
$caps_general{'hide_email_after'} = {
    type => 'integer',
    desc => 'Hide an account\'s &email; address who has not used the site in a time period '.
            ' longer than the given setting.  If 0, the &email; is never hidden.  The time period is in days.',
};
$caps_general{'weblogscom'} = {
    type => 'boolean',
    desc => 'Can ping <uri>weblogs.com</uri> when posting new entries.',
};
$caps_general{'full_rss'} = {
    type => 'boolean',
    desc => 'Show the full text in the RSS view.',
};
$caps_general{'edit_comments'} = {
    type => 'boolean',
    desc => 'Can edit comments they posted, which have not been replied to or frozen.',
};
$caps_general{'get_comments'} = {
    type => 'boolean',
    desc => 'Can receive comments.',
};
$caps_general{'leave_comments'} = {
    type => 'boolean',
    desc => 'Can leave comments on other accounts.',
};
$caps_general{'can_post'} = {
    type => 'boolean',
    desc => 'Can post new entries.',
};
$caps_general{'rateperiod-failed_login'} = {
    type => 'integer',
    desc => 'The period of time an account can try to repeat logging in for.',
};
$caps_general{'rateallowed-failed_login'} = {
    type => 'integer',
    desc => 'How many times during a period an account can try to log in.',
};
$caps_general{'security_filter'} = {
    type => 'boolean',
    desc => 'Can use view-by-security filters to see all posts with a given security in their journal.',
};
$caps_general{'s2styles'} = {
    type => 'boolean',
    desc => 'Can use all S2 layers.',
};
$caps_general{'friendspopwithfriends'} = {
    type => 'boolean',
    desc => 'Can use the <quote>Popular with Friends</quote> tool.',
};
$caps_general{'emailpost'} = {
    type => 'boolean',
    desc => 'Can post via an &email; gateway.',
};
$caps_general{'disable_can_post'} = {
    type => 'boolean',
    desc => 'Posting new journal entries is disabled for this account, presumably '.
            ' because a trial period of some sort has expired.',
};
$caps_general{'disable_get_comments'} = {
    type => 'boolean',
    desc => 'Getting new comments in this journal is disabled, presumably '.
            ' because a trial period of some sort has expired.',
};
$caps_general{'disable_leave_comments'} = {
    type => 'boolean',
    desc => 'This account can no longer leave comments, presumably '.
            ' because a trial period of some sort has expired.',
};
$caps_general{'no_mail_alias'} = {
    type => 'boolean',
    desc => 'Disable forwarding of &email; sent to user&apos;s site-based (see useremail cap) address '.
            'onto user&apos;s &email; address.',
};
$caps_general{'userlinks'} = {
    type => 'integer',
    desc => 'Maximum number of links users can place in their Links  '.
            'List (<quote>blogroll</quote>), used in S2 styles.',
};
$caps_general{'mod_queue'} = {
    type => 'integer',
    desc => 'Maximum number of entries that can be queued for approval by a community '.
            'moderator, for a moderated community.',
};
$caps_general{'mod_queue_per_poster'} = {
    type => 'integer',
    desc => 'Maximum number of entries a user can submit into a community '.
            ' moderation queue, within a period.',
};
$caps_general{'getselfemail'} = {
    type => 'boolean',
    desc => 'Can receive copy by &email; of own comments.',
};
$caps_general{'maxcomments'} = {
    type => 'integer',
    desc => 'Total number of comments that can be posted to an entry. Defaults to 5000.',
};
$caps_general{'domainmap'} = {
    type => 'boolean',
    desc => 'Can map (CNAME) a vanity domain to their journal &url;.',
};
$caps_general{'tools_recent_comments_display'} = {
    type => 'integer',
    desc => 'Total number of comments a user can see, '.
            ' at <filename>/tools/recent_comments.bml</filename>.',
};
$caps_general{'directory'} = {
    type => 'boolean',
    desc => 'Can use the Directory to search for users.',
};
$caps_general{'s2layersmax'} = {
    type => 'integer',
    desc => 'Maximum number of allowed layers for a user.',
};
$caps_general{'s2props'} = {
    type => 'boolean',
    desc => 'Can use all S2 properties. Custom hooks used to restrict user ability '.
            'should be based on this instead of the s2styles cap.',
};
$caps_general{'s2stylesmax'} = {
    type => 'integer',
    desc => 'Maximum number of S2 styles allowed for a user.',
};
$caps_general{'subscriptions'} = {
    type => 'integer',
    desc => 'Maximum number of &esn; subscriptions allowed.',
};
$caps_general{'mass_privacy'} = {
    type => 'boolean',
    desc => 'Can edit entries en-masse, at <filename>editprivacy.bml</filename>.',
};
$caps_general{'tags_max'} = {
    type => 'integer',
    desc => 'Maximum number of tags a user is allowed. A value of 0 allows unlimited tags '.
            'If a user has more tags than the limit, they can continue to use existing tags, '.
            'but cannot create new ones.',
};
$caps_general{'inbox_max'} = {
    type => 'integer',
    desc => 'Maximum number of &esn; notifications a user can have in their Inbox.',
};
$caps_general{'usermessage_length'} = {
    type => 'integer',
    desc => 'Maximum number of characters a user can use in messages  '.
        'they compose in their &esn; Inbox. Defaults to 5000.',
};
$caps_general{'userpicselect'} = {
    type => 'boolean',
    desc => 'Can use the &ajax; Userpic Selector.',
};
$caps_general{'maxfriends'} = {
    type => 'integer',
    desc => 'Maximum number of accounts a user can add to their <quote>Friends list</quote>.',
};
$caps_general{'track_defriended'} = {
    type => 'boolean',
    desc => 'Can add &esn; notifications for being de-friended by other users.',
};
$caps_general{'track_thread'} = {
    type => 'boolean',
    desc => 'Can add &esn; subscriptions for comment threads.',
};
$caps_general{'track_user_newuserpic'} = {
    type => 'boolean',
    desc => 'Can add &esn; subscriptions for a user uploading a new userpic.',
};
$caps_general{'track_pollvotes'} = {
    type => 'boolean',
    desc => 'Can add &esn; subscriptions for tracking when a vote is added to a poll.',
};
$caps_general{'s2viewentry'} = {
    type => 'boolean',
    desc => 'Lets S2 layouts disable customized EntryPage <quote>fall-back</quote> '.
            'to &bml; (actually <quote>s1shortcomings</quote> S2 style).',
};
$caps_general{'s2viewreply'} = {
    type => 'boolean',
    desc => 'Lets S2 layouts disable customized ReplyPage <quote>fall-back</quote> '.
            'to &bml; (actually <quote>s1shortcomings</quote> S2 style).',
};
$caps_general{'rateperiod-invitefriend'} = {
    type => 'integer',
    desc => 'Rate-limiting for the <filename>/friends/invite.bml</filename> '.
            ' <quote>Invite a Friend</quote> feature. The time period is in minutes.',
};
$caps_general{'rateallowed-invitefriend'} = {
    type => 'integer',
    desc => 'How many times within a period a user can invite a friend, at the <filename>/friends/invite.bml</filename> page.',
};
$caps_general{'rateperiod-lostinfo'} = {
    type => 'integer',
    desc => 'Rate-limiting for the Lost Username/Password <filename>lostinfo.bml</filename> page. '.
            'The time period is in minutes, so one hour is a value of 60 while a value of 24*60 is 24 hours.',
};
$caps_general{'rateallowed-lostinfo'} = {
    type => 'integer',
    desc => 'How many times within a period a user can request a lost password/username reminder, at '.
            'the <filename>lostinfo.bml</filename> page.',
};
$caps_general{'bookmark_max'} = {
    type => 'integer',
    desc => 'Maximum number of bookmarks, or flags, a user can use in their &esn; Inbox.',
};
$caps_general{'viewmailqueue'} = {
    type => 'boolean',
    desc => 'Can use the Email Gateway log at <filename>/tools/recent_emailposts.bml</filename> to view recent &email; posts, along with any error messages, for troubleshooting.',
};

sub dump_caps
{
    my $title = shift;
    my $caps = shift;
    print "<variablelist>\n  <title>$title Capabilities</title>\n";
    foreach my $cap (sort keys %$caps)
    {
        print "  <varlistentry>\n";
        print "    <term><literal role=\"cap.class\">$cap</literal></term>\n";
        print "    <listitem><para>\n";
        print "      (<emphasis>$caps->{$cap}->{'type'}</emphasis>) - $caps->{$cap}->{'desc'}\n";
        print "    </para></listitem>\n";
        print "  </varlistentry>\n";
    }
    print "</variablelist>\n";
}

dump_caps("General", \%caps_general);
if (%caps_local) { dump_caps("Local", \%caps_local); }

