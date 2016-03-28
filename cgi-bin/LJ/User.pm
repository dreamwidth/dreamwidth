#
# NOTE: This module now requires Perl 5.10 or greater.
#
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
# LiveJournal user object
#
# 2004-07-21: we're transitioning from $u hashrefs to $u objects, currently
#             backed by hashrefs, to ease migration.  in the future,
#             more methods from ljlib.pl and other places will move here,
#             and the representation of a $u object will change to 'fields'.
#             at present, the motivation to moving to $u objects is to do
#             all database access for a given user through his/her $u object
#             so the queries can be tagged for use by the star replication
#             daemon.

use strict;
no warnings 'uninitialized';

########################################################################
### Begin LJ::User functions

package LJ::User;
use LJ::MemCache;

use DW::Logic::ProfilePage;
use DW::User::ContentFilters;
use DW::User::Edges;

use LJ::Community;
use IO::Socket::INET;
use Time::Local;

########################################################################
### Please keep these categorized and alphabetized for ease of use.
### If you need a new category, add it at the end, BEFORE category 99.
### Categories kinda fuzzy, but better than nothing.
###
### Categories:
###  1. Creating and Deleting Accounts
###  2. Statusvis and Account Types
###  3. Working with All Types of Account
###  19. OpenID and Identity Functions
###  26. Syndication-Related Functions
use LJ::User::Account;

###  4. Login, Session, and Rename Functions
###  21. Password Functions
use LJ::User::Login;

###  5. Database and Memcache Functions
###  23. Relationship Functions
use LJ::User::Data;

###  6. What the App Shows to Users
###  7. Formatting Content Shown to Users
use LJ::User::Display;

###  8. Userprops, Caps, and Displaying Content to Others
###  22. Priv-Related Functions
use LJ::User::Permissions;

###  9. Logging and Recording Actions
###  10. Banning-Related Functions
use LJ::User::Administration;

###  11. Birthdays and Age-Related Functions
###  12. Adult Content Functions
use LJ::User::Age;

###  13. Community-Related Functions and Authas
###  14. Comment-Related Functions
###  15. Entry-Related Functions
###  27. Tag-Related Functions
use LJ::User::Journal;

###  16. Email-Related Functions
###  25. Subscription, Notifiction, and Messaging Functions
use LJ::User::Message;

###  24. Styles and S2-Related Functions
use LJ::User::Styles;

###  28. Userpic-Related Functions
use LJ::User::Icons;


########################################################################
###  99. Miscellaneous Legacy Items

########################################################################
###  99B. Deprecated (FIXME: we shouldn't need these)


# THIS IS DEPRECATED DO NOT USE
sub email {
    my ($u, $remote) = @_;
    return $u->emails_visible($remote);
}


# FIXME: Needs updating for WTF
sub opt_showmutualfriends {
    my $u = shift;
    return $u->raw_prop('opt_showmutualfriends') ? 1 : 0;
}

# FIXME: Needs updating for WTF
# only certain journaltypes can show mutual friends
sub show_mutualfriends {
    my $u = shift;

    return 0 unless $u->is_individual;
    return $u->opt_showmutualfriends ? 1 : 0;
}


1;
