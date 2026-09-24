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

package LJ;
use strict;

use Carp;
use POSIX;
use Digest::MD5;
use Digest::SHA1;

use DW::AccountSwitcher;
use DW::Auth::Challenge;
use DW::External::Site;
use DW::Request;
use DW::Formats;
use LJ::Utils;
use LJ::Global::Constants;
use LJ::Event;
use LJ::Subscription::Pending;
use LJ::Directory::Search;
use LJ::Directory::Constraint;
use LJ::PageStats;
use LJ::JSON;
use LJ::Lang;

# <LJFUNC>
# name: LJ::img
# des: Returns an HTML &lt;img&gt; or &lt;input&gt; tag to an named image
#      code, which each site may define with a different image file with
#      its own dimensions.  This prevents hard-coding filenames & sizes
#      into the source.  The real image data is stored in LJ::Img, which
#      has default values provided in cgi-bin/LJ/Global/Img.pm but can be
#      overridden in cgi-bin/LJ/Local/Img.pm or etc/config.pl.
# args: imagecode, type?, attrs?
# des-imagecode: The unique string key to reference the image.  Not a filename,
#                but the purpose or location of the image.
# des-type: By default, the tag returned is an &lt;img&gt; tag, but if 'type'
#           is "input", then an input tag is returned.
# des-attrs: Optional hashref of other attributes.  If this isn't a hashref,
#            then it's assumed to be a scalar for the 'name' attribute for
#            input controls.
# </LJFUNC>
sub img {
    my ( $ic, $type, $attr ) = @_;
    $type //= '';    # Type is either "" or "input"

    my ( $attrs, $alt ) = ( '', '' );
    if ($attr) {
        if ( ref $attr eq "HASH" ) {
            if ( exists $attr->{alt} ) {
                $alt = LJ::ehtml( $attr->{alt} );
                delete $attr->{alt};
            }
            $attrs .= " $_=\"" . LJ::ehtml( $attr->{$_} || '' ) . "\"" foreach keys %$attr;
        }
        else {
            $attrs = " id=\"$attr\"";
        }
    }

    my $i = $LJ::Img::img{$ic};
    $alt ||= LJ::Lang::string_exists( $i->{alt} ) ? LJ::Lang::ml( $i->{alt} ) : $i->{alt};
    if ( $type eq "" ) {
        return
              "<img src=\"$LJ::IMGPREFIX$i->{src}\" width=\"$i->{width}\" "
            . "height=\"$i->{height}\" alt=\"$alt\" title=\"$alt\" "
            . "border='0'$attrs />";
    }
    if ( $type eq "input" ) {
        return
              "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" "
            . "width=\"$i->{'width'}\" height=\"$i->{'height'}\" title=\"$alt\" "
            . "alt=\"$alt\" border='0'$attrs />";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::date_to_view_links
# class: component
# des: Returns HTML of date with links to user's journal.
# args: u, date
# des-date: date in yyyy-mm-dd form.
# returns: HTML with yyyy, mm, and dd all links to respective views.
# </LJFUNC>
sub date_to_view_links {
    my ( $u, $date ) = @_;
    return unless $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;

    my ( $y, $m, $d ) = ( $1, $2, $3 );
    my $base = $u->journal_base;

    my $ret;
    $ret .= "<a href=\"$base/$y/\">$y</a>-";
    $ret .= "<a href=\"$base/$y/$m/\">$m</a>-";
    $ret .= "<a href=\"$base/$y/$m/$d/\">$d</a>";
    return $ret;
}

# <LJFUNC>
# name: LJ::auto_linkify
# des: Takes a plain-text string and changes URLs into <a href> tags (auto-linkification).
# args: str
# des-str: The string to perform auto-linkification on.
# returns: The auto-linkified text.
# </LJFUNC>
sub auto_linkify {
    my $str   = shift;
    my $match = sub {
        my $str = shift;
        if ( $str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/ ) {
            return "<a href='$1'>$1</a>$2";
        }
        else {
            return "<a href='$str'>$str</a>";
        }
    };
    $str =~ s!(https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-])! $match->( $1 ); !ge
        if defined $str;

    return $str;
}

# return 1 if URL is a safe stylesheet that S1/S2/etc can pull in.
# return 0 to reject the link tag
# return a URL to rewrite the stylesheet URL
# $href will always be present.  $host and $path may not.
sub valid_stylesheet_url {
    my ( $href, $host, $path ) = @_;
    unless ( $host && $path ) {
        return 0 unless $href =~ m!^https?://([^/]+?)(/.*)$!;
        ( $host, $path ) = ( $1, $2 );
    }

    my $cleanit = sub {

        # allow tag, if we're doing no css cleaning
        return 1 unless LJ::is_enabled('css_cleaner');

        # remove tag, if we have no CSSPROXY configured
        return 0 unless $LJ::CSSPROXY;

        # rewrite tag for CSS cleaning
        return "$LJ::CSSPROXY?u=" . LJ::eurl($href);
    };

    return 1 if $LJ::TRUSTED_CSS_HOST{$host};
    return $cleanit->() unless $host =~ /\Q$LJ::DOMAIN\E$/i;

    # let users use system stylesheets.
    return 1
        if $host eq $LJ::DOMAIN
        || $host eq $LJ::DOMAIN_WEB
        || $href =~ /^\Q$LJ::STATPREFIX\E/;

    # S2 stylesheets:
    return 1 if $path =~ m!^(/~\w+|/users/\w+|/\w+)?/res/(\d+)/stylesheet(\?\d+)?$!;

    # unknown, reject.
    return $cleanit->();
}

# <LJFUNC>
# name: LJ::make_authas_select
# des: Given a u object and some options, determines which users the given user
#      can switch to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of HTML elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'authas' - current user, gets selected in drop-down;
#           'label' - label to go before form elements;
#           'button' - button label for submit button;
#           'type' - journaltype (affects label & list filtering)
#           'selectonly' - 1 for just menu items, otherwise entire HTML block
#           'foundation' - 1 for Foundation HTML, otherwise legacy HTML
#           others - arguments to pass to $u->get_authas_list.
# </LJFUNC>
sub make_authas_select {
    my ( $u, $opts ) = @_;    # type, authas, label, button

    my $authas = $opts->{authas} || $u->user;
    my $button = $opts->{button} || LJ::Lang::ml('web.authas.btn');
    my $label  = $opts->{label}  || LJ::Lang::ml('web.authas.select.label');

    my $foundation = $opts->{foundation} || 0;

    my @list = $u->get_authas_list($opts);

    # only do most of form if there are options to select from
    if ( @list > 1 || $list[0] ne $u->user ) {
        my $menu = LJ::html_select(
            {
                name     => 'authas',
                selected => $authas,
                class    => 'hideable',
                id       => 'authas',
                style    => $foundation ? 'width: 100%' : '',
            },
            map { $_, $_ } @list
        );

        my $ret = '';
        if ( $opts->{selectonly} ) {
            $ret = $menu;
        }
        else {
            $ret = $foundation
                ? q{<div class='row collapse'><div class='columns small-3 medium-1'><label class='inline'>}
                . $label
                . q{</label></div>}
                . q{<div class='columns small-9 medium-11'><div class='row'>}
                . q{<div class="columns small-8 medium-4">}
                . $menu
                . q{</div>}
                . q{<div class='columns small-4 medium-2 end'>}
                . LJ::html_submit( undef, $button, { class => "secondary button" } )
                . q{</div>}
                . q{</div></div>}
                . q{</div>}

                # else not foundation
                : "<br/>"
                . LJ::Lang::ml( 'web.authas.select',
                { menu => $menu, username => LJ::ljuser($authas) } )
                . " "
                . LJ::html_submit( undef, $button )
                . "<br/><br/>\n";
        }

        return $ret;
    }

    # no communities to choose from, give the caller a hidden
    return LJ::html_hidden( authas => $authas );
}

# <LJFUNC>
# name: LJ::help_icon
# des: Returns HTML to show a help link/icon given a help topic, or nothing
#      if the site hasn't defined a URL for that topic.  Optional arguments
#      include HTML to place before and after the link/icon, should it
#      be returned.
# args: topic, pre?, post?
# des-topic: Help topic key.
#            See etc/config-local.pl, or [special[helpurls]] for examples.
# des-pre: HTML to place before the help icon.
# des-post: HTML to place after the help icon.
# </LJFUNC>
sub help_icon {
    return help_icon_html(@_);
}

sub help_icon_html {
    my $topic = shift;
    my $url   = $LJ::HELPURL{$topic} or return "";
    my $pre   = shift || "";
    my $post  = shift || "";
    return
          "$pre<a href=\"$url\" class=\"helplink\" target=\"_blank\">"
        . LJ::img( 'help', '' )
        . "</a>$post";
}

# <LJFUNC>
# name: LJ::error_list
# des: Returns an error bar with bulleted list of errors.
# returns: HTML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub error_list {

    # FIXME: retrofit like bad_input above?  merge?  make aliases for each other?
    my @errors = @_;
    my $ret;
    $ret .= qq{<div class="errorbar">};
    $ret .= "<strong>";
    $ret .= LJ::Lang::ml('error.procrequest');
    $ret .= "</strong><ul>";

    foreach my $ei (@errors) {
        my $err = LJ::errobj($ei) or next;
        $ret .= $err->as_bullets;
    }
    $ret .= "</ul></div>";
    return $ret;
}

# <LJFUNC>
# name: LJ::error_noremote
# des: Returns an error telling the user to log in.
# returns: Translation string "error.notloggedin"
# </LJFUNC>
sub error_noremote {
    my $r        = DW::Request->get;
    my $returnto = '';
    if ($r) {
        my $uri = $r->uri;
        if ( my $qs = $r->query_string ) {
            $uri .= '?' . $qs;
        }
        $returnto = '?returnto=' . LJ::eurl($uri);
    }
    return LJ::Lang::ml( 'error.notloggedin', { aopts => "href='$LJ::SITEROOT/login$returnto'" } );
}

# <LJFUNC>
# name: LJ::warning_list
# des: Returns a warning bar with bulleted list of warnings.
# returns: HTML showing warnings
# args: warnings*
# des-warnings: A list of warnings
# </LJFUNC>
sub warning_list {
    my @warnings = @_;
    my $ret;

    $ret .= qq{<div class="warningbar">};
    $ret .= "<strong>";
    $ret .= LJ::Lang::ml('label.warning');
    $ret .= "</strong><ul>";

    foreach (@warnings) {
        $ret .= "<li>$_</li>";
    }
    $ret .= "</ul></div>";
    return $ret;
}

