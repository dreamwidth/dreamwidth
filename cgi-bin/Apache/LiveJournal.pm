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

package Apache::LiveJournal;

use strict;
no warnings 'uninitialized';

use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED
                       HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
                       M_TRACE M_OPTIONS /;

use LJ::Protocol;

# needed to call S2::set_domain() so early:
use LJ::S2;
use Apache::LiveJournal::Interface::Blogger;
use Apache::LiveJournal::PalImg;
use LJ::ModuleCheck;
use LJ::AccessLogSink;
use LJ::AccessLogRecord;
use LJ::AccessLogSink::Database;
use LJ::AccessLogSink::DInsertd;
use LJ::AccessLogSink::DBIProfile;
use Compress::Zlib;
use XMLRPC::Transport::HTTP;
use LJ::PageStats;
use LJ::URI;
use DW::Routing;
use DW::Template;
use DW::VirtualGift;
use Cwd qw/abs_path/;

BEGIN {
    $LJ::OPTMOD_ZLIB = eval "use Compress::Zlib (); 1;";

    require "ljlib.pl";
}

my %RQ;       # per-request data
my %USERPIC;  # conf related to userpics
my %REDIR;
my ( $TOR_UPDATE_TIME, %TOR_EXITS );

my %FILE_LOOKUP_CACHE;

# Mapping of MIME types to image types understood by the blob functions.
my %MimeTypeMapd6 = (
    'G' => 'gif',
    'J' => 'jpg',
    'P' => 'png',
);

$USERPIC{'cache_dir'} = "$LJ::HOME/htdocs/userpics";
$USERPIC{'use_disk_cache'} = -d $USERPIC{'cache_dir'};
$USERPIC{'symlink'} = eval { symlink('',''); 1; };

# redirect data.
foreach my $file ('redirect.dat', 'redirect-local.dat') {
    open (REDIR, "$LJ::HOME/cgi-bin/$file") or next;
    while (<REDIR>) {
        next unless (/^(\S+)\s+(\S+)/);
        my ($src, $dest) = ($1, $2);
        $REDIR{$src} = $dest;
    }
    close REDIR;
}

my @req_hosts;  # client IP, and/or all proxies, real or claimed

# init handler (PostReadRequest)
sub handler
{
    my $r = shift;

    if ($LJ::SERVER_TOTALLY_DOWN) {
        $r->handler("perl-script");
        $r->set_handlers(PerlResponseHandler => [ \&totally_down_content ]);
        return OK;
    }

    # only perform this once in case of internal redirects
    if ($r->is_initial_req) {
        $r->push_handlers(PerlCleanupHandler => sub { %RQ = () });
        $r->push_handlers(PerlCleanupHandler => "Apache::LiveJournal::db_logger");
        $r->push_handlers(PerlCleanupHandler => "LJ::end_request");
        $r->push_handlers(PerlCleanupHandler => "Apache::DebateSuicide");

        if ($LJ::TRUST_X_HEADERS) {
            # if we're behind a lite mod_proxy front-end, we need to trick future handlers
            # into thinking they know the real remote IP address.  problem is, it's complicated
            # by the fact that mod_proxy did nothing, requiring mod_proxy_add_forward, then
            # decided to do X-Forwarded-For, then did X-Forwarded-Host, so we have to deal
            # with all permutations of versions, hence all the ugliness:
            @req_hosts = ($r->connection->remote_ip);
            if (my $forward = $r->headers_in->{'X-Forwarded-For'})
            {
                my (@hosts, %seen);
                foreach (split(/\s*,\s*/, $forward)) {
                    next if $seen{$_}++;
                    push @hosts, $_;
                    push @req_hosts, $_;
                }
                if (@hosts) {
                    my $real = shift @hosts;
                    $r->connection->remote_ip($real);
                }
                $r->headers_in->{'X-Forwarded-For'} = join(", ", @hosts);
            }

            # and now, deal with getting the right Host header
            if ($_ = $r->headers_in->{'X-Host'}) {
                $r->headers_in->{'Host'} = $_;
            } elsif ($_ = $r->headers_in->{'X-Forwarded-Host'}) {
                $r->headers_in->{'Host'} = $_;
            }
        }

        # reload libraries that might've changed
        if ( $LJ::IS_DEV_SERVER && LJ::is_enabled('module_reload') ) {
            my %to_reload;
            while (my ($file, $mod) = each %LJ::LIB_MOD_TIME) {
                my $cur_mod = (stat($file))[9];
                next if $cur_mod == $mod;
                $to_reload{$file} = 1;
            }
            my @key_del;
            foreach (my ($key, $file) = each %INC) {
                push @key_del, $key if $to_reload{$file};
            }
            delete $INC{$_} foreach @key_del;

            foreach my $file (keys %to_reload) {
                print STDERR "[$$] Reloading file: $file.\n";
                my %reloaded;
                local $SIG{__WARN__} = sub {
                    if ($_[0] =~ m/^Subroutine (\S+) redefined at /)
                    {
                        warn @_ if ($reloaded{$1}++);
                    } else {
                        warn(@_);
                    }
                };
                my $good = do $file;
                if ($good) {
                    $LJ::LIB_MOD_TIME{$file} = (stat($file))[9];
                } else {
                    die "Failed to reload module [$file] due to error: $@\n";
                }
            }
        }

        LJ::work_report_start();
    }

    $r->set_handlers(PerlTransHandler => [ \&trans ]);

    return OK;
}

sub redir {
    my ($r, $url, $code) = @_;
    $r->content_type("text/html");
    $r->headers_out->{Location} = $url;

    if ( $LJ::DEBUG{'log_redirects'} ) {
        $r->log_error("redirect to $url from: " . join(", ", caller(0)));
    }
    return $code || REDIRECT;
}

# send the user to the URL for them to get their domain session cookie
sub remote_domsess_bounce {
    return redir(BML::get_request(), LJ::remote_bounce_url(), HTTP_MOVED_TEMPORARILY);
}

sub totally_down_content
{
    my $r = shift;
    my $uri = $r->uri;

    if ($uri =~ m!^/cgi-bin/log\.cg!) {
        $r->content_type("text/plain");
        $r->print("success\nFAIL\nerrmsg\n$LJ::SERVER_DOWN_MESSAGE");
        return OK;
    }

    if ($uri =~ m!^/customview.cgi!) {
        $r->content_type("text/html");
        $r->print("<!-- $LJ::SERVER_DOWN_MESSAGE -->");
        return OK;
    }

    # set to 500 so people don't cache this error message
    my $body = "<h1>$LJ::SERVER_DOWN_SUBJECT</h1>$LJ::SERVER_DOWN_MESSAGE<!-- " . ("x" x 1024) . " -->";
    $r->status_line("503 Server Maintenance");
    $r->content_type("text/html");
    $r->headers_out->{"Content-length"} = length $body;

    $r->print($body);
    return OK;
}

sub blocked_bot
{
    my $r = shift;

    $r->status_line("403 Denied");
    $r->content_type("text/html");
    my $subject = $LJ::BLOCKED_BOT_SUBJECT || "403 Denied";
    my $message = $LJ::BLOCKED_BOT_MESSAGE || "You don't have permission to view this page.";

    if ($LJ::BLOCKED_BOT_INFO) {
        my $ip = LJ::get_remote_ip();
        my $uniq = LJ::UniqCookie->current_uniq;
        $message .= " $uniq @ $ip";
    }

    $r->print("<h1>$subject</h1>$message");
    return OK;
}

sub blocked_anon
{
    my $r = shift;
    $r->status_line( "403 Denied" );
    $r->content_type( "text/html" );

    my $subject = $LJ::BLOCKED_ANON_SUBJECT || "403 Denied";
    my $message = $LJ::BLOCKED_ANON_MESSAGE;

    unless ( $message ) {
        $message = "You don't have permission to access $LJ::SITENAME. Please first <a href='$LJ::SITEROOT/login.bml?usescheme=lynx'>log in</a>.";

        if ( $LJ::BLOCKED_ANON_URI ) {
            $message .= " <a href='$LJ::BLOCKED_ANON_URI'>Why can't I access the site without logging in?</a>";
        }
    }

    $r->print( "<html><head><title>$subject</title></head><body>" );
    $r->print( "<h1>$subject</h1> $message" );
    $r->print( "</body></html>" );
    return OK;
}

