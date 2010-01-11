#!/usr/bin/perl
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Stores all global crumbs and builds the crumbs hash

use Errno qw(ENOENT);

%LJ::CRUMBS = (
    'acctstatus' => ['Account Status', '/accountstatus', 'manage'],
    'addfriend' => ['Add Friend', '', 'friends'],
    'advcustomize' => ['Customize Advanced S2 Settings', '/customize/advanced/', 'manage'],
    'advsearch' => ['Advanced Search', '/directorysearch', 'search'],
    'birthdays' => ['Birthdays', '/birthdays', 'friends'],
    'changeemail' => ['Change Email Address', '/changeemail', 'editprofile'],
    'changepass' => ['Change Password', '/changepassword', 'manage'],
    'comminvites' => ['Community Invitations', '/manage/invites', 'manage'],
    'commmembers' => ['Community Membership', '', 'managecommunity'],
    'commpending' => ['Pending Memberships', '', 'managecommunity'],
    'commsearch' => ['Community Search', '/community/search', 'community'],
    'commsentinvites' => ['Sent Invitations', '/community/sentinvites', 'managecommunity'],
    'commsettings' => ['Community Settings', '/community/settings', 'managecommunity'],
    'community' => ['Community Center', '/community/', 'home'],
    'createcommunity' => ['Create Community', '/community/create', 'managecommunity'],
    'createjournal_1' => ['Create Your Account', '/create', 'home'],
    'createstyle' => ['Create Style', '/styles/create', 'modify'],
    'customize' => ['Customize S2 Settings', '/customize/', 'manage'],
    'customizelayer' => ['Individual Customizations', '/customize/layer', 'customize'],
    'domain' => ['Domain Aliasing', '/manage/domain', 'manage'],
    'delcomment' => ['Delete Comment', '/delcomment', 'home'],
    'editentries' => ['Edit Entries', '/editjournal', 'manage'],
    'editinfo' => ['Personal Info', '/manage/profile/', 'manage'],
    'editprofile' => ['Edit Profile', '/manage/profile/', 'manage'],
    'editsettings' => ['Viewing Options', '/manage/profile/', 'manage'],
    'editstyle' => ['Edit Style', '/styles/edit', 'modify'],
    'emailmanage' => ['Email Management', '/tools/emailmanage', 'manage'],
    'export' => ['Export Journal', '/export', 'home'],
    'faq' => ['Frequently Asked Questions', '/support/faq', 'support'],
    'feedstersearch' => ['Search a Journal', '/tools/search', 'home'],
    'filterfriends' => ['Filter Reading Page', '/manage/circle/filter', 'friends'],
    'friends' => ['Circle Tools', '/manage/circle/', 'manage'],
    'home' => ['Home', '/', ''],
    'invitefriend' => ['Invite a Friend', '/manage/circle/invite', 'friends'],
    'joincomm' => ['Join Community', '', 'community'],
    'latestposts' => ['Latest Posts', '/stats/latest', 'stats'],
    'layerbrowse' => ['Public Layer Browser', '/customize/advanced/layerbrowse', 'advcustomize'],
    'leavecomm' => ['Leave Community', '', 'community'],
    'login' => ['Login', '/login', 'home'],
    'logout' => ['Logout', '/logout', 'home'],
    'lostinfo' => ['Lost Info', '/lostinfo', 'manage'],
    'manage' => ['Manage Accounts', '/manage/', 'home'],
    'managecomments' => ['Manage Comments', '/tools/recent_comments', 'manage'],
    'managecommentsettings' => [ 'Manage Comment Settings', '/manage/comments', 'manage'],
    'managecommunities' => ['Manage Communities', '/community/manage', 'manage'],
    'managefriends' => ['Manage Circle', '/manage/circle/edit', 'friends'],
    'managefriendgrps' => ['Manage Filters', '/manage/circle/editfilters', 'friends'],
    'managetags' => ['Manage Tags', '/manage/tags', 'manage'],
    'managelogins' => ['Manage Your Login Sessions', '/manage/logins', 'manage'],
    'manageuserpics' => ['Manage Userpics', '/editpics', 'manage'],
    'memories' => ['Memorable Posts', '/tools/memories', 'manage'],
    'mobilepost' => ['Mobile Post Settings', '/manage/emailpost', 'manage'],
    'moderate' => ['Community Moderation', '/community/moderate', 'community'],
    'moodeditor' => ['Custom Mood Theme Editor', '/manage/moodthemes', 'manage'],
    'moodlist' => ['Mood Viewer', '/moodlist', 'manage'],
    'popfaq' => ['Popular FAQs', '/support/popfaq', 'faq'],
    'postentry' => ['Post an Entry', '/update', 'home'],
    'register' => ['Validate Email', '/register', 'home'],
    'searchinterests' => ['Search By Interest', '/interests', 'search'],
    'searchregion' => ['Search By Region', '/directory', 'search'],
    'seeoverrides' => ['View User Overrides', '', 'support'],
    'setpgpkey' => ['Public Key', '/manage/pubkey', 'manage'],
    'sitestats' => ['Site Statistics', '/stats/site', 'about'],
    'stats' => ['Statistics', '/stats', 'about'],
    'styles' => ['Styles', '/styles/', 'modify'],
    'support' => ['Support', '/support/', 'home'],
    'supportact' => ['Request Action', '', 'support'],
    'supportappend' => ['Append to Request', '', 'support'],
    'supporthelp' => ['Request Board', '/support/help', 'support'],
    'supportnotify' => ['Notification Settings', '/support/changenotify', 'support'],
    'supportscores' => ['High Scores', '/support/highscores', 'support'],
    'supportsubmit' => ['Submit Request', '/support/submit', 'support'],
    'textmessage' => ['Send Text Message', '/tools/textmessage', 'home'],
    'transfercomm' => ['Transfer Community', '/community/transfer', 'managecommunity'],
    'translate' => ['Translation Area', '/translate/', 'home'],
    'translateteams' => ['Translation Teams', '/translate/teams', 'translate'],
    'unsubscribe' => ['Unsubscribe', '/unsubscribe', 'home'],
    'utf8convert' => ['UTF-8 Converter', '/utf8convert', 'manage'],
    'yourlayers' => ['Your Layers', '/customize/advanced/layers', 'advcustomize'],
    'yourstyles' => ['Your Styles', '/customize/advanced/styles', 'advcustomize'],
);

# include the local crumbs info
eval { require "crumbs-local.pl" };
die $@ if $@ && $! != ENOENT;

1;