# <LJFUNC>
# name: LJ::did_post
# des: Cookies should only show pages which make no action.
#      When an action is being made, check the request coming
#      from the remote user is a POST request.
# info: When web pages are using cookie authentication, you can't just trust that
#       the remote user wants to do the action they're requesting.  It's way too
#       easy for people to force other people into making GET requests to
#       a server.  What if a user requested http://server/delete_all_journal.bml,
#       and that URL checked the remote user and immediately deleted the whole
#       journal?  Now anybody has to do is embed that address in an image
#       tag and a lot of people's journals will be deleted without them knowing.
#       Cookies should only show pages which make no action.  When an action is
#       being made, check that it's a POST request.
# returns: true if REQUEST_METHOD == "POST"
# </LJFUNC>
sub did_post {
    my $r = DW::Request->get;
    return $r->did_post if $r;

    # no active request (e.g. a background job): never a POST.
    return '';
}

# <LJFUNC>
# name: LJ::robot_meta_tags
# des: Returns meta tags to instruct a robot/crawler to not index or follow links.
# returns: A string with appropriate meta tags
# </LJFUNC>
sub robot_meta_tags {
    return "<meta name=\"robots\" content=\"noindex, nofollow, noarchive\" />\n"
        . "<meta name=\"googlebot\" content=\"noindex, nofollow, noarchive, nosnippet\" />\n";
}

sub paging_bar {
    my ( $page, $pages, $opts ) = @_;

    my $self_link = $opts->{self_link}
        || sub { LJ::page_change_getargs( page => $_[0] ) };

    my $href_opts = $opts->{href_opts} || sub { '' };

    my $nav = '';
    return $nav unless $pages && $pages > 1;

    $nav .= "<p style='font-weight: bolder; margin: 0 0 .5em 0'>";
    $nav .= LJ::Lang::ml( 'ljlib.pageofpages', { page => $page, total => $pages } );
    $nav .= "</p>\n";

    my $linkify = sub {
        "<a href='" . $self_link->( $_[0] ) . "'" . $href_opts->( $_[0] ) . ">$_[1]</a>\n";
    };

    my ( $left, $right ) = ( "<b>&lt;&lt;</b>", "<b>&gt;&gt;</b>" );
    $left  = $linkify->( $page - 1, $left )  if $page > 1;
    $right = $linkify->( $page + 1, $right ) if $page < $pages;

    my @pagelinks;

    for ( my $i = 1 ; $i <= $pages ; $i++ ) {
        my $link = "[$i]";
        $link = ( $i != $page ) ? $linkify->( $i, $link ) : "<b>$link</b>";
        push @pagelinks, "<br />" if $i > 10 && ( $i == 11 || $i % 10 == 0 );
        push @pagelinks, $link;
    }

    $nav .= "$left &nbsp; ";
    $nav .= "<span style='text-align: center'>";
    $nav .= join ' ', @pagelinks;
    $nav .= "</span>";
    $nav .= " &nbsp; $right";

    return
"<div class='action-box'><div class='inner'>$nav</div></div><div class='clear-floats'></div>\n";
}

=head2 C<< LJ::page_change_getargs( %args ) >>
Returns the current URL with a modified list of GET arguments.
=cut

sub page_change_getargs {
    my %args    = @_;
    my %cu_opts = ( keep_args => 1, no_blank => 1 );

    # specified args will override keep_args
    return LJ::create_url( undef, args => \%args, %cu_opts );
}

=head2 C<< LJ::paging( $listref, $page, $pagesize ) >>
Paginate a list, returning the current page's items plus page-navigation data.
=cut

sub paging {
    my ( $listref, $page, $pagesize ) = @_;
    $page = 1 unless $page && $page == int $page;
    return unless $pagesize;    # let's not divide by zero
    my @items = @{$listref};
    my %self;

    my $newurl = sub {
        return LJ::page_change_getargs( page => $_[0] );
    };

    $self{itemcount} = scalar @items;

    $self{pages} = $self{itemcount} / $pagesize;
    $self{pages} = int( $self{pages} ) + 1
        if $self{pages} != int( $self{pages} );    # round up any fraction

    $page = 1            if $page < 1;
    $page = $self{pages} if $page > $self{pages};
    $self{page} = $page;

    $self{itemfirst} = $pagesize * ( $page - 1 ) + 1;
    $self{itemlast}  = $pagesize * $page;
    $self{itemlast}  = $self{itemcount} if $self{pages} == $page;

    my @range = ( $self{itemfirst} - 1 ) .. ( $self{itemlast} - 1 );
    $self{items} = [ @items[@range] ];

    my ( $prev, $next ) = ( $newurl->( $page - 1 ), $newurl->( $page + 1 ) );
    $self{backlink} = "<a href=\"$prev\">&lt;&lt;&lt;</a>" unless $page == 1;
    $self{nextlink} = "<a href=\"$next\">&gt;&gt;&gt;</a>" unless $page == $self{pages};

    return %self;
}

# <LJFUNC>
# class: web
# name: LJ::make_cookie
# des: Prepares cookie header lines.
# returns: An array of cookie lines.
# args: name, value, expires, path?, domain?
# des-name: The name of the cookie.
# des-value: The value to set the cookie to.
# des-expires: The time (in seconds) when the cookie is supposed to expire.
#              Set this to 0 to expire when the browser closes. Set it to
#              undef to delete the cookie.
# des-path: The directory path to bind the cookie to.
# des-domain: The domain (or domains) to bind the cookie to.
# </LJFUNC>
sub make_cookie {
    my ( $name, $value, $expires, $path, $domain ) = @_;
    my $cookie  = "";
    my @cookies = ();

    # let the domain argument be an array ref, so callers can set
    # cookies in both .foo.com and foo.com, for some broken old browsers.
    if ( $domain && ref $domain eq "ARRAY" ) {
        foreach (@$domain) {
            push( @cookies, LJ::make_cookie( $name, $value, $expires, $path, $_ ) );
        }
        return;
    }

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($expires);
    $year += 1900;

    my @day   = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    $cookie = sprintf "%s=%s", LJ::eurl($name), LJ::eurl($value);

    # this logic is confusing potentially
    unless ( defined $expires && $expires == 0 ) {
        $cookie .= sprintf "; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
            $mday, $year, $hour, $min, $sec;
    }

    $cookie .= "; path=$path"     if $path;
    $cookie .= "; domain=$domain" if $domain;
    push( @cookies, $cookie );
    return @cookies;
}

# <LJFUNC>
# name: LJ::check_referer
# class: web
# des: Checks if the user is coming from a given URI.
# args: uri?, referer?
# des-uri: string; the URI we want the user to come from.
# des-referer: string; the location the user is posting from.
#              If not supplied, will be retrieved from the active request's
#              Referer header. In general, you don't want to pass this
#              yourself unless you already have it or know there's no
#              active request to get it from.
# returns: 1 if they're coming from that URI, else undef
# </LJFUNC>
sub check_referer {
    my $uri = shift(@_) || '';
    my $referer =
           shift(@_)
        || ( DW::Request->get && DW::Request->get->header_in('Referer') )
        || '';

    # get referer and check
    return 1 unless $referer;

    my ( $origuri, $origreferer ) = ( $uri, $referer );

    # escape any regex characters, like the '.' in '.bml'
    $uri = quotemeta($uri);

    # check that the end of the uri matches exactly (no extra characters or dir levels)
    # or else that the uri is followed immediately by additional parameters
    my $checkend = '(?:$|\\?)';

    # allow us to properly check URIs without .bml extensions
    if ( $origuri =~ /\.bml($|\?)/ ) {
        $checkend = '' if $1 eq '?';
        $uri     =~ s/\\.bml($|\\\?)/$1$checkend/;
        $referer =~ s/\.bml($|\?)/$1/;
    }
    elsif ($uri) {
        $uri .= $checkend;
    }
    else {
        $uri = '(/|$)';
    }

    return 1 if $LJ::SITEROOT   && $referer =~ m!^\Q$LJ::SITEROOT\E$uri!;
    return 1 if $LJ::DOMAIN     && $referer =~ m!^https?://\Q$LJ::DOMAIN\E$uri!;
    return 1 if $LJ::DOMAIN_WEB && $referer =~ m!^https?://\Q$LJ::DOMAIN_WEB\E$uri!;
    return 1
        if $referer =~ m!^https?://([A-Za-z0-9_\-]{1,25})\.\Q$LJ::DOMAIN\E$uri!;
    return 1 if $origuri =~ m!^https?://! && $origreferer eq $origuri;

    # Dev container: $LJ::DOMAIN is empty, so match referer host against request host
    if ( $LJ::IS_DEV_SERVER && !$LJ::DOMAIN ) {
        my $r = eval { DW::Request->get };
        if ($r) {
            my $host = $r->host;
            return 1 if $referer =~ m!^https?://\Q$host\E$uri!;
        }
    }

    return undef;
}

# <LJFUNC>
# name: LJ::form_auth
# class: web
# des: Creates an authentication token to be used later to verify that a form
#      submission came from a particular user.
# args: raw?
# des-raw: boolean; If true, returns only the token (no HTML).
# returns: HTML hidden field to be inserted into the output of a page.
# </LJFUNC>
sub form_auth {
    my $raw  = shift;
    my $chal = $LJ::REQ_GLOBAL{form_auth_chal};

    unless ($chal) {
        my $remote = LJ::get_remote();
        my $id     = $remote ? $remote->id : 0;
        my $sess =
            $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;

        my $auth = join( '-', LJ::rand_chars(10), $id, $sess );
        $chal = DW::Auth::Challenge->generate( 86400, $auth );
        $LJ::REQ_GLOBAL{form_auth_chal} = $chal;
    }

    return $raw ? $chal : LJ::html_hidden( "lj_form_auth", $chal );
}

# <LJFUNC>
# name: LJ::check_form_auth
# class: web
# des: Verifies form authentication created with [func[LJ::form_auth]].
# returns: Boolean; true if the current data in %POST is a valid form, submitted
#          by the user in $remote using the current session,
#          or false if the user has changed, the challenge has expired,
#          or the user has changed session (logged out and in again, or something).
# </LJFUNC>
sub check_form_auth {
    my $formauth =
        @_
        ? shift
        : ( DW::Request->get && DW::Request->get->post_args->{'lj_form_auth'} )
        || $BMLCodeBlock::POST{'lj_form_auth'};
    return 0 unless $formauth;

    my $remote = LJ::get_remote();
    my $id     = $remote ? $remote->id : 0;
    my $sess   = $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;

    # check the attributes are as they should be
    my $attr = DW::Auth::Challenge->get_attributes($formauth);
    my ( $randchars, $chal_id, $chal_sess ) = split( /\-/, $attr );

    return 0 unless $id == $chal_id;
    return 0 unless $sess eq $chal_sess;

    # check the signature is good and not expired
    my $opts = { dont_check_count => 1 };    # in/out
    DW::Auth::Challenge->check( $formauth, $opts );
    return $opts->{valid} && !$opts->{expired};
}