# returns whether or not an IP address is from the Tor proxy exit list, but only if we're configured
# to actually use this data
sub ip_is_via_tor {
    return unless $LJ::USE_TOR_CONFIGS;

    # try to load the data every few minutes so that we keep it reasonably fresh, but so that we don't
    # hammer the database all of the time
    unless ( defined $TOR_UPDATE_TIME && $TOR_UPDATE_TIME > time ) {
        # either way, wait a few minutes before trying again, that way we don't hammer things if the
        # database is down or something
        $TOR_UPDATE_TIME = time + 300;

        # be very conscientious not to get rid of data if we get a db error
        my $dbh = LJ::get_db_writer() or return;
        my $ips = $dbh->selectcol_arrayref( 'SELECT addr FROM tor_proxy_exits' );
        return if $dbh->err;

        if ( $ips && ref $ips eq 'ARRAY' ) {
            %TOR_EXITS = ();
            $TOR_EXITS{$_} = 1 foreach @$ips;
        }
    }

    # regardless of what happened above we can check and return
    return exists $TOR_EXITS{$_[0]};
}

sub resolve_path_for_uri {
    my ( $r, $uri ) = @_;

    if ( $uri !~ m!(\.\.|\%|\.\/)! ) {
        if ( exists $FILE_LOOKUP_CACHE{$uri} ) {
            return @{ $FILE_LOOKUP_CACHE{$uri} };
        }

        foreach my $dir ( LJ::get_all_directories( 'htdocs' ) ) {
            my $file = "$dir/$uri";
            if ( -e "$file/index.bml" && $uri eq '/' ) { 
                $file .= "index.bml";
                $uri .= "/index.bml";
            }
            if ( -e "$file.bml" ) {
                $file .= ".bml";
                $uri .= ".bml";
            }
            next unless -e $file;

            if ( -d $file && -e "$file/index.bml" ) {
                return redir( $r, $uri . "/" ) unless $uri =~ m!/$!;
                $file .= "/index.bml";
            }

            $file = abs_path( $file );
            if ( $file ) { 
                $uri =~ s!^/+!/!;
                $FILE_LOOKUP_CACHE{$uri} = [ $uri, $file ];
                return @{ $FILE_LOOKUP_CACHE{$uri} };
            }
        }
    }
    return undef;
}

