#!/usr/bin/perl
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


# to be require'd by modperl.pl

use strict;

package LJ;

use Apache2::ServerUtil ();

use LJ::Config;

BEGIN {
    LJ::Config->load;
}

use Apache::LiveJournal;
use Apache::BML;
use Apache::SendStats;
use Apache::DebateSuicide;

use Digest::MD5;
use Text::Wrap ();
use LWP::UserAgent ();
use Storable;
use Time::HiRes ();
use Image::Size ();
use POSIX ();

use LJ::Hooks;
use LJ::Blob;
use LJ::Faq;
use DW::BusinessRules::InviteCodes;
use DW::BusinessRules::InviteCodeRequests;

use DateTime;
use DateTime::TimeZone;
use LJ::CProd;
use LJ::OpenID;
use LJ::Location;
use LJ::SpellCheck;
use LJ::TextMessage;
use LJ::ModuleCheck;
use LJ::Widget;
use MogileFS::Client;
use DDLockClient;
use LJ::BetaFeatures;
use DW::InviteCodes;
use DW::InviteCodeRequests;


# force XML::Atom::* to be brought in (if we have it, it's optional),
# unless we're in a test.
BEGIN {
    LJ::ModuleCheck->have_xmlatom unless LJ::is_from_test();
}

# this loads MapUTF8.
# otherwise, we'll rely on the AUTOLOAD in ljlib.pl to load MapUTF8
use LJ::ConvUTF8;

use MIME::Words;

# Try to load DBI::Profile
BEGIN { $LJ::HAVE_DBI_PROFILE = eval "use DBI::Profile (); 1;" }

use LJ::Lang;
use LJ::Links;
use LJ::Syn;
require "htmlcontrols.pl";
require "weblib.pl";
require "imageconf.pl";
use LJ::Support;
use LJ::CleanHTML;
use LJ::Talk;
require "ljfeed.pl";
require "emailcheck.pl";
require "ljmemories.pl";
require "ljmail.pl";
require "sysban.pl";
require "communitylib.pl";
use LJ::Tags;
require "ljemailgateway-web.pl";
use LJ::Customize;

use DW::Captcha;

# preload site-local libraries, if present:
require "$LJ::HOME/cgi-bin/modperl_subs-local.pl"
    if -e "$LJ::HOME/cgi-bin/modperl_subs-local.pl";

# defer loading of hooks, better that in the future, the hook loader
# will be smarter and only load in the *.pm files it needs to fulfill
# the hooks to be run
LJ::Hooks::_load_hooks_dir() unless LJ::is_from_test();

$LJ::IMGPREFIX_BAK = $LJ::IMGPREFIX;
$LJ::STATPREFIX_BAK = $LJ::STATPREFIX;
$LJ::USERPICROOT_BAK = $LJ::USERPIC_ROOT;

package LJ::ModPerl;

# pull in a lot of useful stuff before we fork children

sub setup_start {

    # auto-load some stuff before fork (unless this is a test program)
    unless ($0 && $0 =~ m!(^|/)t/!) {
        Storable::thaw(Storable::freeze({}));
        foreach my $minifile ("GIF89a", "\x89PNG\x0d\x0a\x1a\x0a", "\xFF\xD8") {
            Image::Size::imgsize(\$minifile);
        }
        DBI->install_driver("mysql");
        LJ::CleanHTML::helper_preload();
    }

    # set this before we fork
    $LJ::CACHE_CONFIG_MODTIME = (stat("$LJ::HOME/cgi-bin/ljconfig.pl"))[9];

    eval { setup_start_local(); };
}

sub setup_restart {

    # setup httpd.conf things for the user:
    LJ::ModPerl::add_httpd_config("DocumentRoot $LJ::HTDOCS")
        if $LJ::HTDOCS;
    LJ::ModPerl::add_httpd_config("ServerAdmin $LJ::ADMIN_EMAIL")
        if $LJ::ADMIN_EMAIL;

    LJ::ModPerl::add_httpd_config(q{

# User-friendly error messages
ErrorDocument 404 /404-error.bml
ErrorDocument 500 /500-error.html

# This interferes with LJ's /~user URI, depending on the module order
<IfModule mod_userdir.c>
    UserDir disabled
</IfModule>

# required for the $r we use
PerlOptions +GlobalRequest

PerlInitHandler Apache::LiveJournal
#PerlInitHandler Apache::SendStats
#PerlCleanupHandler Apache::SendStats
#PerlChildInitHandler Apache::SendStats
DirectoryIndex index.html index.bml

});

    # setup child init handler to seed random using a good entropy source
    eval { Apache2::ServerUtil->server->push_handlers(PerlChildInitHandler => sub {
        srand(LJ::urandom_int());
    }); };

    if ($LJ::BML_DENY_CONFIG) {
        LJ::ModPerl::add_httpd_config("PerlSetVar BML_denyconfig \"$LJ::BML_DENY_CONFIG\"\n");
    }

    unless ($LJ::SERVER_TOTALLY_DOWN)
    {
        LJ::ModPerl::add_httpd_config(q{

# BML support:
<Files ~ "\.bml$">
    SetHandler perl-script
    PerlResponseHandler Apache::BML
</Files>

});
    }

    if ( LJ::is_enabled('ignore_htaccess') ) {
        LJ::ModPerl::add_httpd_config(qq{

<Directory />
    AllowOverride none
</Directory>

        });
    }

    eval { setup_restart_local(); };

}

sub add_httpd_config {
    my $text = shift;
    eval { Apache2::ServerUtil->server->add_config( [ split /\n/, $text ] ); };
}

setup_start();

1;