# <LJFUNC>
# name: LJ::create_qr_div
# class: web
# des: Creates the hidden div that stores the QuickReply form.
# returns: undef upon failure or HTML for the div upon success
# args: user, remote, ditemid, style args, userpic, viewing thread
# des-u: user object or userid for journal reply in.
# des-ditemid: ditemid for this comment.
# des-style_opts: the viewing style arguments on this page, as a hashref.
# des-userpic: alternate default userpic.
# </LJFUNC>
sub create_qr_div {

    my ( $user, $ditemid, %opts ) = @_;
    my $u      = LJ::want_user($user);
    my $remote = LJ::get_remote();
    return undef unless $u && $remote && $ditemid;

    my $style_opts     = $opts{style_opts} || {};
    my $userpic_kw     = $opts{userpic};
    my $viewing_thread = $opts{thread};

    return undef if $remote->prop("opt_no_quickreply");

    my $e         = LJ::Entry->new( $u, ditemid => $ditemid );
    my $separator = %$style_opts ? "&" : "?";
    my $basepath  = $e->url( style_opts => LJ::viewing_style_opts(%$style_opts) ) . $separator;

    my $usertype =
        ( $remote->openid_identity && $remote->is_validated ) ? 'openid_cookie' : 'cookieuser';
    my $hidden_form_elements .= LJ::html_hidden(
        { 'name' => 'replyto',      'id' => 'replyto',      'value' => '' },
        { 'name' => 'parenttalkid', 'id' => 'parenttalkid', 'value' => '' },

        # ^ these two inputs are duplicates, but oh well.
        { 'name' => 'journal',    'id' => 'journal',    'value' => $u->{'user'} },
        { 'name' => 'itemid',     'id' => 'itemid',     'value' => $ditemid },
        { 'name' => 'usertype',   'id' => 'usertype',   'value' => $usertype },
        { 'name' => 'qr',         'id' => 'qr',         'value' => '1' },
        { 'name' => 'cookieuser', 'id' => 'cookieuser', 'value' => $remote->{'user'} },
        { 'name' => 'dtid',       'id' => 'dtid',       'value' => '' },

        # ^ the "display" version of replyto/parenttalkid. Starts empty, set by
        # JS when QR is summoned, then used to build the "more options" URL.
        # Nothing uses this after the form is submitted, it's just for JS.
        { 'name' => 'basepath',       'id' => 'basepath',       'value' => $basepath },
        { 'name' => 'viewing_thread', 'id' => 'viewing_thread', 'value' => $viewing_thread },
    );

    while ( my ( $key, $value ) = each %$style_opts ) {
        $hidden_form_elements .= LJ::html_hidden( { name => $key, id => $key, value => $value } );
    }

    # rate limiting challenge
    {
        my ( $time, $secret ) = LJ::get_secret();
        my $rchars = LJ::rand_chars(20);
        my $chal   = $ditemid . "-$u->{userid}-$time-$rchars";
        my $res    = Digest::MD5::md5_hex( $secret . $chal );
        $hidden_form_elements .= LJ::html_hidden( "chrp1", "$chal-$res" );
    }

    # hashref with "selected" and "items" keys
    my $editors = DW::Formats::select_items( preferred => $remote->prop('comment_editor'), );

    # FIXME: This is incoherent on reading/network pages. (But it's only
    # noticeable when viewing the reading/network page of someone who wouldn't
    # allow you to comment.) -NF
    my $post_disabled = $u->does_not_allow_comments_from($remote);

    return DW::Template->template_string(
        'journal/quickreply.tt',
        {
            form_url             => LJ::create_url( '/talkpost_do', host => $LJ::DOMAIN_WEB ),
            hidden_form_elements => $hidden_form_elements,
            post_disabled        => $post_disabled,
            post_button_class    => $post_disabled ? 'ui-state-disabled' : '',

            # Currently unused, but might come back.
            minimal => $opts{minimal} ? 1 : 0,

            current_icon_kw => $userpic_kw,
            current_icon    => LJ::Userpic->new_from_keyword( $remote, $userpic_kw ),

            editors => $editors,

            foundation_beta => !LJ::BetaFeatures->user_in_beta( $remote => "nos2foundation" ),

            remote => $remote,

            journal => {
                is_iplogging    => $u->opt_logcommentips eq 'A',
                is_linkstripped => !$remote
                    || ( $remote && $remote->is_identity && !$u->trusts_or_has_member($remote) ),
            },

            help => {
                icon      => LJ::help_icon_html( "userpics",  " " ),
                iplogging => LJ::help_icon_html( "iplogging", " " ),
            },
        }
    );
}

# <LJFUNC>
# name: LJ::get_lastcomment
# class: web
# des: Looks up the last talkid and journal the remote user posted in.
# returns: talkid, jid
# args:
# </LJFUNC>
sub get_lastcomment {
    my $remote = LJ::get_remote();
    my ( $talkid, $jid );

    # Figure out their last post
    if ($remote) {
        my $memkey = [ $remote->{'userid'}, "lastcomm:$remote->{'userid'}" ];
        my $memval = LJ::MemCache::get($memkey);
        ( $jid, $talkid ) = split( /:/, $memval ) if $memval;
    }

    return ( $talkid, $jid );
}

# <LJFUNC>
# name: LJ::make_qr_target
# class: web
# des: Returns a div usable for QuickReply boxes.
# returns: HTML for the div
# args:
# </LJFUNC>
sub make_qr_target {
    my $name = shift;

    return "<div id='ljqrt$name' name='ljqrt$name'></div>";
}

# <LJFUNC>
# name: LJ::set_lastcomment
# class: web
# des: Sets the lastcomm memcached key for this user's last comment.
# returns: undef on failure
# args: u, remote, dtalkid, life?
# des-u: Journal they just posted in, either u or userid
# des-remote: Remote user
# des-dtalkid: Talkid for the comment they just posted
# des-life: How long, in seconds, the memcached key should live.
# </LJFUNC>
sub set_lastcomment {
    my ( $u, $remote, $dtalkid, $life ) = @_;

    my $userid = LJ::want_userid($u);
    return undef unless $userid && $remote && $dtalkid;

    # By default, this key lasts for 10 seconds.
    $life ||= 10;

    # Set memcache key for highlighting the comment
    my $memkey = [ $remote->{'userid'}, "lastcomm:$remote->{'userid'}" ];
    LJ::MemCache::set( $memkey, "$userid:$dtalkid", time() + $life );

    return;
}

=head2 C<< LJ::determine_viewing_style( $args, $view, $u ) >>
Takes a hashref of get args, and the current view, and an optional user.
Returns "original", "mine", "site", or "light" as the style.
=cut

sub determine_viewing_style {
    my ( $args, $view, $u ) = @_;

    my $style = 'original';

    # incorporate any user preferences
    $style = $u->viewing_style($view) if $u;

    # incorporate any style arguments
    my %style_getargs = %{ LJ::viewing_style_opts(%$args) };
    $style = $style_getargs{'style'} if $style_getargs{'style'};

    # keep format=light for backwards compatibility -- override and
    # assume that somebody using it really wants the light version
    $style = $style_getargs{'format'} if $style_getargs{'format'};

    return $style;
}

=head2 C<< LJ::viewing_style_args( %arguments ) >>
Takes a list of viewing styles arguments from a list, makes sure they are valid values,
and returns them as a string that can be appended to the URL. Looks for "s2id", "format", "style"
=cut

sub viewing_style_args {

    #fixme - this should be modernised to take a hashref rather than a hash
    my (%args) = @_;

    %args = %{ LJ::viewing_style_opts(%args) };

    my @valid_args;
    while ( my ( $key, $value ) = each %args ) {
        push @valid_args, "$key=$value";
    }

    return join "&", @valid_args;
}

=head2 C<< LJ::viewing_style_opts( %arguments ) >>
Takes a list of viewing styles arguments from a list, and returns a hashref of valid values
=cut

sub viewing_style_opts {

    #fixme - this should be modernised to take a hashref rather than a hash
    my (%args) = @_;
    return {} unless %args;

    my $valid_style_args = {
        style    => { light => 1, site => 1, mine => 1, original => 1 },
        format   => { light => 1 },
        fallback => { s2    => 1, bml => 1 },
    };

    my %ret;

    # only accept purely numerical s2ids
    $ret{s2id} = $args{s2id} if $args{s2id} && $args{s2id} =~ /^\d+$/;

    foreach my $key ( keys %{$valid_style_args} ) {
        $ret{$key} = $args{$key}
            if $args{$key} && $valid_style_args->{$key}->{ $args{$key} };
    }

    return \%ret;
}

=head2 C<< LJ::create_url($path,%opts) >>
If specified, path must begin with a /

args being a list of arguments to create.
opts can contain:
proto -- specify a protocol
host -- link to different domains
args -- get arguments to add
fragment -- add fragment identifier
cur_args -- hashref of current GET arguments to the page
keep_args -- arguments to keep
keep_query_string -- keep the raw query string (ignores keep_args)
no_blank -- remove keys with null values from GET args
viewing_style -- include viewing style args
=cut

sub create_url {
    my ( $path, %opts ) = @_;

    my $r        = DW::Request->get;
    my %out_args = %{ $opts{args} || {} };

    my $host = lc( $opts{host} || $r->host );
    $path ||= $r->uri;

    my $proto = $opts{proto} // $LJ::PROTOCOL;
    my $url   = $proto . "://$host$path";

    # TWO PATHS: if keep_query_string is used, we simply preserve that
    # with no further logic. If not, however, we perform arguments logic.
    my $args;
    if ( $opts{keep_query_string} ) {
        $args = $r->query_string;

    }
    else {
        my $orig_args = $opts{cur_args} || $r->get_args( preserve_case => 1 );

        # Move over viewing style arguments
        if ( $opts{viewing_style} ) {
            my $vs_args = LJ::viewing_style_opts(%$orig_args);
            foreach my $k ( keys %$vs_args ) {
                $out_args{$k} = $vs_args->{$k} unless exists $out_args{$k};
            }
        }

        $opts{keep_args} = [ keys %$orig_args ]
            if defined $opts{keep_args} and $opts{keep_args} == 1;
        $opts{keep_args} = [] if ref $opts{keep_args} ne 'ARRAY';

        # Move over arguments that we need to keep
        foreach my $k ( @{ $opts{keep_args} } ) {
            $out_args{$k} = $orig_args->{$k}
                if exists $orig_args->{$k} && !exists $out_args{$k};
        }

        foreach my $k ( keys %out_args ) {
            if ( !defined $out_args{$k} ) {
                delete $out_args{$k};
            }
            elsif ( !length $out_args{$k} ) {
                delete $out_args{$k} if $opts{no_blank};
            }
        }

        $args = LJ::encode_url_string( \%out_args, [ sort keys %out_args ] );
    }

    $url .= "?$args" if $args;
    $url .= "#" . $opts{fragment} if $opts{fragment};

    return $url;
}