sub trans
{
    my $r = shift;
    return DECLINED if defined $r->main || $r->method_number == M_OPTIONS;  # don't deal with subrequests or OPTIONS

    my $uri = $r->uri;
    my $args = $r->args;
    my $args_wq = $args ? "?$args" : "";
    my $host = lc( $r->headers_in->{"Host"} );
    my $hostport = ( $host =~ s/(:\d+)$// ) ? $1 : "";

    # Allow hosts ending in . to work properly.
    $host =~ s/\.$//;

    # disable TRACE (so scripts on non-LJ domains can't invoke
    # a trace to get the LJ cookies in the echo)
    return FORBIDDEN if $r->method_number == M_TRACE;

    # If the configuration says to log statistics and GTop is available, mark
    # values before the request runs so it can be turned into a delta later
    if (my $gtop = LJ::gtop()) {
        $r->pnotes->{gtop_cpu} = $gtop->cpu;
        $r->pnotes->{gtop_mem} = $gtop->proc_mem($$);
    }

    LJ::start_request();
    LJ::Procnotify::check();
    S2::set_domain('LJ');

    my $lang = $LJ::DEFAULT_LANG || $LJ::LANGS[0];
    BML::set_language($lang, \&LJ::Lang::get_text);

    my $is_ssl = $LJ::IS_SSL = LJ::Hooks::run_hook("ssl_check", {
        r => $r,
    });

    my $bml_handler = sub {
        my $filename = shift;
        $r->handler("perl-script");
        $r->notes->{bml_filename} = $filename;
        $r->push_handlers(PerlHandler => \&Apache::BML::handler);
        return OK;
    };

    if ($r->is_initial_req) {
        # delete cookies if there are any we want gone
        if (my $cookie = $LJ::DEBUG{"delete_cookie"}) {
            LJ::Session::set_cookie($cookie => 0, delete => 1, domain => $LJ::DOMAIN, path => "/");
        }

        # handle uniq cookies
        # this will ensure that we have a correct cookie value
        # and also add it to $r->notes
        LJ::UniqCookie->ensure_cookie_value;

        # apply sysban block if applicable
        if ( LJ::UniqCookie->sysban_should_block ) {
            $r->handler( "perl-script" );
            $r->push_handlers( PerlResponseHandler => \&blocked_bot );
            return OK;
            }

    } else { # not is_initial_req
        if ($r->status == 404) {
            my $fn = $LJ::PAGE_404 || "404-error.bml";
            my ( $uri, $path ) = resolve_path_for_uri( $r, $fn );
            return $bml_handler->( $path ) if $path;
        }
    }

    # only allow certain pages over SSL
    if ($is_ssl) {
        $LJ::IMGPREFIX = $LJ::SSLIMGPREFIX;
        $LJ::STATPREFIX = $LJ::SSLSTATPREFIX;
    } elsif (LJ::Hooks::run_hook("set_alternate_statimg")) {
        # do nothing, hook did it.
    } else {
        $LJ::DEBUG_HOOK{'pre_restore_bak_stats'}->() if $LJ::DEBUG_HOOK{'pre_restore_bak_stats'};
        $LJ::IMGPREFIX = $LJ::IMGPREFIX_BAK;
        $LJ::STATPREFIX = $LJ::STATPREFIX_BAK;
        $LJ::USERPIC_ROOT = $LJ::USERPICROOT_BAK if $LJ::USERPICROOT_BAK;
    }

    # let foo.com still work, but redirect to www.foo.com
    if ($LJ::DOMAIN_WEB && $r->method eq "GET" &&
        $host eq $LJ::DOMAIN && $LJ::DOMAIN_WEB ne $LJ::DOMAIN)
    {
        my $url = "$LJ::SITEROOT$uri";
        $url .= "?" . $args if $args;
        return redir($r, $url);
    }

    # handle alternate domains
    if ( $host ne $LJ::DOMAIN && $host ne $LJ::DOMAIN_WEB &&
           !( $LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/ ) ) {
        my $which_alternate_domain = undef;
        foreach my $other_host ( @LJ::ALTERNATE_DOMAINS ) {
            $which_alternate_domain = $other_host
                if $host =~ m/\Q$other_host\E$/i;
        }

        if ( defined $which_alternate_domain ) {
            my $root = $is_ssl ? "https://" : "http://";
            $host =~ s/\Q$which_alternate_domain\E$/$LJ::DOMAIN/i;

            # do $LJ::DOMAIN -> $LJ::DOMAIN_WEB here, to save a redirect.
            if ( $LJ::DOMAIN_WEB && $host eq $LJ::DOMAIN ) {
                $host = $LJ::DOMAIN_WEB;
            }
            $root .= "$host";

            if ( $r->method eq "GET" ) {
                my $url = "$root$uri";
                $url .= "?" . $args if $args;
                return redir( $r, $url );
            } else {
                return redir( $r, $root );
            }
        }
    }

    # block on IP address for anonymous users but allow users to log in,
    # and logged in users to go through

    # we're not logged in, and we're not in the middle of logging in
    unless ( LJ::get_remote() || LJ::remote_bounce_url() ) {
        # blocked anon uri contains more information for the user
        # re: why they're banned, and what they should do
        unless ( ( $LJ::BLOCKED_ANON_URI && index( $uri, $LJ::BLOCKED_ANON_URI ) == 0 )
                # allow the user to go through login and subdomain cookie checking paths
                || $uri =~ m!^(?:/login|/__setdomsess|/misc/get_domain_session)!) {

            foreach my $ip (@req_hosts) {
                if ( LJ::sysban_check( 'noanon_ip', $ip ) ) {
                    $r->handler( "perl-script" );
                    $r->push_handlers( PerlResponseHandler => \&blocked_anon );
                    return OK;
                }
            }
        }
    }

    # check for sysbans on ip address, and block the ip address completely
    unless ( $LJ::BLOCKED_BOT_URI && index( $uri, $LJ::BLOCKED_BOT_URI ) == 0 ) {
        foreach my $ip (@req_hosts) {
            if ( LJ::sysban_check( 'ip', $ip ) ) {
                $r->handler( "perl-script" );
                $r->push_handlers( PerlResponseHandler => \&blocked_bot );
                return OK;
            }

            # determine if this IP is one of the tor exits and set a note on the request
            $r->notes->{via_tor_exit} = 1 if ip_is_via_tor( $ip );
        }
        if ( LJ::Hooks::run_hook( "forbid_request", $r ) ) {
            $r->handler( "perl-script" );
            $r->push_handlers( PerlResponseHandler => \&blocked_bot );
            return OK;
        }
    }

    # see if we should setup a minimal scheme based on the initial part of the
    # user-agent string; FIXME: maybe this should do more than just look at the
    # initial letters?
    if (my $ua = $r->headers_in->{'User-Agent'}) {
        if (($ua =~ /^([a-z]+)/i) && $LJ::MINIMAL_USERAGENT{$1}) {
            $r->notes->{use_minimal_scheme} = 1;
            $r->notes->{bml_use_scheme} = $LJ::MINIMAL_BML_SCHEME;
        }
    }

    my %GET = LJ::parse_args( $r->args );

    if ($LJ::IS_DEV_SERVER && $GET{'as'} =~ /^\w{1,25}$/) {
        my $ru = LJ::load_user($GET{'as'});
        LJ::set_remote($ru); # might be undef, to allow for "view as logged out"
    }

    # is this the embed module host
    if ($LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/embedcontent.bml");
    }

    my $journal_view = sub {
        my $opts = shift;
        $opts ||= {};

        my $orig_user = $opts->{'user'};
        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        my $remote = LJ::get_remote();
        my $u = LJ::load_user($orig_user);

        # do redirects:
        # -- uppercase usernames
        # -- users with hyphens/underscores, except users from external domains (see table 'domains')
        if ( $orig_user ne lc($orig_user) ||
            $orig_user =~ /[_-]/ && $u && $u->journal_base !~ m!^http://$host!i && $opts->{'vhost'} !~ /^other:/) {

            my $newurl = $uri;

            # if we came through $opts->{vhost} eq "users" path above, then
            # the s/// below will not match and there will be a leading /,
            # so the s/// leaves a leading slash as well so that $newurl is
            # consistent for the concatenation before redirect
            $newurl =~ s!^/(users/|community/|~)\Q$orig_user\E!/!;
            $newurl = $u->journal_base . "$newurl$args_wq" if $u;
            return redir($r, $newurl);
        }

        # check if this entry or journal contains adult content
        if ( LJ::is_enabled( 'adult_content' ) ) {
            # force remote to be checked
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            my $entry = $opts->{ljentry};
            my $poster;

            my $adult_content = "none";
            if ($u && $entry) {
                $adult_content = $entry->adult_content_calculated || $u->adult_content_calculated;
                $poster = $entry->poster;
            } elsif ($u) {
                $adult_content = $u->adult_content_calculated;
            }

            # we should show the page (no interstitial) if:
            # the viewed user is deleted / suspended OR
            # the entry is specified but invalid OR
            # the remote user owns the journal we're viewing OR
            # the remote user posted the entry we're viewing
            my $should_show_page = ( $u && ! $u->is_visible ) ||
                                   ( $entry && ! $entry->valid ) ||
                                   ( $remote &&
                                       ( $remote->can_manage( $u ) || ( $entry && $remote->equals( $poster ) ) )
                                   );

            my %journal_pages = (
                read => 1,
                archive => 1,
                month => 1,
                day => 1,
                tag => 1,
                entry => 1,
                reply => 1,
                lastn => 1,
            );
            my $is_journal_page = !$opts->{mode} || $journal_pages{$opts->{mode}};

            if ($adult_content ne "none" && $is_journal_page && !$should_show_page) {
                my $returl = "http://$host" . $r->uri . "$args_wq";

                LJ::set_active_journal( $u );
                $r->pnotes->{user} = $u;
                $r->pnotes->{entry} = $entry if $entry;
                $r->notes->{returl} = $returl;

                unless ( DW::Logic::AdultContent->user_confirmed_page( user => $remote, journal => $u, entry => $entry, adult_content => $adult_content ) ) {
                    # logged in users with a defined age of under 18 are blocked from explicit adult content
                    # logged in users with a defined age of under 18 are given a confirmation page for adult concepts depending on their settings
                    # logged in users with a defined age of 18 or older are given confirmation pages for adult content depending on their settings
                    # logged in users without defined ages and logged out users are given confirmation pages for all adult content
                    if ( $adult_content eq "explicit" && $remote && $remote->is_minor ) {
                        return $bml_handler->( DW::Logic::AdultContent->adult_interstitial_path( type => 'explicit_blocked' ) );
                    } else {
                        my $hide_adult_content = $remote ? $remote->hide_adult_content : "concepts";
                        if ( $adult_content eq "explicit" && $hide_adult_content ne "none" ) {
                            return $bml_handler->( DW::Logic::AdultContent->adult_interstitial_path( type => 'explicit' ) );
                        } elsif ( $adult_content eq "concepts" && $hide_adult_content eq "concepts" ) {
                            return $bml_handler->( DW::Logic::AdultContent->adult_interstitial_path( type => 'concepts' ) );
                        }
                    }
                }
            }
        }

        if ($opts->{'mode'} eq "info") {
            my $u = LJ::load_user($opts->{user})
                or return 404;
            my $mode = $GET{mode} eq 'full' ? '?mode=full' : '';
            return redir($r, $u->profile_url . $mode);
        }

        if ($opts->{'mode'} eq "profile") {
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            $r->notes->{_journal} = $opts->{user};

            # this is the notes field that all other s1/s2 pages use.
            # so be consistent for people wanting to read it.
            # _journal above is kinda deprecated, but we'll carry on
            # its behavior of meaning "whatever the user typed" to be
            # passed to the profile BML page, whereas this one only
            # works if journalid exists.
            if (my $u = LJ::load_user($opts->{user})) {
                $r->notes->{journalid} = $u->{userid};
            }

            my $file = LJ::Hooks::run_hook("profile_bml_file");
            $file ||= $LJ::PROFILE_BML_FILE || "profile.bml";
            return $bml_handler->("$LJ::HOME/htdocs/$file");
        }

        if ($opts->{'mode'} eq "update") {
            my $u = LJ::load_user($opts->{user})
                or return 404;

            return redir($r, "$LJ::SITEROOT/update.bml?usejournal=".$u->{'user'});
        }

        %RQ = %$opts;

        if ($opts->{mode} eq "data" && $opts->{pathextra} =~ m!^/(\w+)(/.*)?!) {
            my $remote = LJ::get_remote();
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            my ($mode, $path) = ($1, $2);

            if ($mode eq "customview") {
                $r->handler("perl-script");
                $r->push_handlers(PerlResponseHandler => \&customview_content);
                return OK;
            }
            if (my $handler = LJ::Hooks::run_hook("data_handler:$mode", $RQ{'user'}, $path)) {
                $r->handler("perl-script");
                $r->push_handlers(PerlResponseHandler => $handler);
                return OK;
            }
        }

        $r->handler("perl-script");
        $r->push_handlers(PerlResponseHandler => \&journal_content);
        return OK;
    };

    my $determine_view = sub {
        my ($user, $vhost, $uuri) = @_;
        my $mode = undef;
        my $pe;
        my $ljentry;

        # if favicon, let filesystem handle it, for now, until
        # we have per-user favicons.
        return DECLINED if $uuri eq "/favicon.ico";

        # see if there is a modular handler for this URI
        my $ret = LJ::URI->handle($uuri, $r);
        $ret = DW::Routing->call( username => $user ) unless defined $ret;
        return $ret if defined $ret;

        if ($uuri =~ m#^/tags(.*)#) {
            return redir($r, "/tag$1");
        }

        if ($uuri eq "/__setdomsess") {
            return redir( $r, LJ::Session->setdomsess_handler );
        }

        if ($uuri =~ m#^/calendar(.*)#) {
            return redir($r, "/archive$1");
        }

        if ($uuri =~ m#^/(\d+)\.html$#) {
            my $u = LJ::load_user($user)
                or return 404;

            $ljentry = LJ::Entry->new($u, ditemid => $1);
            if ($GET{'mode'} eq "reply" || $GET{'replyto'} || $GET{'edit'}) {
                $mode = "reply";
            } else {
                $mode = "entry";
            }
        } elsif ($uuri =~ m#^/(\d\d\d\d)(?:/(\d\d)(?:/(\d\d))?)?(/?)$#) {
            my ($year, $mon, $day, $slash) = ($1, $2, $3, $4);
            unless ($slash) {
                my $u = LJ::load_user($user)
                    or return 404;
                my $proper = $u->journal_base . "/$year";
                $proper .= "/$mon" if defined $mon;
                $proper .= "/$day" if defined $day;
                $proper .= "/";
                return redir($r, $proper);
            }

            # the S1 ljviews code looks at $opts->{'pathextra'}, because
            # that's how it used to do it, when the pathextra was /day[/yyyy/mm/dd]
            $pe = $uuri;

            if (defined $day) {
                $mode = "day";
            } elsif (defined $mon) {
                $mode = "month";
            } else {
                $mode = "archive";
            }

        } elsif ($uuri =~ m!
                 /([a-z\_]+)?           # optional /<viewname>
                 (.*)                   # path extra: /ReadingFilter, for example
                 !x && ($1 eq "" || defined $LJ::viewinfo{$1}))
        {
            ($mode, $pe) = ($1, $2);
            $mode ||= "" unless length $pe;  # if no pathextra, then imply 'lastn'

            # redirect old-style URLs to new versions:
            if ($mode =~ /^day|calendar$/ && $pe =~ m!^/\d\d\d\d!) {
                my $newuri = $uri;
                $newuri =~ s!$mode/(\d\d\d\d)!$1!;
                return redir($r, LJ::journal_base($user) . $newuri);
            } elsif ($mode eq 'rss') {
                # code 301: moved permanently, update your links.
                return redir($r, LJ::journal_base($user) . "/data/rss$args_wq", 301);
            } elsif ($mode eq 'tag') {

                # tailing slash on here to prevent a second redirect after this one
                return redir($r, LJ::journal_base($user) . "$uri/") unless $pe;
                if ($pe eq '/') {
                    # tag list page
                    $mode = 'tag';
                    $pe = undef;
                } else {
                    # filtered lastn page
                    $mode = 'lastn';

                    # prepend /tag so that lastn knows to do tag filtering
                    $pe = "/tag$pe";
                }
            } elsif ($mode eq 'security') {
                # tailing slash on here to prevent a second redirect after this one
                return redir($r, LJ::journal_base($user) . "$uri/") unless $pe;
                # filtered lastn page
                $mode = 'lastn';

                # prepend /security so that lastn knows to do security filtering
                $pe = "/security$pe";

            }
        } elsif (($vhost eq "users" || $vhost =~ /^other:/) &&
                 $uuri eq "/robots.txt") {
            $mode = "robots_txt";
        } else {
            my $key = $uuri;
            $key =~ s!^/!!;
            my $u = LJ::load_user($user)
                or return 404;
        }

        return undef unless defined $mode;

        # Now that we know ourselves to be at a sensible URI, redirect renamed
        # journals. This ensures redirects work sensibly for all valid paths
        # under a given username, without sprinkling redirects everywhere.
        my $u = LJ::load_user($user);
        if ( $u && $u->is_redirect && $u->is_renamed ) {
            my $renamedto = $u->prop( 'renamedto' );
            if ($renamedto ne '') {
                my $redirect_url = ($renamedto =~ m!^https?://!) ? $renamedto : LJ::journal_base($renamedto, $vhost) . $uuri . $args_wq;
                return redir($r, $redirect_url, 301);
            }
        }

        return $journal_view->({
            'vhost' => $vhost,
            'mode' => $mode,
            'args' => $args,
            'pathextra' => $pe,
            'user' => $user,
            'ljentry' => $ljentry,
        });
    };

    # flag if we hit a domain that was configured as a "normal" domain
    # which shouldn't be inspected for its domain name.  (for use with
    # Akamai and other CDN networks...)
    my $skip_domain_checks = 0;

    # user domains
    if (($LJ::USER_VHOSTS || $LJ::ONLY_USER_VHOSTS) &&
        $host =~ /^([\w\-]{1,25})\.\Q$LJ::USER_DOMAIN\E$/ &&
        $1 ne "www" &&

        # 1xx: info, 2xx: success, 3xx: redirect, 4xx: client err, 5xx: server err
        # let the main server handle any errors
        $r->status < 400)
    {
        if ( $is_ssl ) {
            # FIXME: Remove when we are ready for SSL in userspace
            return redir($r, LJ::create_url( undef, ssl => 0, keep_args => 1 ) )
                    if $r->method eq "GET" || $r->method eq "HEAD";
            return 404;
        }

        my $user = $1;

        # see if the "user" is really functional code
        my $func = $LJ::SUBDOMAIN_FUNCTION{$user};

        if ($func eq "normal") {
            # site admin wants this domain to be ignored and treated as if it
            # were "www", so set this flag so the custom "OTHER_VHOSTS" check
            # below fails.
            $skip_domain_checks = 1;

        } elsif ($func eq "cssproxy") {

            return $bml_handler->("$LJ::HOME/htdocs/extcss/index.bml");

        } elsif ($func eq 'support') {
            return redir($r, "$LJ::SITEROOT/support/");

        } elsif ($func eq 'shop') {

            return redir($r, "$LJ::SITEROOT/shop$uri");

        } elsif ($func eq 'mobile') {

            return redir($r, "$LJ::SITEROOT/mobile$uri");

        } elsif (ref $func eq "ARRAY" && $func->[0] eq "changehost") {

            return redir($r, "http://$func->[1]$uri$args_wq");

        } elsif ($uri =~ m!^/(?:talkscreen|delcomment)\.bml!) {
            # these URLs need to always work for the javascript comment management code
            # (JavaScript can't do cross-domain XMLHttpRequest calls)
            return DECLINED;

        } elsif ($func eq "journal") {

            unless ($uri =~ m!^/(\w{1,25})(/.*)?$!) {
                return DECLINED if $uri eq "/favicon.ico";
                my $redir = LJ::Hooks::run_hook("journal_subdomain_redirect_url",
                                         $host, $uri);
                return redir($r, $redir) if $redir;
                return 404;
            }
            ($user, $uri) = ($1, $2);
            $uri ||= "/";

            # redirect them to their canonical URL if on wrong host/prefix
            if (my $u = LJ::load_user($user)) {
                my $canon_url = $u->journal_base;
                unless ($canon_url =~ m!^http://$host!i || $LJ::DEBUG{'user_vhosts_no_wronghost_redirect'}) {
                    return redir($r, "$canon_url$uri$args_wq");
                }
            }

            my $view = $determine_view->($user, "safevhost", $uri);
            return $view if defined $view;

        } elsif ($func) {
            my $code = {
                'userpics' => \&userpic_trans,
                'files' => \&files_trans,
            };
            return $code->{$func}->($r) if $code->{$func};
            return 404;  # bogus ljconfig
        } else {
            my $view = $determine_view->($user, "users", $uri);
            return $view if defined $view;
            return 404;
        }
    }

    # custom used-specified domains
    if ($LJ::OTHER_VHOSTS && !$skip_domain_checks &&
        $host !~ /$LJ::DOMAIN$/ &&
        $host =~ /\./ &&
        $host =~ /[^\d\.]/)
    {
        my $dbr = LJ::get_db_reader();
        my $checkhost = lc( $host );
        $checkhost =~ s/^www\.//i;
        my $key = "domain:$checkhost";
        my $userid = LJ::MemCache::get( $key );
        unless (defined $userid) {
            my $db = LJ::get_db_reader();
            ($userid) = $db->selectrow_array( qq{SELECT userid FROM domains WHERE domain=?}, undef, $checkhost );
            $userid ||= 0; ## we do cache negative results - if no user for such domain, set userid=0
            LJ::MemCache::set( $key, $userid );
        }
        my $user = LJ::load_userid( $userid );
        return 404 unless $user;

        my $view = $determine_view->( $user->user, "other:$host$hostport", $uri );
        return $view if defined $view;
        return 404;
    }

    my ( $alt_uri, $alt_path ) = resolve_path_for_uri( $r, $uri );
    if ( $alt_path ) {
        $r->uri( $alt_uri );
        $r->filename( $alt_path );
        return OK;
    }

    # userpic
    return userpic_trans($r) if $uri =~ m!^/userpic/!;

    return vgift_trans($r) if $uri =~ m!^/vgift/!;

    # front page journal
    if ($LJ::FRONTPAGE_JOURNAL) {
        my $view = $determine_view->($LJ::FRONTPAGE_JOURNAL, "front", $uri);
        return $view if defined $view;
    }

    # custom interface handler
    if ($uri =~ m!^/interface/([\w\-]+)$!) {
        my $inthandle = LJ::Hooks::run_hook("interface_handler", {
            int         => $1,
            r           => $r,
            bml_handler => $bml_handler,
        });
        return $inthandle if defined $inthandle;
    }

    # see if there is a modular handler for this URI
    my $ret = LJ::URI->handle( $uri, $r );
    $ret = DW::Routing->call( ssl => $is_ssl ) unless defined $ret;
    return $ret if defined $ret;

    # protocol support
    if ($uri =~ m!^/(?:interface/(\w+))|cgi-bin/log\.cgi!) {
        my $int = $1;
        $r->handler("perl-script");
        if ($int =~ /^xmlrpc|blogger|elsewhere_info$/) {
            $RQ{'interface'} = $int;
            $RQ{'is_ssl'} = $is_ssl;
            $r->push_handlers(PerlResponseHandler => \&interface_content);
            return OK;
        }
        return 404;
    }

    # normal (non-domain) journal view
    if (
        $uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        ([^/]+)                     # potential username
        (.*)?                       # rest
        !x && $uri !~ /\.bml/)
    {
        my ($part1, $user, $rest) = ($1, $2, $3);

        # get what the username should be
        my $cuser = LJ::canonical_username($user);
        return DECLINED unless length($cuser);

        my $srest = $rest || '/';

        # need to redirect them to canonical version
        if ($LJ::ONLY_USER_VHOSTS && ! $LJ::DEBUG{'user_vhosts_no_old_redirect'}) {
            # FIXME: skip two redirects and send them right to __setdomsess with the right
            #        cookie-to-be-set arguments.  below is the easy/slow route.
            my $u = LJ::load_user($cuser)
                or return 404;
            my $base = $u->journal_base;
            return redir($r, "$base$srest$args_wq", correct_url_redirect_code());
        }

        # redirect to canonical username and/or add slash if needed
        return redir($r, "http://$host$hostport/$part1$cuser$srest$args_wq")
            if $cuser ne $user or not $rest;

        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$part1};

        my $view = $determine_view->($user, $vhost, $rest);
        return $view if defined $view;
    }

    # customview (get an S1 journal by number)
    if ($uri =~ m!^/customview\.cgi!) {
        $r->handler("perl-script");
        $r->push_handlers(PerlResponseHandler => \&customview_content);
        return OK;
    }

    if ($uri =~ m!^/palimg/!) {
        Apache::LiveJournal::PalImg->load;
        $r->handler("perl-script");
        $r->push_handlers(PerlResponseHandler => \&Apache::LiveJournal::PalImg::handler);
        return OK;
    }

    # redirected resources
    if ($REDIR{$uri}) {
        my $new = $REDIR{$uri};
        if ($r->args) {
            $new .= ($new =~ /\?/ ? "&" : "?");
            $new .= $r->args;
        }
        return redir($r, $new, HTTP_MOVED_PERMANENTLY);
    }

    # confirm
    if ($uri =~ m!^/confirm/(\w+\.\w+)!) {
        return redir($r, "$LJ::SITEROOT/register.bml?$1");
    }

    # approve
    if ($uri =~ m!^/approve/(\w+\.\w+)!) {
        return redir($r, "$LJ::SITEROOT/approve.bml?$1");
    }

    # reject
    if ($uri =~ m!^/reject/(\w+\.\w+)!) {
        return redir($r, "$LJ::SITEROOT/reject.bml?$1");
    }

    return FORBIDDEN if $uri =~ m!^/userpics!;

    return DECLINED;
}

sub userpic_trans
{
    my $r = shift;
    return 404 unless $r->uri =~ m!^/(?:userpic/)?(\d+)/(\d+)$!;
    my ($picid, $userid) = ($1, $2);

    $r->notes->{codepath} = "img.userpic";

    # redirect to the correct URL if we're not at the right one,
    # and unless CDN stuff is in effect...
    unless ($LJ::USERPIC_ROOT ne $LJ::USERPICROOT_BAK) {
        my $host = $r->headers_in->{"Host"};
        unless (    $LJ::USERPIC_ROOT =~ m!^http://\Q$host\E!i
                    || $LJ::USERPIC_ROOT_CDN && $LJ::USERPIC_ROOT_CDN =~ m!^http://\Q$host\E!i
                    || $host eq '127.0.0.1' # FIXME: lame hack for DW config
        ) {
            return redir($r, "$LJ::USERPIC_ROOT/$picid/$userid");
        }
    }

    # we can safely do this without checking since we never re-use
    # picture IDs and don't let the contents get modified
    return HTTP_NOT_MODIFIED if $r->headers_in->{'If-Modified-Since'};

    $RQ{'picid'} = $picid;
    $RQ{'pic-userid'} = $userid;

    if ($USERPIC{'use_disk_cache'}) {
        my @dirs_make;
        my $file;

        if ($picid =~ /^\d*(\d\d)(\d\d\d)$/) {
            push @dirs_make, ("$USERPIC{'cache_dir'}/$2",
                              "$USERPIC{'cache_dir'}/$2/$1");
            $file = "$USERPIC{'cache_dir'}/$2/$1/$picid-$userid";
        } else {
            my $mod = sprintf("%03d", $picid % 1000);
            push @dirs_make, "$USERPIC{'cache_dir'}/$mod";
            $file = "$USERPIC{'cache_dir'}/$mod/p$picid-$userid";
        }

        foreach (@dirs_make) {
            next if -d $_;
            mkdir $_, 0777;
        }

        # set both, so we can compared later if they're the same,
        # and thus know if directories were created (if not,
        # apache will give us a pathinfo)
        $RQ{'userpicfile'} = $file;
        $r->filename($file);
    }

    $r->handler("perl-script");
    $r->push_handlers(PerlResponseHandler => \&userpic_content);
    return OK;
}

sub userpic_content
{
    my $r = shift;
    my $file = $r->filename;

    my $picid = $RQ{'picid'};
    my $userid = $RQ{'pic-userid'}+0;

    # will we try to use disk cache?
    my $disk_cache = $USERPIC{'use_disk_cache'} &&
        $file eq $RQ{'userpicfile'};

    my ($data, $lastmod);
    my $need_cache;

    my $mime = "image/jpeg";
    my $set_mime = sub {
        my $data = shift;
        if ($data =~ /^GIF/) { $mime = "image/gif"; }
        elsif ($data =~ /^\x89PNG/) { $mime = "image/png"; }
    };
    my $size;

    my $send_headers = sub {
        $size = $_[0] if @_;
        $size ||= 0;
        $r->content_type( $mime );
        $r->headers_out->{"Content-length"} = $size + 0;
        $r->headers_out->{"Cache-Control"} = "no-transform";
        $r->headers_out->{"Last-Modified"} = LJ::time_to_http($lastmod);
    };

    # Load the user object and pic and make sure the picture is viewable
    my $u = LJ::load_userid($userid);
    my $pic = LJ::Userpic->get( $u, $picid, { no_expunged => 1 } )
        or return NOT_FOUND;

    # Read the mimetype from the pichash if dversion 7
    $mime = $pic->mimetype;

    ### Handle reproxyable requests

    # For dversion 7+ and mogilefs userpics, follow this path
    if ( $pic->in_mogile ) {
        my $key = $u->mogfs_userpic_key( $picid );
        my $memkey = [$picid, "mogp.up.$picid"];
        mogile_fetch( $r, $key, $memkey, 'userpics', $send_headers );
        return OK;
    }

    # try to get it from disk if in disk-cache mode
    if ($disk_cache) {
        if (-s $r->finfo) {
            die "Reimplement me please.\n";
#            $lastmod = (stat _)[9];
#            $size = -s _;
#            my $fh = Apache::File->new($file);
#            my $magic;
#            read($fh, $magic, 4);
#            $set_mime->($magic);
#            $send_headers->();
#            $r->print($magic);
#            $r->send_fd($fh);
#            $fh->close();
#            return OK;
        } else {
            $need_cache = 1;
        }
    }

    # else, get it from db.
    unless ($data) {
        $lastmod = $pic->pictime;

        my $dbb = LJ::get_cluster_reader( $u );
        return SERVER_ERROR unless $dbb;
        $data = $dbb->selectrow_array( "SELECT imagedata FROM userpicblob2 WHERE " .
                                       "userid=$userid AND picid=$picid" );
    }

    return NOT_FOUND unless $data;

    if ($need_cache) {
        # make $realfile /userpic-userid, and $file /userpic
        my $realfile = $file;
        unless ($file =~ s/-\d+$//) {
            $realfile .= "-$userid";
        }

        # delete short file on Unix if it exists
        unlink $file if $USERPIC{'symlink'} && -f $file;

        # write real file.
        open (F, ">$realfile"); print F $data; close F;

        # make symlink, or duplicate file (if on Windows)
        my $symtarget = $realfile;  $symtarget =~ s!.+/!!;
        unless (eval { symlink($symtarget, $file) }) {
            open (F, ">$file"); print F $data; close F;
        }
    }

    $set_mime->($data);
    $size = length($data);
    $send_headers->();
    $r->print($data) unless $r->header_only;
    return OK;
}

sub files_trans
{
    my $r = shift;
    return 404 unless $r->uri =~ m!^/(\w{1,25})/(\w+)(/\S+)!;
    my ($user, $domain, $rest) = ($1, $2, $3);

    if (my $handler = LJ::Hooks::run_hook("files_handler:$domain", $user, $rest)) {
        $r->notes->{codepath} = "files.$domain";
        $r->handler("perl-script");
        $r->push_handlers(PerlResponseHandler => $handler);
        return OK;
    }
    return 404;
}

sub vgift_trans
{
    my $r = shift;
    return 404 unless $r->uri =~ m!^/vgift/(\d+)/(\w+)$!;
    my ( $picid, $picsize ) = ( $1, $2 );
    return 404 unless $picsize =~ /^(?:small|large)$/;

    $r->notes->{codepath} = "img.vgift";

    # we can safely do this without checking
    # unless we're using the admin interface
    return HTTP_NOT_MODIFIED if $r->headers_in->{'If-Modified-Since'}
        && $r->headers_in->{'Referer'} !~ m!^\Q$LJ::SITEROOT\E$/admin/!;

    $RQ{picid} = $picid;
    $RQ{picsize} = $picsize;

    $r->handler( "perl-script" );
    $r->push_handlers( PerlResponseHandler => \&vgift_content );
    return OK;
}

sub vgift_content
{
    my $r = shift;
    my $picid = $RQ{picid};
    my $picsize = $RQ{picsize};

    my $vg = DW::VirtualGift->new( $picid );
    my $mime = $vg->mime_type( $picsize );
    return NOT_FOUND unless $mime;

    my $size;

    my $send_headers = sub {
        $size = $_[0] if @_;
        $size ||= 0;
        $r->content_type( $mime );
        $r->headers_out->{"Content-length"} = $size + 0;
        $r->headers_out->{"Cache-Control"} = "no-transform";
    };

    my $key = $vg->img_mogkey( $picsize );
    my $memkey = $vg->img_memkey( $picsize ); #[$picid, "mogp.vg.$picsize.$picid"];
    mogile_fetch( $r, $key, $memkey, 'vgifts', $send_headers );
    return OK;
}

sub journal_content
{
    my $r = shift;
    my $uri = $r->uri;
    my %GET = LJ::parse_args( $r->args );

    if ($RQ{'mode'} eq "robots_txt")
    {
        my $u = LJ::load_user($RQ{'user'});
        return 404 unless $u;

        $u->preload_props("opt_blockrobots", "adult_content");
        $r->content_type("text/plain");
        my @extra = LJ::Hooks::run_hook("robots_txt_extra", $u), ();
        $r->print($_) foreach @extra;
        $r->print("User-Agent: *\n");
        if ($u->should_block_robots) {
            $r->print("Disallow: /\n");

            # FOAF doesn't contain journal content
            $r->print("\n# If you also support the allow directive let us know\n");
            foreach (qw/Googlebot Slurp Teoma/) {
                $r->print("User-Agent: $_\n");
                # Some bots ignore generic section if a more specific on exists
                $r->print("Disallow: /\n");
                $r->print("Allow: /data/foaf\n");
                $r->print("\n");
            }
        }
        return OK;
    }

    # handle HTTP digest authentication
    if ($GET{'auth'} eq 'digest' ||
        $r->headers_in->{"Authorization"} =~ /^Digest/) {
        my $res = LJ::auth_digest($r);
        unless ($res) {
            $r->content_type("text/html");
            $r->print("<b>Digest authentication failed.</b>");
            return OK;
        }
    }

    my $criterr = 0;

    my $remote = LJ::get_remote({
        criterr      => \$criterr,
    });

    return remote_domsess_bounce() if LJ::remote_bounce_url();

    # check for faked cookies here, since this is pretty central.
    if ($criterr) {
        $r->status_line("500 Invalid Cookies");
        $r->content_type("text/html");

        # reset all cookies
        foreach my $dom ( "", $LJ::DOMAIN, $LJ::COOKIE_DOMAIN ) {
            DW::Request->get->add_cookie(
                name     => 'ljsession',
                expires  => LJ::time_to_cookie(1),
                domain   => $dom ? $dom : undef,
                path     => '/',
                httponly => 1
            );
        }

        $r->print("Invalid cookies.  Try <a href='$LJ::SITEROOT/logout.bml'>logging out</a> and then logging back in.\n");
        $r->print("<!-- xxxxxxxxxxxxxxxxxxxxxxxx -->\n") for (0..100);
        return OK;
    }


    # LJ::make_journal() will set this flag if the pages are
    # viewed without using S2 (e.g. lynx, format=light, which
    # can't do EntryPage or MonthPage), in which
    # case it's our job to invoke the legacy BML page.
    my $handle_with_bml = 0;

    # or this flag for pages that are from siteviews and expect
    # to be processed by /misc/siteviews to get sitescheme around them
    my $handle_with_siteviews = 0;

    my %headers = ();
    my $opts = {
        'r'         => $r,
        'headers'   => \%headers,
        'args'      => $RQ{'args'},
        'getargs'   => \%GET,
        'vhost'     => $RQ{'vhost'},
        'pathextra' => $RQ{'pathextra'},
        'header'    => {
            'If-Modified-Since' => $r->headers_in->{"If-Modified-Since"},
        },
        'handle_with_bml_ref' => \$handle_with_bml,
        'handle_with_siteviews_ref' => \$handle_with_siteviews,
        'siteviews_extra_content' => {},
        'ljentry' => $RQ{'ljentry'},
    };

    $r->notes->{view} = $RQ{mode};
    my $user = $RQ{'user'};

    my $html = LJ::make_journal($user, $RQ{'mode'}, $remote, $opts);

    # Allow to add extra http-header or even modify html
    LJ::Hooks::run_hooks("after_journal_content_created", $opts, \$html) unless $handle_with_siteviews;

    # check for redirects
    if ( $opts->{internal_redir} ) {
        my $int_redir = DW::Routing->call( uri => $opts->{internal_redir} );
        if ( defined $int_redir ) {
            # we got a match; clear the request cache and return DECLINED.
            LJ::start_request();
            return DECLINED;
        }
    }
    return redir($r, $opts->{'redir'}) if $opts->{'redir'};
    return $opts->{'handler_return'} if defined $opts->{'handler_return'};

    # if LJ::make_journal() indicated it can't handle the request:
    # only if HTML is set, otherwise leave it alone so the user
    # gets "messed up template definition", cause something went wrong.
    if ( $handle_with_siteviews && $html ) {
        return DW::Template->render_string( $html, $opts->{siteviews_extra_content} );
    } elsif ( $handle_with_bml ) {
        my $args = $r->args;
        my $args_wq = $args ? "?$args" : "";

        # historical: can't show BML on user domains... redirect them.  nowadays
        # not a big deal, but debug option retained for other sites w/ old BML schemes
        if ($LJ::DEBUG{'no_bml_on_user_domains'}
            && $RQ{'vhost'} eq "users" && ($RQ{'mode'} eq "entry" ||
                                           $RQ{'mode'} eq "reply" ||
                                           $RQ{'mode'} eq "month"))
        {
            my $u = LJ::load_user($RQ{'user'});
            my $base = "$LJ::SITEROOT/users/$RQ{'user'}";
            $base = "$LJ::SITEROOT/community/$RQ{'user'}" if $u && $u->is_community;
            return redir($r, "$base$uri$args_wq");
        }

        if ($RQ{'mode'} eq "entry" || $RQ{'mode'} eq "reply") {
            my $filename = $RQ{'mode'} eq "entry" ?
                "$LJ::HOME/htdocs/talkread.bml" :
                "$LJ::HOME/htdocs/talkpost.bml";
            $r->notes->{_journal} = $RQ{user};
            $r->notes->{bml_filename} = $filename;
            return Apache::BML::handler($r);
        }

        if ($RQ{'mode'} eq "month") {
            my $filename = "$LJ::HOME/htdocs/view/index.bml";
            $r->notes->{_journal} = $RQ{user};
            $r->notes->{bml_filename} = $filename;
            return Apache::BML::handler($r);
        }
    }

    my $status = $opts->{'status'} || "200 OK";
    $opts->{'contenttype'} ||= $opts->{'contenttype'} = "text/html";
    if ($opts->{'contenttype'} =~ m!^text/! &&
        $LJ::UNICODE && $opts->{'contenttype'} !~ /charset=/) {
        $opts->{'contenttype'} .= "; charset=utf-8";
    }

    # Set to 1 if the code should generate junk to help IE
    # display a more meaningful error message.
    my $generate_iejunk = 0;

    if ($opts->{'badargs'})
    {
        # No special information to give to the user, so just let
        # Apache handle the 404
        return 404;
    }
    elsif ($opts->{'baduser'})
    {
        $status = "404 Unknown User";
        $html = "<h1>Unknown User</h1><p>There is no user <b>$user</b> at <a href='$LJ::SITEROOT'>$LJ::SITENAME.</a></p>";
        $generate_iejunk = 1;
    }
    elsif ($opts->{'badfriendgroup'})
    {
        # give a real 404 to the journal owner
        if ( $remote && $remote->{'user'} eq $user ) {
            return 404;

        # otherwise be vague with a 403
        } else {
            return 403;
        }

        $generate_iejunk = 1;

    } elsif ($opts->{'suspendeduser'}) {
        $status = "403 User suspended";
        $html = "<h1>Suspended User</h1>" .
                "<p>The content at this URL is from a suspended user.</p>";

        $generate_iejunk = 1;

    } elsif ($opts->{'suspendedentry'}) {
        $status = "403 Entry suspended";
        $html = "<h1>Suspended Entry</h1>" .
                "<p>The entry at this URL is suspended.  You cannot reply to it.</p>";

        $generate_iejunk = 1;

    } elsif ($opts->{'readonlyremote'} || $opts->{'readonlyjournal'}) {
        $status = "403 Read-only user";
        $html = "<h1>Read-Only User</h1>";
        $html .= $opts->{'readonlyremote'} ? "<p>You are read-only.  You cannot post comments.</p>" : "<p>This journal is read-only.  You cannot comment in it.</p>";

        $generate_iejunk = 1;
    }

    unless ($html) {
        $status = "500 Bad Template";
        $html = "<h1>Error</h1><p>User <b>$user</b> has messed up their journal template definition.</p>";
        $generate_iejunk = 1;
    }

    $r->status_line($status);
    foreach my $hname (keys %headers) {
        if (ref($headers{$hname}) && ref($headers{$hname}) eq "ARRAY") {
            foreach (@{$headers{$hname}}) {
                $r->headers_out->{$hname} = $_;
            }
        } else {
            $r->headers_out->{$hname} = $headers{$hname};
        }
    }

    $r->content_type($opts->{'contenttype'});
    $r->headers_out->{"Cache-Control"} = "private, proxy-revalidate";

    $html .= ("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 100) if $generate_iejunk;

    # Parse the page content for any temporary matches
    # defined in local config
    if (my $cb = $LJ::TEMP_PARSE_MAKE_JOURNAL) {
        $cb->(\$html);
    }


    # add stuff before </body>
    my $before_body_close = "";
    LJ::Hooks::run_hooks("insert_html_before_body_close", \$before_body_close);
    LJ::Hooks::run_hooks("insert_html_before_journalctx_body_close", \$before_body_close);

    # Insert pagestats HTML and Javascript
    $before_body_close .= LJ::PageStats->new->render( 'journal' );

    $html =~ s!</body>!$before_body_close</body>!i if $before_body_close;

    my $do_gzip = $LJ::DO_GZIP && $LJ::OPTMOD_ZLIB;
    if ($do_gzip) {
        my $ctbase = $opts->{'contenttype'};
        $ctbase =~ s/;.*//;
        $do_gzip = 0 unless $LJ::GZIP_OKAY{$ctbase};
        $do_gzip = 0 if $r->headers_in->{"Accept-Encoding"} !~ /gzip/;
    }
    my $length = length($html);
    $do_gzip = 0 if $length < 500;

    if ($do_gzip) {
        my $pre_len = $length;
        $r->notes->{bytes_pregzip} = $pre_len;
        $html = Compress::Zlib::memGzip($html);
        $length = length($html);
        $r->headers_out->{'Content-Encoding'} = 'gzip';
    }
    # Let caches know that Accept-Encoding will change content
    $r->headers_out->{'Vary'} = 'Accept-Encoding';

    $r->headers_out->{"Content-length"} = $length;
    $r->print($html) unless $r->header_only;

    return OK;
}

sub customview_content
{
    my $r = shift;
    my %FORM = $r->args;

    my $charset = "utf-8";

    if ($LJ::UNICODE && $FORM{'charset'}) {
        $charset = $FORM{'charset'};
        if ($charset ne "utf-8" && ! Unicode::MapUTF8::utf8_supported_charset($charset)) {
            $r->content_type("text/html");
            $r->print("<b>Error:</b> requested charset not supported.");
            return OK;
        }
    }

    my $ctype = "text/html";
    if ($FORM{'type'} eq "xml") {
        $ctype = "text/xml";
    }

    if ($LJ::UNICODE) {
        $ctype .= "; charset=$charset";
    }

    $r->content_type($ctype);

    my $cur_journal = LJ::Session->domain_journal;
    my $user = LJ::canonical_username($FORM{'username'} || $FORM{'user'} || $cur_journal);
    my $styleid = $FORM{'styleid'} + 0;
    my $nooverride = $FORM{'nooverride'} ? 1 : 0;

    if ($LJ::ONLY_USER_VHOSTS && $cur_journal ne $user) {
        my $u = LJ::load_user($user)
            or return 404;
        my $safeurl = $u->journal_base . "/data/customview?";
        my %get_args = %FORM;
        delete $get_args{'user'};
        delete $get_args{'username'};
        $safeurl .= join("&", map { LJ::eurl($_) . "=" . LJ::eurl($get_args{$_}) } keys %get_args);
        return redir($r, $safeurl);
    }

    my $remote;
    if ($FORM{'checkcookies'}) {
        $remote = LJ::get_remote();
    }

    my $data = (LJ::make_journal($user, "", $remote,
                 { "nocache" => $FORM{'nocache'},
                   "vhost" => "customview",
                   "nooverride" => $nooverride,
                   "styleid" => $styleid,
                   "saycharset" => $charset,
                   "args" => scalar $r->args,
                   "getargs" => \%FORM,
                   "r" => $r,
               })
          || "<b>[$LJ::SITENAME: Bad username, styleid, or style definition]</b>");

    if ($FORM{'enc'} eq "js") {
        $data =~ s/\\/\\\\/g;
        $data =~ s/\"/\\\"/g;
        $data =~ s/\n/\\n/g;
        $data =~ s/\r//g;
        $data = "document.write(\"$data\")";
    }

    if ($LJ::UNICODE && $charset ne 'utf-8') {
        $data = Unicode::MapUTF8::from_utf8({-string=>$data, -charset=>$charset});
    }

    $r->headers_out->{"Cache-Control"} = "must-revalidate";
    $r->headers_out->{"Content-Length"} = length($data);
    $r->print($data) unless $r->header_only;
    return OK;
}

sub correct_url_redirect_code {
    if ($LJ::CORRECT_URL_PERM_REDIRECT) {
        return HTTP_MOVED_PERMANENTLY;
    }
    return REDIRECT;
}

sub interface_content
{
    my $r = shift;
    my $args = $r->args;

    if ($RQ{'interface'} eq "xmlrpc") {
        return 404 unless LJ::ModuleCheck->have('XMLRPC::Transport::HTTP');
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_to('LJ::XMLRPC')
            -> handle($r);
        return OK;
    }

    if ($RQ{'interface'} eq "blogger") {
        Apache::LiveJournal::Interface::Blogger->load;
        return 404 unless LJ::ModuleCheck->have('XMLRPC::Transport::HTTP');
        my $pkg = "Apache::LiveJournal::Interface::Blogger";
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_with({ 'blogger' => $pkg })
            -> dispatch_to($pkg)
            -> handle($r);
        return OK;
    }

    $r->content_type("text/plain");
    $r->print("Unknown interface.");
    return OK;
}

sub db_logger
{
    # FIXME: ModPerl 2.0: how to get last item, bucket brigade? ->last here bad
    return;

    my $r = shift;
    my $rl = $r->last;

    $r->pnotes->{did_lj_logging} = 1;

    # these are common enough, it's worth doing it here, early, before
    # constructing the accesslogrecord.
    if ($LJ::DONT_LOG_IMAGES) {
        my $uri = $r->uri;
        my $ctype = $rl->content_type;
        $ctype =~ s/;.*//;  # strip charset
        return if $ctype =~ m!^image/!;
        return if $uri =~ m!^/(img|userpic)/!;
    }

    my $rec = LJ::AccessLogRecord->new($r);
    my @sinks = (
                 LJ::AccessLogSink::Database->new,
                 LJ::AccessLogSink::DInsertd->new,
                 LJ::AccessLogSink::DBIProfile->new,
                 );

    if (@LJ::EXTRA_ACCESS_LOG_SINKS) {
        # will convert them to objects from class/ctor-arg arrayrefs
        push @sinks, LJ::AccessLogSink->extra_log_sinks;
    }

    foreach my $sink (@sinks) {
        $sink->log($rec);
    }
}

sub mogile_fetch {
    my ( $r, $key, $memkey, $class, $send_headers ) = @_;

    if ( !$LJ::REPROXY_DISABLE{$class} &&
         $r->headers_in->{'X-Proxy-Capabilities'} &&
         $r->headers_in->{'X-Proxy-Capabilities'} =~ m{\breproxy-file\b}i ) {

        my $zone = $r->headers_in->{'X-MogileFS-Explicit-Zone'} || undef;
        $memkey->[1] .= ".$zone" if $zone;

        my $cache_for = $LJ::MOGILE_PATH_CACHE_TIMEOUT || 3600;

        my $paths = LJ::MemCache::get( $memkey );
        unless ( $paths ) {
            # load and add to memcache
            my @paths = LJ::mogclient()->get_paths( $key, { noverify => 1, zone => $zone } );
            $paths = \@paths;
            LJ::MemCache::add( $memkey, $paths, $cache_for ) if @paths;
        }

        if ( defined $paths->[0] && $paths->[0] =~ m/^http:/ ) {
            # reproxy url
            $r->headers_out->{'X-REPROXY-CACHE-FOR'} = "$cache_for; Last-Modified Content-Type";
            $r->headers_out->{'X-REPROXY-URL'} = join( ' ', @$paths );
        } else {
            # reproxy file
            $r->headers_out->{'X-REPROXY-FILE'} = $paths->[0];
        }

        $send_headers->();

    } else {  # no reproxy
        my $data = LJ::mogclient()->get_file_data( $key );
        return NOT_FOUND unless $data;
        $send_headers->( length $$data );
        $r->print( $$data ) unless $r->header_only;
    }
}

package LJ::Protocol;
use Encode();

sub xmlrpc_method {
    my $method = shift;
    shift;   # get rid of package name that dispatcher includes.
    my $req = shift;

    if (@_) {
        # don't allow extra arguments
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message(202))
            ->faultcode(202);
    }
    my $error = 0;
    if (ref $req eq "HASH") {
        # get rid of the UTF8 flag in scalars
        while ( my ($k, $v) = each %$req ) {
            $req->{$k} = Encode::encode_utf8($v) if Encode::is_utf8($v);
        }
    }
    my $res = LJ::Protocol::do_request($method, $req, \$error);
    if ($error) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($error))
            ->faultcode(substr($error, 0, 3));
    }

    # Perl is untyped language and XML-RPC is typed.
    # When library XMLRPC::Lite tries to guess type, it errors sometimes
    # (e.g. string username goes as int, if username contains digits only).
    # As workaround, we can select some elements by it's names
    # and label them by correct types.

    # Key - field name, value - type.
    my %lj_types_map = (
        journalname => 'string',
        fullname => 'string',
        username => 'string',
        poster => 'string',
        postername => 'string',
        name => 'string',
    );

    my $recursive_mark_elements;
    $recursive_mark_elements = sub {
        my $structure = shift;
        my $ref = ref($structure);

        if ($ref eq 'HASH') {
            foreach my $hash_key (keys %$structure) {
                if (exists($lj_types_map{$hash_key})) {
                    $structure->{$hash_key} = SOAP::Data
                            -> type($lj_types_map{$hash_key})
                            -> value($structure->{$hash_key});
                } else {
                    $recursive_mark_elements->($structure->{$hash_key});
                }
            }
        } elsif ($ref eq 'ARRAY') {
            foreach my $idx (@$structure) {
                $recursive_mark_elements->($idx);
            }
        }
    };

    $recursive_mark_elements->($res);

    return $res;
}


1;