{
    my %stat_cache = ();    # key -> {lastcheck, modtime}

    sub _file_modtime {
        my ( $key, $now ) = @_;
        if ( my $ci = $stat_cache{$key} ) {
            if ( $ci->{lastcheck} > $now - 10 ) {
                return $ci->{modtime};
            }
        }

        my $set = sub {
            my $mtime = shift;
            $stat_cache{$key} = { lastcheck => $now, modtime => $mtime };
            return $mtime;
        };

        my $file;

        # Prefer the compiled version, but fall back to source
        if ( defined $LJ::STATDOCS ) {
            $file = $LJ::STATDOCS . '/' . $key;
        }
        else {
            $file = LJ::resolve_file("htdocs/$key");
        }

        my $mtime = defined $file ? ( stat($file) )[9] : undef;
        return $set->($mtime);
    }
}

# INTERLUDE: What's up w/ need_res, res_includes, and set_active_resource_group?
#
#     GOOD QUESTION, WONDER-CAT. This is a system for lazy resolution and
# deduplication of required CSS/JS files. Any component can declare its own
# dependencies without caring where it's being called from, which theoretically
# makes things slightly more self-contained and maintainable.
#     Later (I think?), someone extended it to enable incremental code
# modernization. A component can declare multiple implementations of a frontend
# feature, specifying a "resource group" for each implementation. When it's
# finally time to build a page, the controller sets its preferred resource group
# and pulls in only frontend code that's compatible with that group.
#     As for how to use these, well, hmm. They follow a classic LJ design
# pattern that I like to call "launch some garbage into the void / reach
# into the void and grab some garbage." Infinite flexibility, zero handrails or
# validation. So here's the conventions I've been able to puzzle out.
#
# * `need_res`: Declares one or more JS/CSS files that need to be loaded for
# the current page. need_res([<opts hashref>], <path>, [<path>...])
#     FILE PATHS: Use paths like "js/jquery.replyforms.js" or
#         "stc/components/quick-reply.css", relative to the top-level "htdocs"
#         directory. Paths can ONLY go into the "js" (javascript) or "stc" (CSS)
#         subdirectories. Note that on a live instance of the app, "stc" also
#         has the compiled contents of the "scss" directory (minus any files
#         whose names begin with an underscore [_]).
#     PRIORITY: The opts hashref can have a "priority" key, whose value is
#         an integer. This affects the order in which files are added to the
#         page; otherwise the order is effectively random. Files with bigger
#         priority values get included first. Existing code only seems to
#         use two values: 0 (normal) and 3 (prerequisites). 0 is never
#         referenced explicitly, just defaulted to. 3 is always referenced
#         indirectly, via the $LJ::LIB_RES_PRIORITY variable.
#     RESOURCE GROUP: The opts hashref can have a "group" key, whose value
#         is a string. See "KNOWN RESOURCE GROUPS" below for more details. If
#         you don't specify a group, need_res puts CSS files in the "all" group
#         and JS files in the "default" (actually legacy) group.
#
# * `set_active_resource_group`: Sets the value of a global variable called
# $LJ::ACTIVE_RES_GROUP, which then affects the behavior of res_includes. It's
# supposed to be called pretty late in the process of building a page. You can
# check that variable to see what will _probably_ be happening, but be careful;
# there aren't a lot of assurances about how accurate it is at any given time.
#
# * `res_includes`: Builds the actual HTML tags for the JS/CSS in the current
# resource group (plus the special "all" group), and returns them as a string.
# Whatever calls res_includes is responsible for putting the result somewhere
# useful.
#     Conceptually, res_includes is only meant to be called once per page, but
# since Foundation expects JS to go at the bottom of the <body>, it's more like
# "call half of it twice," via the wrapper functions `res_includes_head`
# (for CSS and really basic inline JS that everything else relies on) and
# `res_includes_body` (JS loaded from files).
#
# KNOWN RESOURCE GROUPS: There isn't any validation on these, but these are the
# values that actually get used by something.
#     - "foundation" - newer pages.
#     - "jquery" - pages whose JS was modernized in the early '10s.
#     - "default" - legacy LJ pages that have basically never been modernized.
#     - "all" - always included, regardless of the current resource group.
#     - "fragment" - no idea, tbh. Something involving the template system.
#
# LIMITATIONS: Lazy resolution doesn't work reliably with non-"siteviews" S2
# pages (they can sometimes do JS, but not CSS), so they should know all of
# their CSS/JS files BEFORE we start rendering markup. In particular, watch out
# for this when using .tt components that call need_res.
#     Why? To lazy resolve, you need to call res_includes AFTER the inner
# content is fully built, which means building the outer frame of the page last.
# That's easy for site pages, but since journal styles can override the entire
# HTML document, there's not really any protected "outer" part of the page that
# core2 can defer.
# -NF

# optional first argument: hashref with options
# other arguments: resources to include
sub need_res {
    my %opts;
    if ( ref $_[0] eq 'HASH' ) {
        %opts = %{ shift() };
    }

    my $group = $opts{group};

    # higher priority means it comes first in the ordering
    my $priority = $opts{priority} || 0;

    foreach my $reskey (@_) {
        die "Bogus reskey $reskey" unless $reskey =~ m!^(js|stc)/!;

        # we put javascript in the 'default' group and CSS in the 'all' group
        # since we need CSS everywhere and we are switching JS groups
        my $lgroup = $group || ( $reskey =~ /^js/ ? 'default' : 'all' );
        unless ( $LJ::NEEDED_RES{"$lgroup-$reskey"}++ ) {
            $LJ::NEEDED_RES[$priority] ||= [];

            push @{ $LJ::NEEDED_RES[$priority] }, [ $lgroup, $reskey ];
        }
    }
}

sub res_includes {
    my (%opts) = @_;

    my $include_js          = !$opts{nojs};
    my $include_libs        = !$opts{nolib};
    my $include_stylesheets = !$opts{no_stylesheets};
    my $include_script_tags = !$opts{no_scripttags};
    my $include_links       = $include_stylesheets || $include_script_tags;

    # TODO: automatic dependencies from external map and/or content of files,
    # currently it's limited to dependencies on the order you call LJ::need_res();
    my $ret = "";

    # use correct root and prefixes for SSL pages
    my ( $siteroot, $imgprefix, $statprefix, $jsprefix, $wstatprefix, $iconprefix );
    $siteroot    = $LJ::SITEROOT;
    $imgprefix   = $LJ::IMGPREFIX;
    $statprefix  = $LJ::STATPREFIX;
    $jsprefix    = $LJ::JSPREFIX;
    $wstatprefix = $LJ::WSTATPREFIX;
    $iconprefix  = $LJ::USERPIC_ROOT;

    if ($include_js) {

        # find current journal
        my $r            = DW::Request->get;
        my $journal_base = '';
        my $journal      = '';
        if ($r) {
            my $journalid = $r->note('journalid');

            my $ju;
            $ju = LJ::load_userid($journalid) if $journalid;

            if ($ju) {
                $journal_base = $ju->journal_base;
                $journal      = $ju->{user};
            }
        }

        my $remote    = LJ::get_remote();
        my $hasremote = $remote ? 1 : 0;

        # ctxpopup prop
        my $ctxpopup_icons    = 1;
        my $ctxpopup_userhead = 1;
        $ctxpopup_icons    = 0 if $remote && !$remote->opt_ctxpopup_icons;
        $ctxpopup_userhead = 0 if $remote && !$remote->opt_ctxpopup_userhead;

        # poll for esn inbox updates?
        my $inbox_update_poll = LJ::is_enabled('inbox_update_poll');

        # are media embeds enabled?
        my $embeds_enabled = LJ::is_enabled('embed_module');

        # esn ajax enabled?
        my $esn_async = LJ::is_enabled('esn_ajax');

        my %site = (
            imgprefix           => "$imgprefix",
            siteroot            => "$siteroot",
            statprefix          => "$statprefix",
            iconprefix          => "$iconprefix",
            currentJournalBase  => "$journal_base",
            currentJournal      => "$journal",
            has_remote          => $hasremote,
            ctx_popup           => ( $ctxpopup_icons || $ctxpopup_userhead ),
            ctx_popup_icons     => $ctxpopup_icons,
            ctx_popup_userhead  => $ctxpopup_userhead,
            inbox_update_poll   => $inbox_update_poll,
            media_embed_enabled => $embeds_enabled,
            esn_async           => $esn_async,
            user_domain         => $LJ::USER_DOMAIN,
            cmax_comment        => LJ::CMAX_COMMENT,
        );

        my $site_params = to_json( \%site );

        # include standard JS info
        $ret .= qq {
            <script type="text/javascript">
                var Site;
                if (!Site)
                    Site = {};

                Site = Object.assign(Site, $site_params);
           </script>
        };
    }

    if ($include_links) {
        my $now = time();
        my %list;      # type -> [];
        my %oldest;    # type -> $oldest
        my %included = ();
        my $add      = sub {
            my ( $type, $what, $modtime, $order ) = @_;

            # the same file may have been included twice
            # if it was in two different groups and not JS
            # so add another check here
            return if $included{$what};
            $included{$what} = 1;

            # in the concat-res case, we don't directly append the URL w/
            # the modtime, but rather do one global max modtime at the
            # end, which is done later in the tags function.
            $modtime = '' unless defined $modtime;

            $list{$type} ||= [];
            push @{ $list{$type}[$order] ||= [] }, $what;
            $oldest{$type} ||= [];
            $oldest{$type}[$order] = $modtime
                if $modtime && $modtime > ( $oldest{$type}[$order] || 0 );
        };

 # we may not want to pull in the libraries again, say if we're pulling in elements via an ajax load
        delete $LJ::NEEDED_RES[$LJ::LIB_RES_PRIORITY] unless $include_libs;

        my $order = 0;
        foreach my $by_priority ( reverse @LJ::NEEDED_RES ) {
            next unless $by_priority;
            $order++;

            foreach my $resrow (@$by_priority) {

                # determine if this resource is part of the resource group that is active;
                # or 'default' if no group explicitly active
                my ( $group, $key ) = @$resrow;
                next
                    if $group ne 'all'
                    && ( ( defined $LJ::ACTIVE_RES_GROUP && $group ne $LJ::ACTIVE_RES_GROUP )
                    || ( !defined $LJ::ACTIVE_RES_GROUP && $group ne 'default' ) );

                my $path;
                my $mtime = _file_modtime( $key, $now );
                if ( $key =~ m!^stc/fck/! || $LJ::FORCE_WSTAT{$key} ) {
                    $path = "w$key";    # wstc/ instead of stc/
                }
                else {
                    $path = $key;
                }

                # if we want to also include a local version of this file, include that too
                if (@LJ::USE_LOCAL_RES) {
                    if ( grep { lc $_ eq lc $key } @LJ::USE_LOCAL_RES ) {
                        my $inc = $key;
                        $inc =~ s/(\w+)\.(\w+)$/$1-local.$2/;
                        LJ::need_res($inc);
                    }
                }

                if ( $path =~ m!^js/(.+)! ) {
                    $add->( "js", $1, $mtime, $order );
                }
                elsif ( $path =~ /\.css$/ && $path =~ m!^(w?)stc/(.+)! ) {
                    $add->( "${1}stccss", $2, $mtime, $order );
                }
                elsif ( $path =~ /\.js$/ && $path =~ m!^(w?)stc/(.+)! ) {
                    $add->( "${1}stcjs", $2, $mtime, $order );
                }
            }
        }

        my $tags = sub {
            my ( $type, $template ) = @_;
            for my $o ( 0 ... $order ) {
                my $list;
                my $template_order = $template;
                next unless $list = $list{$type}[$o];

                my $csep = join( ',', @$list );
                $csep .= "?v=" . $oldest{$type}[$o];
                $template_order =~ s/__+/??$csep/;
                $ret .= $template_order;
            }
        };

        if ($include_stylesheets) {
            $tags->(
                "stccss", "<link rel=\"stylesheet\" type=\"text/css\" href=\"$statprefix/___\" />\n"
            );
            $tags->(
                "wstccss",
                "<link rel=\"stylesheet\" type=\"text/css\" href=\"$wstatprefix/___\" />\n"
            );
        }

        if ($include_script_tags) {
            $tags->( "js", "<script type=\"text/javascript\" src=\"$jsprefix/___\"></script>\n" );
            $tags->(
                "stcjs", "<script type=\"text/javascript\" src=\"$statprefix/___\"></script>\n"
            );
            $tags->(
                "wstcjs", "<script type=\"text/javascript\" src=\"$wstatprefix/___\"></script>\n"
            );
        }
    }

    return $ret;
}

sub res_includes_head {
    return LJ::res_includes( no_scripttags => 1 );
}

sub res_includes_body {
    return LJ::res_includes( nojs => 1, no_stylesheets => 1 );
}

# called to set the active resource group
sub set_active_resource_group {
    $LJ::ACTIVE_RES_GROUP = $_[0];
}

# Returns HTML of a dynamic tag could given passed in data
# Requires hash-ref of tag => { url => url, value => value }
sub tag_cloud {
    my ( $tags, $opts ) = @_;

    # find sizes of tags, sorted
    my @sizes = sort { $a <=> $b } map { $tags->{$_}->{'value'} } keys %$tags;

    # remove duplicates:
    my %sizes = map { $_, 1 } @sizes;
    @sizes = sort { $a <=> $b } keys %sizes;

    my @tag_names = sort keys %$tags;

    my $percentile = sub {
        my $n     = shift;
        my $total = scalar @sizes;
        for ( my $i = 0 ; $i < $total ; $i++ ) {
            next if $n > $sizes[$i];
            return $i / $total;
        }
    };

    my $base_font_size  = 8;
    my $font_size_range = $opts->{font_size_range} || 25;
    my $ret .= "<div id='tagcloud' class='tagcloud'>";
    my %tagdata = ();
    foreach my $tag (@tag_names) {
        my $tagurl = $tags->{$tag}->{'url'};
        my $ct     = $tags->{$tag}->{'value'};
        my $pt     = int( $base_font_size + $percentile->($ct) * $font_size_range );
        $ret .= "<a ";
        $ret .= "id='taglink_$tag' " unless $opts->{ignore_ids};
        $ret .=
            "href='" . LJ::ehtml($tagurl) . "' style='font-size: ${pt}pt; text-decoration: none'>";
        $ret .= LJ::ehtml($tag) . "</a>\n";

        # build hash of tagname => final point size for refresh
        $tagdata{$tag} = $pt;
    }
    $ret .= "</div>";

    return $ret;
}

sub control_strip {
    my %opts = @_;
    my $user = delete $opts{user};

    my $journal    = LJ::load_user($user);
    my $show_strip = 1;
    $show_strip = LJ::Hooks::run_hook("show_control_strip")
        if ( LJ::Hooks::are_hooks("show_control_strip") );

    return "" unless $show_strip;

    my $remote = LJ::get_remote();

    my $r                  = DW::Request->get;
    my $passed_in_location = $opts{host} && $opts{uri} ? 1 : 0;
    my $host               = delete $opts{host} || $r->host;
    my $uri                = delete $opts{uri} || $r->uri;

    my $args;
    my $argshash = {};

    # we need to pass in location explicitly when creating a control strip using JS
    if ($passed_in_location) {
        $args = delete $opts{args};
        LJ::decode_url_string( $args, $argshash );
    }
    else {
        $args     = $r->query_string;
        $argshash = $r->get_args;
    }

    my $view    = delete $opts{view} || $r->note('view');
    my $view_is = sub { defined $view && $view eq $_[0] };

    my $baseuri = "$LJ::PROTOCOL://$host$uri";

    $baseuri .= $args ? "?$args" : "";
    my $euri        = LJ::eurl($baseuri);
    my $create_link = LJ::Hooks::run_hook( "override_create_link_on_navstrip", $journal )
        || "<a href='$LJ::SITEROOT/create'>"
        . LJ::Lang::ml( 'web.controlstrip.links.create', { 'sitename' => $LJ::SITENAMESHORT } )
        . "</a>";

    my %ml = map { $_ => LJ::Lang::ml($_) } qw(
        web.controlstrip.links.addfeed
        web.controlstrip.links.addtocircle
        web.controlstrip.links.confirm
        web.controlstrip.links.editcommmembers
        web.controlstrip.links.editcommprofile
        web.controlstrip.links.home
        web.controlstrip.links.inbox
        web.controlstrip.links.invitefriends
        web.controlstrip.links.joincomm
        web.controlstrip.links.learnmore
        web.controlstrip.links.leavecomm
        web.controlstrip.links.login
        web.controlstrip.links.managecircle
        web.controlstrip.links.managecomminvites
        web.controlstrip.links.manageentries
        web.controlstrip.links.modifycircle
        web.controlstrip.links.popfeeds
        web.controlstrip.links.post2
        web.controlstrip.links.postcomm
        web.controlstrip.links.queue
        web.controlstrip.links.recentcomments
        web.controlstrip.links.removecomm
        web.controlstrip.links.removefeed
        web.controlstrip.links.settings
        web.controlstrip.links.trackcomm
        web.controlstrip.links.trackuser
        web.controlstrip.links.viewreadingpage
        web.controlstrip.links.watchcomm
        web.controlstrip.nouserpic.alt
        web.controlstrip.nouserpic.title
        web.controlstrip.select.friends.all
        web.controlstrip.select.friends.communities
        web.controlstrip.select.friends.feeds
        web.controlstrip.select.friends.journals
        web.controlstrip.status.yourjournal
        web.controlstrip.status.yournetworkpage
        web.controlstrip.status.yourreadingpage
        web.controlstrip.userpic.alt
        web.controlstrip.userpic.title
    );

    # Build up some common links
    my %links = (
        'login' =>
            "<a href='$LJ::SITEROOT/?returnto=$euri'>$ml{'web.controlstrip.links.login'}</a>",
        'post_journal' =>
            "<a href='$LJ::SITEROOT/entry/new'>$ml{'web.controlstrip.links.post2'}</a>",
        'home' => "<a href='$LJ::SITEROOT/'>" . $ml{'web.controlstrip.links.home'} . "</a>",
        'recent_comments' =>
"<a href='$LJ::SITEROOT/comments/recent'>$ml{'web.controlstrip.links.recentcomments'}</a>",
        'manage_friends' =>
            "<a href='$LJ::SITEROOT/manage/circle/'>$ml{'web.controlstrip.links.managecircle'}</a>",
        'manage_entries' =>
            "<a href='$LJ::SITEROOT/editjournal'>$ml{'web.controlstrip.links.manageentries'}</a>",
        'invite_friends' =>
"<a href='$LJ::SITEROOT/manage/circle/invite'>$ml{'web.controlstrip.links.invitefriends'}</a>",
        'create_account' => $create_link,
        'syndicated_list' =>
            "<a href='$LJ::SITEROOT/feeds/list'>$ml{'web.controlstrip.links.popfeeds'}</a>",
        'learn_more' => LJ::Hooks::run_hook('control_strip_learnmore_link')
            || "<a href='$LJ::SITEROOT/'>$ml{'web.controlstrip.links.learnmore'}</a>",
        'explore' => "<a href='$LJ::SITEROOT/explore/'>"
            . LJ::Lang::ml( 'web.controlstrip.links.explore',
            { sitenameabbrev => $LJ::SITENAMEABBREV } )
            . "</a>",
        'confirm' => "<a href='$LJ::SITEROOT/register'>$ml{'web.controlstrip.links.confirm'}</a>",
    );

    if ($remote) {
        my $unread = $remote->notification_inbox->unread_count;
        $links{inbox} .= "<a href='$LJ::SITEROOT/inbox/'>$ml{'web.controlstrip.links.inbox'}";
        $links{inbox} .= " ($unread)" if $unread;
        $links{inbox} .= "</a>";

        $links{settings} =
            "<a href='$LJ::SITEROOT/manage/settings/'>$ml{'web.controlstrip.links.settings'}</a>";
        $links{'view_friends_page'} =
              "<a href='"
            . $remote->journal_base
            . "/read'>$ml{'web.controlstrip.links.viewreadingpage'}</a>";
        $links{'add_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$ml{'web.controlstrip.links.addtocircle'}</a>";
        $links{'edit_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$ml{'web.controlstrip.links.modifycircle'}</a>";
        $links{'track_user'} =
"<a href='$LJ::SITEROOT/manage/tracking/user?journal=$journal->{user}'>$ml{'web.controlstrip.links.trackuser'}</a>";

        if ( $journal->is_syndicated ) {
            $links{'add_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=subscribe'>$ml{'web.controlstrip.links.addfeed'}</a>";
            $links{'remove_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=remove'>$ml{'web.controlstrip.links.removefeed'}</a>";
        }
        if ( $journal->is_community ) {
            $links{'join_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$ml{'web.controlstrip.links.joincomm'}</a>"
                unless $journal->is_closed_membership;
            $links{'leave_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$ml{'web.controlstrip.links.leavecomm'}</a>";
            $links{'watch_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=subscribe'>$ml{'web.controlstrip.links.watchcomm'}</a>";
            $links{'unwatch_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$ml{'web.controlstrip.links.removecomm'}</a>";
            $links{'post_to_community'} =
"<a href='$LJ::SITEROOT/entry/$journal->{user}/new'>$ml{'web.controlstrip.links.postcomm'}</a>";
            $links{'edit_community_profile'} =
"<a href='$LJ::SITEROOT/manage/profile/?authas=$journal->{user}'>$ml{'web.controlstrip.links.editcommprofile'}</a>";
            $links{'edit_community_invites'} =
                  "<a href='"
                . $journal->community_invite_members_url
                . "'>$ml{'web.controlstrip.links.managecomminvites'}</a>";
            $links{'edit_community_members'} =
                  "<a href='"
                . $journal->community_manage_members_url
                . "'>$ml{'web.controlstrip.links.editcommmembers'}</a>";
            $links{'track_community'} =
"<a href='$LJ::SITEROOT/manage/tracking/user?journal=$journal->{user}'>$ml{'web.controlstrip.links.trackcomm'}</a>";
            $links{'queue'} =
                  "<a href='"
                . $journal->moderation_queue_url
                . "'>$ml{'web.controlstrip.links.queue'}</a>";
        }
    }
    my $journal_display = $journal->ljuser_display;
    my %statustext      = (
        'yourjournal'            => $ml{'web.controlstrip.status.yourjournal'},
        'yourfriendspage'        => $ml{'web.controlstrip.status.yourreadingpage'},
        'yourfriendsfriendspage' => $ml{'web.controlstrip.status.yournetworkpage'},
        'personal' =>
            LJ::Lang::ml( 'web.controlstrip.status.personal', { 'user' => $journal_display } ),
        'personalfriendspage' => LJ::Lang::ml(
            'web.controlstrip.status.personalreadingpage',
            { 'user' => $journal_display }
        ),
        'personalfriendsfriendspage' => LJ::Lang::ml(
            'web.controlstrip.status.personalnetworkpage',
            { 'user' => $journal_display }
        ),
        'community' =>
            LJ::Lang::ml( 'web.controlstrip.status.community', { 'user' => $journal_display } ),
        'syn'   => LJ::Lang::ml( 'web.controlstrip.status.syn',   { 'user' => $journal_display } ),
        'other' => LJ::Lang::ml( 'web.controlstrip.status.other', { 'user' => $journal_display } ),
        'mutualtrust' =>
            LJ::Lang::ml( 'web.controlstrip.status.mutualtrust', { 'user' => $journal_display } ),
        'mutualtrust_mutualwatch' => LJ::Lang::ml(
            'web.controlstrip.status.mutualtrust_mutualwatch',
            { 'user' => $journal_display }
        ),
        'mutualtrust_watch' => LJ::Lang::ml(
            'web.controlstrip.status.mutualtrust_watch',
            { 'user' => $journal_display }
        ),
        'mutualtrust_watchedby' => LJ::Lang::ml(
            'web.controlstrip.status.mutualtrust_watchedby',
            { 'user' => $journal_display }
        ),
        'mutualwatch' =>
            LJ::Lang::ml( 'web.controlstrip.status.mutualwatch', { 'user' => $journal_display } ),
        'trust_mutualwatch' => LJ::Lang::ml(
            'web.controlstrip.status.trust_mutualwatch',
            { 'user' => $journal_display }
        ),
        'trust_watch' =>
            LJ::Lang::ml( 'web.controlstrip.status.trust_watch', { 'user' => $journal_display } ),
        'trust_watchedby' => LJ::Lang::ml(
            'web.controlstrip.status.trust_watchedby',
            { 'user' => $journal_display }
        ),
        'trustedby_mutualwatch' => LJ::Lang::ml(
            'web.controlstrip.status.trustedby_mutualwatch',
            { 'user' => $journal_display }
        ),
        'trustedby_watch' => LJ::Lang::ml(
            'web.controlstrip.status.trustedby_watch',
            { 'user' => $journal_display }
        ),
        'trustedby_watchedby' => LJ::Lang::ml(
            'web.controlstrip.status.trustedby_watchedby',
            { 'user' => $journal_display }
        ),
        'maintainer' =>
            LJ::Lang::ml( 'web.controlstrip.status.maintainer', { 'user' => $journal_display } ),
        'memberwatcher' =>
            LJ::Lang::ml( 'web.controlstrip.status.memberwatcher', { 'user' => $journal_display } ),
        'watcher' =>
            LJ::Lang::ml( 'web.controlstrip.status.watcher', { 'user' => $journal_display } ),
        'member' =>
            LJ::Lang::ml( 'web.controlstrip.status.member', { 'user' => $journal_display } ),
        'trusted' =>
            LJ::Lang::ml( 'web.controlstrip.status.trusted', { 'user' => $journal_display } ),
        'watched' =>
            LJ::Lang::ml( 'web.controlstrip.status.watched', { 'user' => $journal_display } ),
        'trusted_by' =>
            LJ::Lang::ml( 'web.controlstrip.status.trustedby', { 'user' => $journal_display } ),
        'watched_by' =>
            LJ::Lang::ml( 'web.controlstrip.status.watchedby', { 'user' => $journal_display } ),
    );

    # Vars for controlstrip.tt
    my $template_args = {
        'view'         => $view,
        'userpic_html' => '',
        'logo_html'    => ( LJ::Hooks::run_hook( 'control_strip_logo', $remote, $journal ) || '' ),
        'show_login_form' => 0,
        'links'           => \%links,
        'statustext'      => '',

        # remote # only set if logged in
        #     .user => "plainname"
        #     .sessid => integer
        #     .display => "<span class="ljuser">..."
        #     .is_validated => bool
        #     .is_identity => bool
        'actionlinks' => [],

        # filters # only set if viewing reading or network page
        #     .all => []
        #     .selected => ""
        'viewoptions' => [],
        'search_html' => LJ::Widget::Search->render,

        # url of the rendered page, for the login/logout form to redirect back to
        'returnto' => $baseuri,
    };

    # Shortcuts for the two nested array refs that get repeatedly dereferenced later
    my $actionlinks = $template_args->{'actionlinks'};
    my $viewoptions = $template_args->{'viewoptions'};

    if ($remote) {
        my $userpic = $remote->userpic;
        $template_args->{'remote'} = {
            'sessid'       => $remote->session->id || 0,
            'user'         => $remote->user,
            'display'      => $remote->ljuser_display,
            'is_validated' => $remote->is_validated,
            'is_identity'  => $remote->is_identity,
        };

        # other accounts signed in to this browser, for the switcher
        $template_args->{'switch_accounts'} = [
            map {
                {
                    userid  => $_->{userid},
                    user    => $_->{user},
                    display => $_->{u}->ljuser_display,
                    valid   => $_->{valid},
                }
            } DW::AccountSwitcher->accounts
        ];
        if ($userpic) {
            my $wh = $userpic->img_fixedsize( width => 43, height => 43 );
            $template_args->{'userpic_html'} =
                  "<a href='$LJ::SITEROOT/manage/icons'><img src='"
                . $userpic->url
                . "' alt=\"$ml{'web.controlstrip.userpic.alt'}\" title=\"$ml{'web.controlstrip.userpic.title'}\" $wh /></a>";
        }
        else {
            my $tinted_nouserpic_img = "";

            if ( $journal->prop('stylesys') == 2 ) {
                my $ctx = $LJ::S2::CURR_CTX;
                my $custom_nav_strip =
                    S2::get_property_value( $ctx, "custom_control_strip_colors" );

                if ( $custom_nav_strip ne "off" ) {
                    my $linkcolor = S2::get_property_value( $ctx, "control_strip_linkcolor" );

                    if ( $linkcolor ne "" ) {
                        $tinted_nouserpic_img =
                            S2::Builtin::LJ::palimg_modify( $ctx, "controlstrip/nouserpic.gif",
                            [ S2::Builtin::LJ::PalItem( $ctx, 0, $linkcolor ) ] );
                    }
                }
            }
            if ( $tinted_nouserpic_img eq "" ) {
                $tinted_nouserpic_img = "$LJ::IMGPREFIX/controlstrip/nouserpic.gif";
            }
            $template_args->{'userpic_html'} =
"<a href='$LJ::SITEROOT/manage/icons'><img src='$tinted_nouserpic_img' alt=\"$ml{'web.controlstrip.nouserpic.alt'}\" title=\"$ml{'web.controlstrip.nouserpic.title'}\" height='43' width='43' /></a>";
        }

        if ( $remote->equals($journal) ) {
            if ( $view_is->("read") ) {
                $template_args->{'statustext'} = $statustext{'yourfriendspage'};
            }
            elsif ( $view_is->("network") ) {
                $template_args->{'statustext'} = $statustext{'yourfriendsfriendspage'};
            }
            else {
                $template_args->{'statustext'} = $statustext{'yourjournal'};
            }

            if ( $view_is->("read") || $view_is->("network") ) {
                my @filters = (
                    "all",             $ml{'web.controlstrip.select.friends.all'},
                    "showpeople",      $ml{'web.controlstrip.select.friends.journals'},
                    "showcommunities", $ml{'web.controlstrip.select.friends.communities'},
                    "showsyndicated",  $ml{'web.controlstrip.select.friends.feeds'}
                );

# content_filters returns an array of content filters this user had, sorted by sortorder
# since this is only shown if $remote->equals( $journal ) , we don't have to care whether a filter is public or not
                my @custom_filters = $journal->content_filters;

                # Making as few changes to existing behaviour
                my $default_filter = "default view";
                foreach my $f (@custom_filters) {

                    # Both 'default' and 'default view' are default filters
                    $default_filter = "default" if lc( $f->name ) eq "default";
                    push @filters, "filter:" . lc( $f->name ), $f->name;
                }

                my $selected = "all";

                # first, change the selection state to reflect any filter in use;
                # if we have no default filter or if the named filter somehow
                # fails to exist, this will effectively select nothing
                if ( $r->uri =~ /^\/read\/?(.+)?/i ) {
                    my $filter = $1 || $default_filter;
                    $selected = "filter:" . LJ::durl( lc($filter) );

                    # but don't select the filter if the query string contains filter=0
                    # (fun fact: named filter + filter=0 returns a 404 error)
                    $selected = "all" if $r->query_string && $r->query_string =~ /\bfilter=0\b/;
                }

                # next, change the selection state to reflect showtypes from getargs;
                # note this will override the implicit default filter or filter=0 selection
                # if a match is found, but not a filter explicitly named in the URL.
                # (of course you can use both! we're just competing for the
                #  state of the pop-up menu in the control strip here)
                if (   ( $r->uri eq "/read" || $r->uri eq "/network" )
                    && $r->query_string
                    && $r->query_string ne "" )
                {
                    $selected = "showpeople"      if $r->query_string =~ /\bshow=P\b/;
                    $selected = "showcommunities" if $r->query_string =~ /\bshow=C\b/;
                    $selected = "showsyndicated"  if $r->query_string =~ /\bshow=F\b/;
                }

                push( @$actionlinks, $links{'manage_friends'} );

                # Data for the reading list filter drop-down:
                $template_args->{'filters'} = {
                    'all'      => \@filters,
                    'selected' => $selected,
                };

            }
            else {
                push( @$actionlinks,
                    $links{'recent_comments'},
                    $links{'manage_entries'},
                    $links{'invite_friends'} );
            }
        }
        elsif ( $journal->is_personal || $journal->is_identity ) {
            my $trusted      = $remote->trusts($journal);
            my $trusted_by   = $journal->trusts($remote);
            my $mutual_trust = $trusted && $trusted_by ? 1 : 0;
            my $watched      = $remote->watches($journal);
            my $watched_by   = $journal->watches($remote);
            my $mutual_watch = $watched && $watched_by ? 1 : 0;

            if ( $mutual_trust && $mutual_watch ) {
                $template_args->{'statustext'} = $statustext{mutualtrust_mutualwatch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $mutual_trust && $watched ) {
                $template_args->{'statustext'} = $statustext{mutualtrust_watch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $mutual_trust && $watched_by ) {
                $template_args->{'statustext'} = $statustext{mutualtrust_watchedby};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted && $mutual_watch ) {
                $template_args->{'statustext'} = $statustext{trust_mutualwatch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted_by && $mutual_watch ) {
                $template_args->{'statustext'} = $statustext{trustedby_mutualwatch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ($mutual_trust) {
                $template_args->{'statustext'} = $statustext{mutualtrust};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ($mutual_watch) {
                $template_args->{'statustext'} = $statustext{mutualwatch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted && $watched ) {
                $template_args->{'statustext'} = $statustext{trust_watch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted && $watched_by ) {
                $template_args->{'statustext'} = $statustext{trust_watchedby};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted_by && $watched ) {
                $template_args->{'statustext'} = $statustext{trustedby_watch};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ( $trusted_by && $watched_by ) {
                $template_args->{'statustext'} = $statustext{trustedby_watchedby};
                push( @$actionlinks, $links{add_friend} );
            }
            elsif ($trusted) {
                $template_args->{'statustext'} = $statustext{trusted};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ($trusted_by) {
                $template_args->{'statustext'} = $statustext{trusted_by};
                push( @$actionlinks, $links{add_friend} );
            }
            elsif ($watched) {
                $template_args->{'statustext'} = $statustext{watched};
                push( @$actionlinks, $links{edit_friend} );
            }
            elsif ($watched_by) {
                $template_args->{'statustext'} = $statustext{watched_by};
                push( @$actionlinks, $links{add_friend} );
            }
            else {
                if ( $view_is->("read") ) {
                    $template_args->{'statustext'} = $statustext{'personalfriendspage'};
                }
                elsif ( $view_is->("network") ) {
                    $template_args->{'statustext'} = $statustext{'personalfriendsfriendspage'};
                }
                else {
                    $template_args->{'statustext'} = $statustext{'personal'};
                }
                push( @$actionlinks, $links{'add_friend'} );
            }
            push( @$actionlinks, $links{'track_user'} );
        }
        elsif ( $journal->is_community ) {
            my $watching          = $remote->watches($journal);
            my $memberof          = $remote->member_of($journal);
            my $haspostingaccess  = $remote->can_post_to($journal);
            my $isclosedcommunity = $journal->is_closed_membership;

            if ( $remote->can_manage_other($journal) ) {
                $template_args->{'statustext'} = "$statustext{maintainer}";
                push( @$actionlinks, $links{post_to_community} )
                    if $haspostingaccess;

                if ( $journal->prop('moderated') ) {
                    push( @$actionlinks, "$links{queue} [" . $journal->get_mod_queue_count . "]" );
                }
                else {
                    push( @$actionlinks, $links{edit_community_profile} );
                }

                push( @$actionlinks,
                    $links{edit_community_invites},
                    $links{edit_community_members} );

            }
            elsif ( $watching && $memberof ) {
                $template_args->{'statustext'} = $statustext{memberwatcher};
                push( @$actionlinks, $links{post_to_community} )
                    if $haspostingaccess;
                push( @$actionlinks, $links{leave_community} );
                push( @$actionlinks, $links{track_community} );

            }
            elsif ($watching) {
                $template_args->{'statustext'} = $statustext{watcher};
                push( @$actionlinks, $links{post_to_community} )
                    if $haspostingaccess;
                push( @$actionlinks,
                    $isclosedcommunity
                    ? "This is a closed community"
                    : $links{join_community} );
                push( @$actionlinks, $links{unwatch_community} );
                push( @$actionlinks, $links{track_community} );

            }
            elsif ($memberof) {
                $template_args->{'statustext'} = $statustext{member};
                push( @$actionlinks, $links{post_to_community} )
                    if $haspostingaccess;
                push( @$actionlinks,
                    $links{watch_community}, $links{'leave_community'},
                    $links{track_community} );

            }
            else {
                $template_args->{'statustext'} = $statustext{community};
                push( @$actionlinks, $links{post_to_community} )
                    if $haspostingaccess;
                push( @$actionlinks,
                    $isclosedcommunity
                    ? "This is a closed community"
                    : $links{join_community} );
                push( @$actionlinks, $links{watch_community}, $links{track_community} );
            }
        }
        elsif ( $journal->is_syndicated ) {
            $template_args->{'statustext'} = $statustext{syn};
            if ( $remote && !$remote->watches($journal) ) {
                push( @$actionlinks, $links{add_friend} );
            }
            elsif ( $remote && $remote->watches($journal) ) {
                push( @$actionlinks, $links{remove_friend} );
            }
            push( @$actionlinks, $links{syndicated_list} );
        }
        else {
            $template_args->{'statustext'} = $statustext{other};
        }

    }
    else {
        $template_args->{'userpic_html'} =
            LJ::Hooks::run_hook( 'control_strip_loggedout_userpic_contents', $euri ) || "";

        my $show_login_form = LJ::Hooks::run_hook( "show_control_strip_login_form", $journal );
        $show_login_form = 1 if !defined $show_login_form;

        $template_args->{'show_login_form'} = $show_login_form;

        if ( $journal->is_personal || $journal->is_identity ) {
            if ( $view_is->("read") ) {
                $template_args->{'statustext'} = $statustext{'personalfriendspage'};
            }
            elsif ( $view_is->("network") ) {
                $template_args->{'statustext'} = $statustext{'personalfriendsfriendspage'};
            }
            else {
                $template_args->{'statustext'} = $statustext{'personal'};
            }
        }
        elsif ( $journal->is_community ) {
            $template_args->{'statustext'} = $statustext{'community'};
        }
        elsif ( $journal->is_syndicated ) {
            $template_args->{'statustext'} = $statustext{'syn'};
        }
        else {
            $template_args->{'statustext'} = $statustext{'other'};
        }

        push( @$actionlinks, $links{'login'} ) unless $show_login_form;
        push( @$actionlinks, $links{'create_account'}, $links{'learn_more'} );
    }

    # search box and ?style=mine/?style=light/?style=original/?style=site options
    # determine whether style is "mine", and define new uri variable to manipulate
    # note: all expressions case-insensitive
    my $current_style = determine_viewing_style( $r->get_args, $view, $remote );

    # a quick little routine to use when cycling through the options
    # to create the style links for the nav bar
    my $make_style_link = sub {
        return LJ::ehtml(
            create_url(
                $uri,
                host     => $host,
                cur_args => $argshash,

                # change the style arg
                'args' => { 'style' => $_[0] },

                # keep any other existing arguments
                'keep_args' => 1,
            )
        );
    };

    # cycle through all possibilities, add the valid ones
    foreach my $view_type (qw( mine site light original )) {

        # only want to offer this option if user is logged in and it's not their own journal, since
        # original will take care of that
        if (    $view_type eq "mine"
            and $current_style ne $view_type
            and $remote
            and not $remote->equals($journal) )
        {
            push @$viewoptions,
                  "<a href='"
                . $make_style_link->($view_type) . "'>"
                . LJ::Lang::ml('web.controlstrip.reloadpage.mystyle2') . "</a>";
        }
        elsif (
                $view_type eq "site"
            and $current_style ne $view_type
            and defined $view
            and {
                entry => 1,
                reply => 1,
                icons => 1,
            }->{$view}
            )
        {
            push @$viewoptions,
                  "<a href='"
                . $make_style_link->($view_type) . "'>"
                . LJ::Lang::ml('web.controlstrip.reloadpage.sitestyle') . "</a>";
        }
        elsif ( $view_type eq "light" and $current_style ne $view_type ) {
            push @$viewoptions,
                  "<a href='"
                . $make_style_link->($view_type) . "'>"
                . LJ::Lang::ml('web.controlstrip.reloadpage.lightstyle2') . "</a>";
        }
        elsif ( $view_type eq "original" and $current_style ne $view_type ) {
            push @$viewoptions,
                  "<a href='"
                . $make_style_link->($view_type) . "'>"
                . LJ::Lang::ml('web.controlstrip.reloadpage.origstyle2') . "</a>";
        }
    }

    return DW::Template->template_string( 'journal/controlstrip.tt', $template_args );
}

sub control_strip_js_inject {
    my %opts = @_;
    my $user = delete $opts{user} || '';

    my $ret;

    my $r    = DW::Request->get;
    my $host = $r->host;
    my $uri  = $r->uri;
    my $args = LJ::eurl( $r->query_string ) || '';
    my $view = $r->note('view') || '';

    $ret .= qq{
<script type='text/javascript'>
jQuery(function(jQ){
    if (jQ("#lj_controlstrip").length == 0) {
        jQ.getJSON("/$user/__rpc_controlstrip?user=$user&host=$host&uri=$uri&args=$args&view=$view", {},
            function(data) {
                jQ("<div></div>").html(data.control_strip).prependTo("body");
            }
        );
    }
})
</script>};

    return $ret;
}

# For the Rich Text Editor
# Set JS variables for use by the RTE
sub rte_js_vars {
    my ($remote) = @_;

    my $ret = '';

    # The JS var canmakepoll is used by fckplugin.js to change the behaviour
    # of the poll button in the RTE.
    # Also remove any RTE buttons that have been set to disabled.
    my $canmakepoll = "true";
    $canmakepoll = "false" if ( $remote && !$remote->can_create_polls );
    $ret .= "<script type='text/javascript'>\n";
    $ret .= "    var RTEdisabled = new Array();\n";
    my $rte_disabled = $LJ::DISABLED{rte_buttons} || {};
    foreach my $key ( keys %$rte_disabled ) {
        $ret .= "    RTEdisabled['$key'] = true;" if $rte_disabled->{$key};
    }

    $ret .= qq^
        var canmakepoll = $canmakepoll;

        function removeDisabled(ToolbarSet) {
            for (var i=0; i<ToolbarSet.length; i++) {
                for (var j=0; j<ToolbarSet[i].length; j++) {
                    if (RTEdisabled[ToolbarSet[i][j]] == true) ToolbarSet[i].splice(j,1);
                }
            }
        }

        var SiteConfig = new Object();
    </script>^;

    return $ret;
}

# prints out UI for subscribing to some events
sub subscribe_interface {
    my ( $u, %opts ) = @_;

    croak "subscribe_interface wants a \$u" unless LJ::isu($u);

    my $categories    = delete $opts{categories}                     || [];
    my $journalu      = delete $opts{journal}                        || LJ::get_remote();
    my $def_notes     = delete $opts{default_selected_notifications} || [];
    my $num_per_page  = delete $opts{num_per_page}                   || 250;
    my $page          = delete $opts{page}                           || 1;
    my $settings_page = delete $opts{settings_page}                  || 0;

    croak "Invalid user object passed to subscribe_interface" unless LJ::isu($journalu);

    croak "Invalid options passed to subscribe_interface" if ( scalar keys %opts );

    my @notify_classes = LJ::NotificationMethod->all_classes;
    return "No notification methods" unless @notify_classes;

    my $page_vars = { settings_page => $settings_page };
    $page_vars->{ntypeids} = join ',', map { $_->ntypeid } @notify_classes;

    # skip the inbox type; it's always on
    @notify_classes = grep { $_ ne 'LJ::NotificationMethod::Inbox' } @notify_classes;
    $page_vars->{notify_classes} = \@notify_classes;

    my @catids;
    my $catid = 0;
    my @catdata;    # this is eventually passed to the display template
    my @prev_cats;

    my %num_subs_by_type = ();    # for the subscription_stats hook

    # pagination variables
    my $displayed_tracking_start = ( $page - 1 ) * $num_per_page;
    my $displayed_tracking_end   = $displayed_tracking_start + $num_per_page - 1;
    my $displayed_tracking_count = 0;

    foreach my $cat_hash (@$categories) {
        my ( $category, $cat_events ) = %$cat_hash;

        # is this category the tracking category?
        my $is_tracking_category = $category eq "Subscription Tracking";

        my $cat_data = { catid => $catid };
        push @catids, $catid;
        my $cat_empty = 1;

        my $cat_title_key = lc($category);
        $cat_title_key =~ s/ /-/g;
        $cat_data->{title_key} = $cat_title_key;

        # add notifytype headings
        $cat_data->{notify_headers} = [];

        foreach my $notify_class (@notify_classes) {
            my $title   = eval { $notify_class->title($u) } or next;
            my $ntypeid = $notify_class->ntypeid            or next;

            # create the checkall box for this event type.
            my $disabled = !$notify_class->configured_for_user($u);

            if ( $notify_class->disabled_url && $disabled ) {
                $title = "<a href='" . $notify_class->disabled_url . "'>$title</a>";
            }
            elsif ( $notify_class->url ) {
                $title = "<a href='" . $notify_class->url . "'>$title</a>";
            }
            $title .= " " . LJ::help_icon( $notify_class->help_url ) if $notify_class->help_url;

            push @{ $cat_data->{notify_headers} },
                { ntypeid => $ntypeid, title => $title, disabled => $disabled };
        }

        # build list of subscriptions to show the user
        $cat_data->{pending_subs} = [];

        my @pending_subscriptions =
              $is_tracking_category
            ? @$cat_events
            : $u->subscription_event_filter( $cat_events, $journalu, $settings_page );

        # inbox method
        my $special_subs     = 0;
        my $unavailable_subs = 0;
        my $sub_count        = 0;
        foreach my $pending_sub (@pending_subscriptions) {
            my $sub_data = $u->pending_sub_data($pending_sub);
            next unless $sub_data;

            $sub_data->{altrow_class}   = $sub_count % 2 == 1   ? "odd"      : "even";
            $sub_data->{inactive_class} = $sub_data->{inactive} ? "inactive" : "";
            $sub_data->{disabled_class} = $sub_data->{disabled} ? "disabled" : "";

            $sub_data->{hidden_style} = $sub_data->{hidden} ? " style='visibility: hidden;'" : "";

            if ( $sub_data->{special_sub} ) {
                $special_subs++;

                push @{ $cat_data->{pending_subs} }, $sub_data;
                $sub_count++;
                next;
            }

            $unavailable_subs++ if $sub_data->{disabled};

            my $evt_class = $pending_sub->event_class or next;
            next if !$evt_class->is_visible && $settings_page;

            # override disabled below if always_checked (can't uncheck)
            my $always_checked = eval { "$evt_class"->always_checked; };
            $sub_data->{disabled} = 1 if $always_checked;

            if ($is_tracking_category) {
                next if $u->tracked_event_exclude( $pending_sub, \@prev_cats );

                my $do_show = 1;
                $do_show = 0
                    unless $displayed_tracking_count >= $displayed_tracking_start
                    && $displayed_tracking_count <= $displayed_tracking_end;
                $displayed_tracking_count++;

                if ( $do_show && $sub_data->{subscribed} ) {
                    my $subid = $pending_sub->id;

                    $sub_data->{subid}      = $subid;
                    $sub_data->{auth_token} = $u->ajax_auth_token(
                        "/__rpc_esn_subs",
                        subid  => $subid,
                        action => 'delsub'
                    );
                }

                $sub_data->{do_show} = $do_show;
            }
            else {
                $sub_data->{do_show} = 1;

                next unless eval { $evt_class->subscription_applicable($pending_sub) };
                next
                    if $u->equals($journalu)
                    && $pending_sub->journalid
                    && $pending_sub->journalid != $u->{userid};
            }

            $cat_empty = 0;    # no more nexts

            # this hook also populates %num_subs_by_type
            $sub_data->{notif_options} = LJ::Hooks::run_hook(
                'subscription_notif_options',
                u                    => $u,
                sub_data             => $sub_data,
                pending_sub          => $pending_sub,
                def_notes            => $def_notes,
                is_tracking_category => $is_tracking_category,
                num_subs_by_type     => \%num_subs_by_type,
                notify_classes       => \@notify_classes,
            );

            push @{ $cat_data->{pending_subs} }, $sub_data;
            $sub_count++;
        }

        # show blurb if not tracking anything
        $cat_data->{empty_blurb}       = $cat_empty && $is_tracking_category;
        $cat_data->{special_subs}      = $special_subs;
        $cat_data->{show_upgrade_note} = !$u->is_paid && ( $special_subs || $unavailable_subs );

        push @catdata,   $cat_data;
        push @prev_cats, $cat_hash;

        $catid++;
    }

    $page_vars->{catdata} = \@catdata;
    $page_vars->{catids}  = join ',', @catids;

    # show how many subscriptions we have active / inactive
    $page_vars->{subscription_stats} =
        LJ::Hooks::run_hook( 'subscription_stats', $u, \%num_subs_by_type );

    $page_vars->{pagination} = LJ::paging_bar(
        $page,
        ceil( $displayed_tracking_count / $num_per_page ),
        {
            self_link => sub {
                return LJ::create_url(
                    undef,
                    args      => { page => $_[0] },
                    keep_args => 1,
                    no_blank  => 1,
                    fragment  => "category-subscription-tracking"
                );
            }
        }
    );

    return DW::Template->template_string( 'tracking/subscribe-interface.tt', $page_vars );
}

# returns a placeholder link
sub placeholder_link {
    my (%opts) = @_;

    my $placeholder_html = LJ::ejs_all( delete $opts{placeholder_html} || '' );
    my $width            = delete $opts{width} || 100;
    my $height           = delete $opts{height} || 100;
    my $width_unit       = delete $opts{width_unit} || "px";
    my $height_unit      = delete $opts{height_unit} || "px";
    my $link             = delete $opts{link} || '';
    my $url              = delete $opts{url} || '';
    my $linktext         = delete $opts{linktext} || '';
    my $img              = delete $opts{img} || "$LJ::IMGPREFIX/videoplaceholder.png";

    my $direct_link =
        defined $url
        ? '<div class="embed_link"><a href="' . $url . '">' . $linktext . '</a></div>'
        : '';
    return qq {
            <div class="LJ_Placeholder_Container" style="width: ${width}${width_unit}; height: ${height}${height_unit};">
                <div class="LJ_Placeholder_HTML" style="display: none;">$placeholder_html</div>
                <div class="LJ_Container"></div>
                <a href="$link">
                    <img src="$img" class="LJ_Placeholder" title="Click to show embedded content" />
                </a>
            </div>
            $direct_link
        };
}

# this returns the right max length for a VARCHAR(255) database
# column.  but in HTML, the maxlength is characters, not bytes, so we
# have to assume 3-byte chars and return 80 instead of 255.  (80*3 ==
# 240, approximately 255).  However, we special-case Russian where
# they often need just a little bit more, and make that 100.  because
# their bytes are only 2, so 100 * 2 == 200.  as long as russians
# don't enter, say, 100 characters of japanese... but then it'd get
# truncated or throw an error.  we'll risk that and give them 20 more
# characters.
sub std_max_length {
    my $context = LJ::Lang::request_context();
    my $lang    = $context ? $context->{lang} : undef;
    return 80  if !$lang || $lang =~ /^en/;
    return 100 if $lang =~ /\b(hy|az|be|et|ka|ky|kk|lt|lv|mo|ru|tg|tk|uk|uz)\b/i;
    return 80;
}

sub final_head_html {
    my $ret = "";

    if ( my $pagestats_obj = LJ::PageStats->new ) {
        $ret .= $pagestats_obj->render_head;
    }

    return $ret;
}

# returns HTML which should appear before </body>
sub final_body_html {
    my $before_body_close = "";
    LJ::Hooks::run_hooks( 'insert_html_before_body_close', \$before_body_close );

    if ( my $pagestats_obj = LJ::PageStats->new ) {
        $before_body_close .= $pagestats_obj->render;
    }

    return $before_body_close;
}

# return a unique per pageview string based on the remote's unique cookie
sub pageview_unique_string {
    my $cached_uniq = $LJ::REQ_GLOBAL{pageview_unique_string};
    return $cached_uniq if $cached_uniq;

    my $uniq = LJ::UniqCookie->current_uniq . time() . LJ::rand_chars(8);
    $uniq = Digest::SHA1::sha1_hex($uniq);

    $LJ::REQ_GLOBAL{pageview_unique_string} = $uniq;
    return $uniq;
}

# returns canonical link for use in header of journal pages
sub canonical_link {
    my ( $url, $tid ) = @_;
    if ( $tid += 0 ) {    # sanitize input
        $url .= "?thread=$tid" . LJ::Talk::comment_anchor($tid);
    }
    return qq{<link rel="canonical" href="$url" />\n};

}

# Takes a string as input and returns a canonicalized slug. This is used in
# the logslugs table for URL generation.
sub canonicalize_slug {
    return undef unless defined $_[0];

    # If you change this, please update htdocs/stc/js/jquery.postform.js
    # to keep the regular expressions in the toSlug function in sync.
    my $str = LJ::trim( lc shift );
    $str =~ s/\s+/-/g;
    $str =~ s/[^a-z0-9_-]//gi;
    $str =~ s/-+/-/g;
    $str =~ s/^-|-$//g;
    $str = LJ::text_trim( $str, 255, 100 );

    return $str;
}

1;
