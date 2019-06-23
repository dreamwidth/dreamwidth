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
use DW::External::Site;
use DW::Request;
use LJ::Event;
use LJ::Subscription::Pending;
use LJ::Directory::Search;
use LJ::Directory::Constraint;
use LJ::PageStats;

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
    my $ic   = shift;
    my $type = shift;    # either "" or "input"
    my $attr = shift;

    my ( $attrs, $alt ) = ( '', '', 0 );
    if ($attr) {
        if ( ref $attr eq "HASH" ) {
            if ( exists $attr->{alt} ) {
                $alt = LJ::ehtml( $attr->{alt} );
                delete $attr->{alt};
            }
            $attrs .= " $_=\"" . LJ::ehtml( $attr->{$_} || '' ) . "\"" foreach keys %$attr;
        }
        else {
            $attrs = " name=\"$attr\"";
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
    return 1 if $path =~ m!^(/\w+)?/res/(\d+)/stylesheet(\?\d+)?$!;

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
#           others - arguments to pass to $u->get_authas_list.
# </LJFUNC>
sub make_authas_select {
    my ( $u, $opts ) = @_;    # type, authas, label, button

    my $authas = $opts->{authas} || $u->user;
    my $button = $opts->{button} || $BML::ML{'web.authas.btn'};

    my $foundation = $opts->{foundation} || 0;

    my @list = $u->get_authas_list($opts);

    # only do most of form if there are options to select from
    if ( @list > 1 || $list[0] ne $u->user ) {
        my $menu = LJ::html_select(
            {
                name     => 'authas',
                selected => $authas,
                class    => 'hideable',
                id       => 'authas'
            },
            map { $_, $_ } @list
        );

        my $ret = '';
        if ( $opts->{selectonly} ) {
            $ret = $menu;
        }
        else {
            $ret =
                $foundation
                ? q{<div class='row collapse'><div class='columns medium-1'><label class='inline'>}
                . LJ::Lang::ml('web.authas.select.label')
                . q{</label></div>}
                . q{<div class='columns medium-11'><div class='row'>}
                . q{<div class='columns medium-4'>}
                . $menu
                . q{</div>}
                . q{<div class='columns medium-2 end'>}
                . LJ::html_submit( undef, $button, { class => "secondary button" } )
                . q{</div>}
                . q{</div></div>}
                . q{</div>}
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
# name: LJ::make_postto_select
# des: Given a u object and some options, determines which users the given user
#      can post to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of HTML elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'authas' - current user, gets selected in drop-down;
#           'label' - label to go before form elements;
#           'button' - button label for submit button;
# </LJFUNC>
sub make_postto_select {
    my ( $u, $opts ) = @_;

    my $authas = $opts->{authas} || $u->user;
    my $label  = $opts->{label}  || $BML::ML{'web.postto.label'};
    my $button = $opts->{button} || $BML::ML{'web.postto.btn'};

    my @list = ( $u, $u->posting_access_list );

    # only do most of form if there are options to select from
    if ( @list > 1 ) {
        return "$label "
            . LJ::html_select( { name => 'authas', selected => $authas },
            map { $_->user, $_->user } @list )
            . " "
            . LJ::html_submit( undef, $button );
    }

    # no communities to choose from, give the caller a hidden
    return LJ::html_hidden( authas => $authas );
}

# <LJFUNC>
# name: LJ::help_icon
# des: Returns BML to show a help link/icon given a help topic, or nothing
#      if the site hasn't defined a URL for that topic.  Optional arguments
#      include HTML/BML to place before and after the link/icon, should it
#      be returned.
# args: topic, pre?, post?
# des-topic: Help topic key.
#            See etc/config-local.pl, or [special[helpurls]] for examples.
# des-pre: HTML/BML to place before the help icon.
# des-post: HTML/BML to place after the help icon.
# </LJFUNC>
sub help_icon {
    my $topic = shift;
    my $pre   = shift;
    my $post  = shift;
    return "" unless ( defined $LJ::HELPURL{$topic} );
    return "$pre<?help $LJ::HELPURL{$topic} help?>$post";
}

# like help_icon, but no BML.
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
# name: LJ::bad_input
# des: Returns common BML for reporting form validation errors in
#      a bulleted list.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub bad_input {
    my @errors = @_;
    my $ret    = "";
    $ret .= "<?badcontent?>\n<ul>\n";
    foreach my $ei (@errors) {
        my $err = LJ::errobj($ei) or next;
        $err->log;
        $ret .= $err->as_bullets;
    }
    $ret .= "</ul>\n";
    return $ret;
}

# <LJFUNC>
# name: LJ::error_list
# des: Returns an error bar with bulleted list of errors.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub error_list {

    # FIXME: retrofit like bad_input above?  merge?  make aliases for each other?
    my @errors = @_;
    my $ret;
    $ret .= "<?errorbar ";
    $ret .= "<strong>";
    $ret .= BML::ml('error.procrequest');
    $ret .= "</strong><ul>";

    foreach my $ei (@errors) {
        my $err = LJ::errobj($ei) or next;
        $err->log;
        $ret .= $err->as_bullets;
    }
    $ret .= " </ul> errorbar?>";
    return $ret;
}

# <LJFUNC>
# name: LJ::error_noremote
# des: Returns an error telling the user to log in.
# returns: Translation string "error.notloggedin"
# </LJFUNC>
sub error_noremote {
    return "<?needlogin?>";
}

# <LJFUNC>
# name: LJ::warning_list
# des: Returns a warning bar with bulleted list of warnings.
# returns: BML showing warnings
# args: warnings*
# des-warnings: A list of warnings
# </LJFUNC>
sub warning_list {
    my @warnings = @_;
    my $ret;

    $ret .= "<?warningbar ";
    $ret .= "<strong>";
    $ret .= BML::ml('label.warning');
    $ret .= "</strong><ul>";

    foreach (@warnings) {
        $ret .= "<li>$_</li>";
    }
    $ret .= " </ul> warningbar?>";
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
    return ( BML::get_method() eq "POST" );
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
Drop-in replacement for BML::paging in non-BML context.
=cut

sub paging {
    my ( $listref, $page, $pagesize ) = @_;
    $page = 1 unless $page && $page == int $page;
    return unless $pagesize;    # let's not divide by zero
    my @items = @{$listref};
    my %self;

    my $newurl = sub {

        # replaces BML::page_newurl
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

# Returns HTML to display user search results
# Args: %args
# des-args:
#           users    => hash ref of userid => u object like LJ::load userids
#                       returns or array ref of user objects
#           userids  => array ref of userids to include in results, ignored
#                       if users is defined
#           timesort => set to 1 to sort by last updated instead
#                       of username
#           perpage  => Enable pagination and how many users to display on
#                       each page
#           curpage  => What page of results to display
#           navbar   => Scalar reference for paging bar
#           pickwd   => userpic keyword to display instead of default if it
#                       exists for the user
#           self_link => Sub ref to generate link to use for pagination
sub user_search_display {
    my %args = @_;

    my $loaded_users;
    unless ( defined $args{users} ) {
        $loaded_users = LJ::load_userids( @{ $args{userids} } );
    }
    else {
        if ( ref $args{users} eq 'HASH' ) {    # Assume this is direct from LJ::load_userids
            $loaded_users = $args{users};
        }
        elsif ( ref $args{users} eq 'ARRAY' ) {    # They did a grep on it or something
            foreach ( @{ $args{users} } ) {
                $loaded_users->{ $_->userid } = $_;
            }
        }
        else {
            return undef;
        }
    }

    # If we're sorting by last updated, we need to load that
    # info for all users before the sort.  If sorting by
    # username we can load it for a subset of users later,
    # if paginating.
    my $updated;
    my $disp_sort;

    if ( $args{timesort} ) {
        $updated = LJ::get_timeupdate_multi( keys %$loaded_users );
        my $def_upd = sub { $updated->{ $_[0]->userid } || 0 };

        # let undefined values be zero for sorting purposes
        $disp_sort = sub { $def_upd->($b) <=> $def_upd->($a) };
    }
    else {
        $disp_sort = sub { $a->{user} cmp $b->{user} };
    }

    my @display = sort $disp_sort values %$loaded_users;

    if ( defined $args{perpage} ) {
        my %items = LJ::paging( \@display, $args{curpage}, $args{perpage} );

        # Fancy paging bar
        my $opts;
        $opts->{self_link} = $args{self_link} if $args{self_link};
        ${ $args{navbar} } = LJ::paging_bar( $items{'page'}, $items{'pages'}, $opts );

        # Now pull out the set of users to display
        @display = @{ $items{'items'} };
    }

    # If we aren't sorting by time updated, load last updated time for the
    # set of users we are displaying.
    $updated = LJ::get_timeupdate_multi( map { $_->userid } @display )
        unless $args{timesort};

    # Allow caller to specify a custom userpic to use instead
    # of the user's default all userpics
    my $get_picid = sub {
        my $u = shift;
        return $u->{'defaultpicid'} unless defined $args{'pickwd'};
        return $u->get_picid_from_keyword( $args{pickwd} );
    };

    my $ret;
    foreach my $u (@display) {

        # We should always have loaded user objects, but it seems
        # when the site is overloaded we don't always load the users
        # we request.
        next unless LJ::isu($u);

        $ret .= "<div class='user-search-display'>";
        $ret .= "<table summary='' style='height: 105px'><tr>";

        $ret .= "<td style='width: 100px; text-align: center;'>";
        $ret .= "<a href='" . $u->allpics_base . "'>";
        if ( my $picid = $get_picid->($u) ) {
            $ret .= "<img src='$LJ::USERPIC_ROOT/$picid/" . $u->userid . "' alt='";
            $ret .= $u->user . " userpic' style='border: 1px solid #000;' />";
        }
        else {
            $ret .= LJ::img( "nouserpic", "", { style => 'border: 1px solid #000;' } );
        }
        $ret .= "</a>";

        $ret .= "</td><td style='padding-left: 5px;' valign='top'><table summary=''>";

        $ret .= "<tr><td class='searchusername' colspan='2' style='text-align: left;'>";
        $ret .= $u->ljuser_display( { head_size => $args{head_size} } );
        $ret .= "</td></tr><tr>";

        if ( $u->{name} ) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>"
                . BML::ml('search.user.name');
            $ret .= "</td><td style='font-size: smaller'><a href='" . $u->profile_url . "'>";
            $ret .= LJ::ehtml( $u->{name} );
            $ret .= "</a>";
            $ret .= "</td></tr><tr>";
        }

        if ( my $jtitle = $u->prop('journaltitle') ) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>"
                . BML::ml('search.user.journal');
            $ret .= "</td><td style='font-size: smaller'><a href='" . $u->journal_base . "'>";
            $ret .= LJ::ehtml($jtitle) . "</a>";
            $ret .= "</td></tr>";
        }

        $ret .=
            "<tr><td colspan='2' style='text-align: left; font-size: smaller' class='lastupdated'>";

        my $upd = $updated->{ $u->userid };
        if ( defined $upd && $upd > 0 ) {
            $ret .= LJ::Lang::ml( 'search.user.update.last', { time => LJ::diff_ago_text($upd) } );
        }
        else {
            $ret .= LJ::Lang::ml('search.user.update.never');
        }

        $ret .= "</td></tr>";

        $ret .= "</table>";
        $ret .= "</td></tr>";
        $ret .= "</table></div>";
    }

    return $ret;
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
#              If not supplied, will be retrieved with BML::get_client_header.
#              In general, you don't want to pass this yourself unless
#              you already have it or know we can't get it from BML.
# returns: 1 if they're coming from that URI, else undef
# </LJFUNC>
sub check_referer {
    my $uri     = shift(@_) || '';
    my $referer = shift(@_) || BML::get_client_header('Referer');

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
        if $LJ::USER_VHOSTS && $referer =~ m!^https?://([A-Za-z0-9_\-]{1,25})\.\Q$LJ::DOMAIN\E$uri!;
    return 1 if $origuri =~ m!^https?://! && $origreferer eq $origuri;
    return undef;
}

# <LJFUNC>
# name: LJ::icons_for_remote
# class: web
# des: Gets all the userpics for a given user, including an item for the default userpic.
# args: remote
# des-remote: a user object.
# returns: An array of {value => ..., text => ..., data => { url => ...}}
#          hashrefs, suitable for use as the items in an LJ::html_select().
#          If no userpics or if remote is undefined, an empty array.
# </LJFUNC>
sub icons_for_remote {
    my ($remote) = @_;
    my @pics;

    {
        my %res;
        if ($remote) {
            LJ::do_request(
                {
                    mode         => "login",
                    ver          => $LJ::PROTOCOL_VER,
                    user         => $remote->user,
                    getpickws    => 1,
                    getpickwurls => 1,
                },
                \%res,
                { noauth => 1, userid => $remote->userid }
            );
        }

        if ( $res{pickw_count} ) {
            for ( my $i = 1 ; $i <= $res{pickw_count} ; $i++ ) {
                push @pics, [ $res{"pickw_$i"}, $res{"pickwurl_$i"} ];
            }
            @pics = sort { lc( $a->[0] ) cmp lc( $b->[0] ) } @pics;
            @pics = (
                {
                    value => "",
                    text  => LJ::Lang::ml('/talkpost.bml.opt.defpic'),
                    data  => { url => $res{defaultpicurl} }
                },
                map { { value => $_->[0], text => $_->[0], data => { url => $_->[1] } } } @pics
            );
        }
    }
    return @pics;
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
        $chal = LJ::challenge_generate( 86400, $auth );
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
    my $formauth = shift || $BMLCodeBlock::POST{'lj_form_auth'};
    return 0 unless $formauth;

    my $remote = LJ::get_remote();
    my $id     = $remote ? $remote->id : 0;
    my $sess   = $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;

    # check the attributes are as they should be
    my $attr = LJ::get_challenge_attributes($formauth);
    my ( $randchars, $chal_id, $chal_sess ) = split( /\-/, $attr );

    return 0 unless $id == $chal_id;
    return 0 unless $sess eq $chal_sess;

    # check the signature is good and not expired
    my $opts = { dont_check_count => 1 };    # in/out
    LJ::challenge_check( $formauth, $opts );
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
        { 'name' => 'replyto',        'id' => 'replyto',        'value' => '' },
        { 'name' => 'parenttalkid',   'id' => 'parenttalkid',   'value' => '' },
        { 'name' => 'journal',        'id' => 'journal',        'value' => $u->{'user'} },
        { 'name' => 'itemid',         'id' => 'itemid',         'value' => $ditemid },
        { 'name' => 'usertype',       'id' => 'usertype',       'value' => $usertype },
        { 'name' => 'qr',             'id' => 'qr',             'value' => '1' },
        { 'name' => 'cookieuser',     'id' => 'cookieuser',     'value' => $remote->{'user'} },
        { 'name' => 'dtid',           'id' => 'dtid',           'value' => '' },
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

    # For userpic selector
    my @pics = icons_for_remote($remote);

    my $post_disabled = $u->does_not_allow_comments_from($remote)
        || $u->does_not_allow_comments_from_unconfirmed_openid($remote);
    return DW::Template->template_string(
        'journal/quickreply.tt',
        {
            form_url             => LJ::create_url( '/talkpost_do', host => $LJ::DOMAIN_WEB ),
            hidden_form_elements => $hidden_form_elements,
            can_checkspell       => $LJ::SPELLER ? 1 : 0,
            minimal              => $opts{minimal} ? 1 : 0,
            post_disabled        => $post_disabled,
            post_button_class    => $post_disabled ? 'ui-state-disabled' : '',

            current_icon_kw => $userpic_kw,
            current_icon    => LJ::Userpic->new_from_keyword( $remote, $userpic_kw ),

            remote => {
                ljuser => $remote->ljuser_display,
                user   => $remote->user,

                icons_url              => $remote->allpics_base,
                icons                  => \@pics,
                can_use_iconbrowser    => $remote->can_use_userpic_select,
                iconbrowser_metatext   => $remote->iconbrowser_metatext ? "true" : "false",
                iconbrowser_smallicons => $remote->iconbrowser_smallicons ? "true" : "false",
            },

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

sub deemp {
    "<span class='de'>$_[0]</span>";
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

# <LJFUNC>
# name: LJ::entry_form
# class: web
# des: Returns a properly formatted form for creating/editing entries.
# args: head, onload, opts
# des-head: string reference for the <head> section (JavaScript previews, etc).
# des-onload: string reference for JavaScript functions to be called on page load
# des-opts: hashref of keys/values:
#           mode: either "update" or "edit", depending on context;
#           datetime: date and time, formatted yyyy-mm-dd hh:mm;
#           remote: remote u object;
#           subject: entry subject;
#           event: entry text;
#           richtext: allow rich text formatting;
#           auth_as_remote: bool option to authenticate as remote user, pre-filling pic/friend groups/etc.
# return: form to include in BML pages.
# </LJFUNC>
sub entry_form {
    my ( $opts, $head, $onload, $errors ) = @_;

    my $out      = "";
    my $remote   = $opts->{remote};
    my $altlogin = $opts->{altlogin};
    my ( $moodlist, $moodpics );

    # usejournal has no point if you're trying to use the account you're logged in as,
    # so disregard it so we can assume that if it exists, we're trying to post to an
    # account that isn't us
    if ( $remote && $opts->{usejournal} && $remote->{user} eq $opts->{usejournal} ) {
        delete $opts->{usejournal};
    }

    # Temp fix for FF 2.0.0.17
    my $rte_is_supported = LJ::is_enabled( 'rte_support', BML::get_client_header("User-Agent") );
    $opts->{'richtext_default'} = 0 unless $rte_is_supported;

    $opts->{'richtext'} = $opts->{'richtext_default'};
    my $tabnum = 10;    #make allowance for username and password
                        # Leave gaps for interpolated fields eg date/time
    my $tabindex = sub { return ( $tabnum += 10 ) - 10; };
    $opts->{'event'} = LJ::durl( $opts->{'event'} ) if $opts->{'mode'} eq "edit";

    # 1 hour auth token, should be adequate
    my $chal = LJ::challenge_generate(3600);
    $out .= "\n\n<div id='entry-form-wrapper'>";
    $out .= "\n<input type='hidden' name='chal' id='login_chal' value='$chal' />\n";
    $out .= "<input type='hidden' name='response' id='login_response' value='' />\n\n";
    $out .= LJ::error_list( $errors->{entry} ) if $errors->{entry};

    ### Icon Selection

    my $pic     = '';    # displays chosen/default pic
    my $picform = '';    # displays form drop-down

    LJ::Widget::UserpicSelector->render(
        picargs              => [ $remote, \$$head, \$pic, \$picform ],
        prop_picture_keyword => $opts->{prop_picture_keyword},
        no_auth              => !$opts->{auth_as_remote},
        onload               => $onload,
        altlogin             => $altlogin,
        entry_js             => 1
    );

    # libs for userpicselect
    LJ::need_res( LJ::Talk::init_iconbrowser_js() )
        if !$altlogin && $remote && $remote->can_use_userpic_select;

    $out .= $pic;

    ### Meta Information Column 1
    {
        # do a login action to get usejournals, but only if using remote
        my $res;
        $res = LJ::Protocol::do_request(
            "login",
            {
                ver      => $LJ::PROTOCOL_VER,
                username => $remote->user,
            },
            undef,
            {
                noauth => 1,
                u      => $remote,
            }
        ) if $opts->{auth_as_remote};

        $out .= "<div id='metainfo'>\n\n";

        # login info
        $out .= $opts->{'auth'};
        if ( $opts->{'mode'} eq "update" ) {

            # communities the user can post in
            my $usejournal = $opts->{'usejournal'};
            if ($usejournal) {
                $out .= "<p id='usejournal_single' class='pkg'>\n";
                $out .=
                      "<label for='usejournal' class='left'>"
                    . BML::ml('entryform.postto')
                    . "</label>\n";
                $out .= LJ::ljuser($usejournal);
                $out .= LJ::html_hidden(
                    { name => 'usejournal', value => $usejournal, id => 'usejournal_username' } );
                $out .= LJ::html_hidden( usejournal_set => 'true' );
                $out .= "</p>\n";
            }
            elsif ( $res && ref $res->{'usejournals'} eq 'ARRAY' ) {
                my $submitprefix = BML::ml('entryform.update3');
                $out .= "<p id='usejournal_list' class='pkg'>\n";
                $out .=
                      "<label for='usejournal' class='left'>"
                    . BML::ml('entryform.postto')
                    . "</label>\n";
                $out .= LJ::html_select(
                    {
                        'name'     => 'usejournal',
                        'id'       => 'usejournal',
                        'selected' => $usejournal,
                        'tabindex' => $tabindex->(),
                        'class'    => 'select',
                        "onchange" => "changeSubmit('"
                            . $submitprefix . "','"
                            . $remote->{'user'}
                            . "'); getUserTags('$remote->{user}'); changeSecurityOptions('$remote->{user}'); XPostAccount.updateXpostFromJournal('$remote->{user}');"
                    },
                    "",
                    $remote->{'user'},
                    map { $_, $_ } @{ $res->{'usejournals'} }
                ) . "\n";
                $out .= "</p>\n";
            }
        }

        # Authentication box
        $out .= "<p class='update-errors'><?inerr $errors->{'auth'} inerr?></p>\n"
            if $errors->{'auth'};

        # Date / Time
        {
            my ( $year, $mon, $mday, $hour, $min ) = split( /\D/, $opts->{'datetime'} );
            my $monthlong = LJ::Lang::month_long($mon);

            # date entry boxes / formatting note
            my $datetime = LJ::html_datetime(
                {
                    name     => 'date_ymd',
                    notime   => 1,
                    default  => "$year-$mon-$mday",
                    tabindex => $tabindex->(),
                    disabled => $opts->{'disabled_save'}
                }
            );
            $datetime .= "<span class='float-left'>&nbsp;&nbsp;</span>";
            $datetime .= LJ::html_text(
                {
                    size      => 2,
                    class     => 'text',
                    maxlength => 2,
                    value     => $hour,
                    name      => "hour",
                    tabindex  => $tabindex->(),
                    disabled  => $opts->{'disabled_save'}
                }
            ) . "<span class='float-left'>:</span>";
            $datetime .= LJ::html_text(
                {
                    size      => 2,
                    class     => 'text',
                    maxlength => 2,
                    value     => $min,
                    name      => "min",
                    tabindex  => $tabindex->(),
                    disabled  => $opts->{'disabled_save'}
                }
            );

            # JavaScript sets this value, so we know that the time we get is correct
            # but always trust the time if we've been through the form already
            my $date_diff = ( $opts->{'mode'} eq "edit" || $opts->{'spellcheck_html'} ) ? 1 : 0;
            $datetime .= LJ::html_hidden( "date_diff", $date_diff );

            # but if we don't have JS, give a signal to trust the given time
            $datetime .= "<noscript>" . LJ::html_hidden( "date_diff_nojs", "1" ) . "</noscript>";

            $out .= "<p class='pkg'>\n";
            $out .=
                "<label for='modifydate' class='left'>" . BML::ml('entryform.date') . "</label>\n";
            $out .=
"<span id='currentdate' class='float-left'><span id='currentdate-date'>$monthlong $mday, $year, $hour"
                . ":"
                . "$min</span> <a href='javascript:void(0)' onclick='editdate();' id='currentdate-edit'>"
                . BML::ml('entryform.date.edit')
                . "</a></span>\n";
            $out .=
                  "<span id='modifydate'>$datetime <?de "
                . BML::ml('entryform.date.24hournote')
                . " de?><br />\n";
            $out .= LJ::html_check(
                {
                    'type'     => "check",
                    'id'       => "prop_opt_backdated",
                    'name'     => "prop_opt_backdated",
                    "value"    => 1,
                    'selected' => $opts->{'prop_opt_backdated'},
                    'tabindex' => $tabindex->()
                }
            );
            $out .=
                  "<label for='prop_opt_backdated' class='right'>"
                . BML::ml('entryform.backdated4')
                . "</label>\n";
            $out .= LJ::help_icon_html( "backdate", "", "" ) . "\n";
            $out .= "</span><!-- end #modifydate -->\n";
            $out .= "</p>\n";
            $out .=
                  "<noscript><p id='time-correct' class='small'>"
                . BML::ml('entryform.nojstime.note')
                . "</p></noscript>\n";
            $$onload .= " defaultDate();";
        }

        # User Picture
        {
            my $tab = $tabindex->();
            $picform =~ s/~~TABINDEX~~/$tab/;
            $out .= $picform;
        }

        $out .= "</div><!-- end #metainfo -->\n\n";

        ### Other Posting Options
        {
            $out .= "<div id='infobox'>\n";
            $out .=
                LJ::Hooks::run_hook( 'entryforminfo', $opts->{'usejournal'}, $opts->{'remote'} );
            $out .= "</div><!-- end #infobox -->\n\n";
        }

        ### Subject
        $out .= "<div id='compose-entry' class='pkg'>\n";

        $out .= "<label class='left' for='subject'>" . BML::ml('entryform.subject') . "</label>\n";
        $out .= LJ::html_text(
            {
                'name'      => 'subject',
                'value'     => $opts->{'subject'},
                'class'     => 'text',
                'id'        => 'subject',
                'size'      => '43',
                'maxlength' => '100',
                'tabindex'  => $tabindex->(),
                'disabled'  => $opts->{'disabled_save'}
            }
        ) . "\n";
        $out .= "<ul id='entry-tabs' style='display: none;'>\n";
        $out .= "<li id='jrich'>"
            . BML::ml(
            "entryform.htmlokay.rich4",
            {
                'opts' => 'href="javascript:void(0);" onclick="return useRichText(\'draft\', \''
                    . $LJ::WSTATPREFIX . '\');"'
            }
            )
            . "</li>\n"
            if $rte_is_supported;
        $out .= "<li id='jplain' class='on'>"
            . BML::ml( "entryform.plainswitch2",
            { 'aopts' => 'href="javascript:void(0);" onclick="return usePlainText(\'draft\');"' } )
            . "</li>\n";
        $out     .= "</ul>";
        $out     .= "</div><!-- end #entry -->\n\n";
        $$onload .= " showEntryTabs();";
    }

    ### Display Spell Check Results:
    $out .=
          "<div id='spellcheck-results'><strong>"
        . BML::ml('entryform.spellchecked')
        . "</strong><br />$opts->{'spellcheck_html'}</div>\n"
        if $opts->{'spellcheck_html'};

    ### Insert Object Toolbar:
    LJ::need_res(
        qw(
            js/6alib/core.js
            js/6alib/dom.js
            js/6alib/ippu.js
            js/lj_ippu.js
            )
    );
    $out .= "<div id='htmltools' class='pkg'>\n";
    $out .= "<ul class='pkg'>\n";
    $out .=
"<li class='image'><a href='javascript:void(0);' onclick='InOb.handleInsertImage();' title='"
        . BML::ml('fckland.ljimage') . "'>"
        . BML::ml('entryform.insert.image2')
        . "</a></li>\n";
    $out .=
"<li class='media'><a href='javascript:void(0);' onclick='InOb.handleInsertEmbed();' title='"
        . BML::ml('fcklang.ljvideo2') . "'>"
        . BML::ml('fcklang.ljvideo2')
        . "</a></li>\n"
        if LJ::is_enabled('embed_module');
    $out .= "</ul>\n";
    my $format_selected =
           ( $opts->{mode} eq "update" && $remote && $remote->disable_auto_formatting )
        || $opts->{'prop_opt_preformatted'}
        || $opts->{'event_format'} ? "checked='checked'" : "";
    $out .=
"<span id='linebreaks'><input type='checkbox' class='check' value='preformatted' name='event_format' id='event_format' $format_selected  />
            <label for='event_format'>"
        . BML::ml('entryform.format3')
        . "</label>"
        . LJ::help_icon_html( "noautoformat", "", " " )
        . "</span>\n";
    $out .= "</div>\n\n";

    ### Draft Status Area
    $out .= "<div id='draft-container' class='pkg'>\n";
    $out .= LJ::html_textarea(
        {
            'name'     => 'event',
            'value'    => $opts->{'event'},
            'rows'     => '20',
            'cols'     => '50',
            'style'    => '',
            'tabindex' => $tabindex->(),
            'wrap'     => 'soft',
            'disabled' => $opts->{'disabled_save'},
            'id'       => 'draft'
        }
    ) . "\n";
    $out .= "</div><!-- end #draft-container -->\n\n";
    $out .= "<input type='text' disabled='disabled' name='draftstatus' id='draftstatus' />\n\n";
    LJ::need_res( 'stc/fck/fckeditor.js', 'js/rte.js', 'stc/display_none.css' );
    if ( !$opts->{'did_spellcheck'} ) {

        my $jnorich = LJ::ejs( LJ::deemp( BML::ml('entryform.htmlokay.norich2') ) );

        $out .= <<RTE;
        <script language='JavaScript' type='text/javascript'>
            <!--

        // Check if this browser supports FCKeditor
        var rte = new FCKeditor();
        var t = rte._IsCompatibleBrowser();
        if (t) {
RTE

        my @sites = DW::External::Site->get_sites;
        my @sitevalues;
        foreach my $site ( sort { $a->{sitename} cmp $b->{sitename} } @sites ) {
            push @sitevalues, { domain => $site->{domain}, sitename => $site->{sitename} };
        }

        $out .= "var FCKLang;\n";
        $out .= "if (!FCKLang) FCKLang = {};\n";
        $out .= "FCKLang.UserPrompt = \"" . LJ::ejs( BML::ml('fcklang.userprompt') ) . "\";\n";
        $out .= "FCKLang.UserPrompt_User = \""
            . LJ::ejs( BML::ml('fcklang.userprompt.user') ) . "\";\n";
        $out .= "FCKLang.UserPrompt_Site = \""
            . LJ::ejs( BML::ml('fcklang.userprompt.site') ) . "\";\n";
        $out .= "FCKLang.UserPrompt_SiteList =" . LJ::js_dumper( \@sitevalues ) . ";\n";
        $out .= "FCKLang.InvalidChars = \"" . LJ::ejs( BML::ml('fcklang.invalidchars') ) . "\";\n";
        $out .= "FCKLang.LJUser = \"" . LJ::ejs( BML::ml('fcklang.ljuser') ) . "\";\n";
        $out .= "FCKLang.LJVideo = \"" . LJ::ejs( BML::ml('fcklang.ljvideo2') ) . "\";\n";
        $out .=
            "FCKLang.EmbedContents = \"" . LJ::ejs( BML::ml('fcklang.embedcontents') ) . "\";\n";
        $out .= "FCKLang.EmbedPrompt = \"" . LJ::ejs( BML::ml('fcklang.embedprompt') ) . "\";\n";
        $out .= "FCKLang.CutPrompt = \"" . LJ::ejs( BML::ml('fcklang.cutprompt') ) . "\";\n";
        $out .= "FCKLang.ReadMore = \"" . LJ::ejs( BML::ml('fcklang.readmore') ) . "\";\n";
        $out .= "FCKLang.CutContents = \"" . LJ::ejs( BML::ml('fcklang.cutcontents') ) . "\";\n";
        $out .= "FCKLang.LJCut = \"" . LJ::ejs( BML::ml('fcklang.ljcut') ) . "\";\n";

        if ( $opts->{'richtext_default'} ) {
            $$onload .= 'useRichText("draft", "' . LJ::ejs($LJ::WSTATPREFIX) . '");';
        }

        {
            my $jrich = LJ::ejs(
                LJ::deemp(
                    BML::ml(
                        "entryform.htmlokay.rich2",
                        {
                            'opts' =>
'href="javascript:void(0);" onclick="return useRichText(\'draft\', \''
                                . LJ::ejs($LJ::WSTATPREFIX) . '\');"'
                        }
                    )
                )
            );

            my $jplain = LJ::ejs(
                LJ::deemp(
                    BML::ml(
                        "entryform.plainswitch",
                        {
                            'aopts' =>
'href="javascript:void(0);" onclick="return usePlainText(\'draft\');"'
                        }
                    )
                )
            );
        }

        $out .= <<RTE;
        } else {
            document.getElementById('entry-tabs').style.visibility = 'hidden';
            document.getElementById('htmltools').style.display = 'block';
            document.write("$jnorich");
            usePlainText('draft');
        }
        //-->
            </script>
RTE

        $out .=
            '<noscript><?de ' . BML::ml('entryform.htmlokay.norich2') . ' de?><br /></noscript>';
    }
    $out .= LJ::html_hidden( { name => 'switched_rte_on', id => 'switched_rte_on', value => '0' } );

    $out .= "<div id='options' class='pkg'>";
    if ( !$opts->{'disabled_save'} ) {
        ### Options

        # Tag labeling
        if ( LJ::is_enabled('tags') ) {
            $out .= "<p class='pkg'>";
            $out .=
                  "<label for='prop_taglist' class='left options'>"
                . BML::ml('entryform.tags')
                . "</label>";
            $out .= LJ::html_text(
                {
                    'name'     => 'prop_taglist',
                    'id'       => 'prop_taglist',
                    'class'    => 'text',
                    'size'     => '35',
                    'value'    => $opts->{'prop_taglist'},
                    'tabindex' => $tabindex->(),
                    'raw'      => "autocomplete='off'",
                }
            );
            $out .= LJ::help_icon_html('addtags');
            $out .= "</p>";
        }

        $out .= "<p class='pkg'>\n";
        $out .= "<span id='prop_mood_wrapper' class='inputgroup-left'>\n";
        $out .=
              "<label for='prop_current_moodid' class='left options'>"
            . BML::ml('entryform.mood')
            . "</label>";

        # Current Mood
        {
            my @moodlist = ( '', BML::ml('entryform.mood.noneother') );
            my $sel;

            my $moods = DW::Mood->get_moods;

            foreach ( sort { $moods->{$a}->{'name'} cmp $moods->{$b}->{'name'} } keys %$moods ) {
                push @moodlist, ( $_, $moods->{$_}->{'name'} );

                if (   $opts->{prop_current_mood}
                    && $opts->{prop_current_mood} eq $moods->{$_}->{name}
                    || $opts->{prop_current_moodid} && $opts->{prop_current_moodid} == $_ )
                {
                    $sel = $_;
                }
            }

            if ($remote) {
                my $r_theme = DW::Mood->new( $remote->{'moodthemeid'} );
                foreach my $mood ( keys %$moods ) {
                    my $moodid = $moods->{$mood}->{id};
                    if ( $r_theme && $r_theme->get_picture( $moodid, \my %pic ) ) {
                        $moodlist .= "    moods[" . $moodid;
                        $moodlist .= "] = \"";
                        $moodlist .= $moods->{$mood}->{name} . "\";\n";
                        $moodpics .= "    moodpics[" . $moodid;
                        $moodpics .= "] = \"";
                        $moodpics .= $pic{pic} . "\";\n";
                    }
                }
                $$onload .= " mood_preview();";
                $$head   .= <<MOODS;
<script type="text/javascript" language="JavaScript"><!--
if (document.getElementById) {
    var moodpics = new Array();
    $moodpics
    var moods    = new Array();
    $moodlist
}
//--></script>
MOODS
            }
            my $moodpreviewoc;
            $moodpreviewoc = 'mood_preview()' if $remote;
            $out .= LJ::html_select(
                {
                    'name'     => 'prop_current_moodid',
                    'id'       => 'prop_current_moodid',
                    'selected' => $sel,
                    'onchange' => $moodpreviewoc,
                    'class'    => 'select',
                    'tabindex' => $tabindex->()
                },
                @moodlist
            );
            $out .= " "
                . LJ::html_text(
                {
                    'name'      => 'prop_current_mood',
                    'id'        => 'prop_current_mood',
                    'class'     => 'text',
                    'value'     => $opts->{'prop_current_mood'},
                    'onchange'  => $moodpreviewoc,
                    'size'      => '15',
                    'maxlength' => '30',
                    'tabindex'  => $tabindex->()
                }
                );
        }
        $out .= "<span id='mood_preview'></span>";
        $out .= "</span>\n";
        $out .= "<span class='inputgroup-right'>\n";
        $out .=
              "<label for='comment_settings' class='left options'>"
            . BML::ml('entryform.comment.settings2')
            . "</label>\n";

        # Comment Settings
        my $comment_settings_selected = sub {
            return "noemail" if $opts->{'prop_opt_noemail'};
            return "nocomments"
                if $opts->{prop_opt_nocomments} || $opts->{prop_opt_nocomments_maintainer};
            return $opts->{'comment_settings'};
        };

        my $comment_settings_journaldefault = sub {
            return "Disabled"
                if $opts->{prop_opt_default_nocomments}
                && $opts->{prop_opt_default_nocomments} eq 'N';
            return "No Email"
                if $opts->{prop_opt_default_noemail} && $opts->{prop_opt_default_noemail} eq 'N';
            return "Enabled";
        };

        my $nocomments_display =
            $opts->{prop_opt_nocomments_maintainer}
            ? 'entryform.comment.settings.nocomments.admin'
            : 'entryform.comment.settings.nocomments';

        my $comment_settings_default = BML::ml( 'entryform.comment.settings.default5',
            { 'aopts' => $comment_settings_journaldefault->() } );
        $out .= LJ::html_select(
            {
                'name'     => "comment_settings",
                'id'       => 'comment_settings',
                'class'    => 'select',
                'selected' => $comment_settings_selected->(),
                'tabindex' => $tabindex->()
            },
            "",
            $comment_settings_default,
            "nocomments",
            BML::ml( $nocomments_display, "noemail" ),
            "noemail",
            BML::ml('entryform.comment.settings.noemail')
        );
        $out .= LJ::help_icon_html( "comment", "", " " );
        $out .= "\n";
        $out .= "</span>\n";
        $out .= "</p>\n";

        # Current Location
        $out .= "<p class='pkg'>";
        if ( LJ::is_enabled('web_current_location') ) {
            $out .= "<span class='inputgroup-left'>";
            $out .=
                  "<label for='prop_current_location' class='left options'>"
                . BML::ml('entryform.location')
                . "</label>";
            $out .= LJ::html_text(
                {
                    name      => 'prop_current_location',
                    value     => $opts->{prop_current_location},
                    id        => 'prop_current_location',
                    class     => 'text',
                    size      => '35',
                    maxlength => LJ::std_max_length(),
                    tabindex  => $tabindex->()
                }
            ) . "\n";
            $out .= "</span>";
        }

        # Comment Screening settings
        $out .= "<span class='inputgroup-right'>\n";
        $out .=
              "<label for='prop_opt_screening' class='left options'>"
            . BML::ml('entryform.comment.screening2')
            . "</label>\n";
        my $opt_default_screen = $opts->{prop_opt_default_screening} || '';
        my $screening_levels_default =
              $opt_default_screen eq 'N' ? BML::ml('label.screening.none2')
            : $opt_default_screen eq 'R' ? BML::ml('label.screening.anonymous2')
            : $opt_default_screen eq 'F' ? BML::ml('label.screening.nonfriends2')
            : $opt_default_screen eq 'A' ? BML::ml('label.screening.all2')
            :                              BML::ml('label.screening.none2');
        my @levels = (
            '',  BML::ml( 'label.screening.default4', { 'aopts' => $screening_levels_default } ),
            'N', BML::ml('label.screening.none2'),
            'R', BML::ml('label.screening.anonymous2'),
            'F', BML::ml('label.screening.nonfriends2'),
            'A', BML::ml('label.screening.all2')
        );
        $out .= LJ::html_select(
            {
                'name'     => 'prop_opt_screening',
                'id'       => 'prop_opt_screening',
                'class'    => 'select',
                'selected' => $opts->{'prop_opt_screening'},
                'tabindex' => $tabindex->()
            },
            @levels
        );
        $out .= LJ::help_icon_html( "screening", "", " " );
        $out .= "</span>\n";
        $out .= "</p>\n";

        # Current Music
        $out .= "<p class='pkg'>\n";
        $out .= "<span class='inputgroup-left'>\n";
        $out .=
              "<label for='prop_current_music' class='left options'>"
            . BML::ml('entryform.music')
            . "</label>\n";

        # BML::ml('entryform.music')
        $out .= LJ::html_text(
            {
                name      => 'prop_current_music',
                value     => $opts->{prop_current_music},
                id        => 'prop_current_music',
                class     => 'text',
                size      => '35',
                maxlength => LJ::std_max_length(),
                tabindex  => $tabindex->()
            }
        ) . "\n";
        $out .= "</span>\n";
        $out .= "<span class='inputgroup-right'>";

        # Content Flag
        if ( LJ::is_enabled('adult_content') ) {
            my @adult_content_menu = (
                ""       => BML::ml('entryform.adultcontent.default'),
                none     => BML::ml('entryform.adultcontent.none'),
                concepts => BML::ml('entryform.adultcontent.concepts'),
                explicit => BML::ml('entryform.adultcontent.explicit'),
            );

            $out .=
                  "<label for='prop_adult_content' class='left options'>"
                . BML::ml('entryform.adultcontent')
                . "</label>\n";
            $out .= LJ::html_select(
                {
                    name     => 'prop_adult_content',
                    id       => 'prop_adult_content',
                    class    => 'select',
                    selected => $opts->{prop_adult_content} || "",
                    tabindex => $tabindex->(),
                },
                @adult_content_menu
            );
            $out .= LJ::help_icon_html( "adult_content", "", " " );
        }
        $out .= "</span>\n";
        $out .= "</p>\n";

        if ( LJ::is_enabled('adult_content') ) {
            $out .= "<p class='pkg'>";
            $out .=
                  "<label for='prop_adult_content_reason' class='left options'>"
                . BML::ml('entryform.adultcontentreason')
                . "</label>";
            $out .= LJ::html_text(
                {
                    'name'      => 'prop_adult_content_reason',
                    'id'        => 'prop_adult_content_reason',
                    'class'     => 'text',
                    'size'      => '35',
                    'maxlength' => '255',
                    'value'     => $opts->{'prop_adult_content_reason'},
                    'tabindex'  => $tabindex->(),
                }
            );
            $out .= LJ::help_icon_html('adult_content_reason');
            $out .= "</p>";
        }

        if ( $remote && !$altlogin ) {

            # crosspost
            my @accounts = DW::External::Account->get_external_accounts($remote);

            # populate the per-account html first, so that we only have to
            # go through them once.
            my $accthtml       = "";
            my $xpostbydefault = 0;
            my $xpost_tabindex = $tabindex->();
            my $did_spellcheck = $opts->{spellcheck_html} ? 1 : 0;
            if ( scalar @accounts ) {
                my $xpoststring    = $opts->{prop_xpost};
                my $xpost_selected = DW::External::Account->xpost_string_to_hash($xpoststring);
                foreach my $acct (@accounts) {

                    # print the checkbox for each account
                    my $acctid   = $acct->acctid;
                    my $acctname = $acct->displayname;
                    my $selected;
                    if ( $opts->{mode} eq 'edit' ) {
                        $selected = $xpost_selected->{ $acct->acctid } ? "1" : "0";
                    }
                    elsif ($did_spellcheck) {
                        $selected = $opts->{"prop_xpost_$acctid"};
                    }
                    else {
                        $selected = $acct->xpostbydefault;
                    }
                    $accthtml .=
"<tr><td><label for='prop_xpost_$acctid' class='left options'>$acctname</label></td>\n";
                    $accthtml .= "<td>"
                        . LJ::html_check(
                        {
                            'type'     => 'checkbox',
                            'name'     => "prop_xpost_$acctid",
                            'id'       => "prop_xpost_$acctid",
                            'class'    => 'check xpost_acct_checkbox',
                            'value'    => '1',
                            'selected' => $selected,
                            'tabindex' => $tabindex->(),
                            'onchange' => 'XPostAccount.xpostAcctUpdated();',
                        }
                        ) . "</td>\n";
                    $xpostbydefault = 1 if $selected;

                    $accthtml .= "<td>";
                    unless ( $acct->password ) {

                        # password field if no password
                        $accthtml .= "<span id='prop_xpost_pwspan_$acctid'>";
                        $accthtml .=
                              "<label for='prop_xpost_password_$acctid'>"
                            . BML::ml('xpost.password')
                            . "</label>";
                        $accthtml .= LJ::html_text(
                            {
                                'name'      => "prop_xpost_password_$acctid",
                                'id'        => "prop_xpost_password_$acctid",
                                'value'     => "",
                                'disabled'  => 0,
                                'size'      => 40,
                                'maxlength' => 80,
                                'type'      => 'password',
                                'class'     => 'xpost_pw'
                            }
                        );
                        $accthtml .=
                            "<span class='xpost_pwstatus' id='prop_xpost_pwstatus_$acctid'></span>";
                        $accthtml .=
"<input type='hidden' name='prop_xpost_chal_$acctid' id='prop_xpost_chal_$acctid' class='xpost_chal' />";
                        $accthtml .=
"<input type='hidden' name='prop_xpost_resp_$acctid' id='prop_xpost_resp_$acctid'/>";
                        $accthtml .= "</span>";
                    }
                    $accthtml .= "</td>\n";

                    $accthtml .= "</tr>\n";
                }
            }
            $out .= qq [
                    <script type="text/javascript" language="JavaScript">
                      // xpost messages
                      var xpostUser = '$remote->{user}';
                ];
            $out .= "var xpostCheckingMessage = '" . BML::ml('xpost.nopw.checking') . "';\n";
            $out .= "var xpostCancelLabel =  '" . BML::ml('xpost.nopw.cancel') . "';\n";
            $out .= "var xpostPwRequired = '" . BML::ml('xpost.nopw.required') . "';\n";
            $out .= "</script>\n";
            $out .= "<div id='xpostdiv'>\n";
            $out .=
                  "<p><label for='prop_xpost_check' class='left options'>"
                . BML::ml('entryform.xpost')
                . "</label>";
            $out .= LJ::html_check(
                {
                    'type'     => 'checkbox',
                    'name'     => 'prop_xpost_check',
                    'id'       => 'prop_xpost_check',
                    'class'    => 'check',
                    'value'    => '1',
                    'selected' => $xpostbydefault,
                    'disabled' => ( scalar @accounts ) ? '0' : '1',
                    'tabindex' => $xpost_tabindex,
                    'onchange' => 'XPostAccount.xpostButtonUpdated();',
                }
            );
            $out .= LJ::help_icon_html('prop_xpost_check');
            $out .= "<a href = '/manage/settings/?cat=othersites'>"
                . BML::ml('entryform.xpost.manage') . "</a>";
            $out .= "</p>\n<table summary=''>";
            $out .= $accthtml;
            $out .= "</table>\n";

            $out .= "</div>\n";
            $out .= qq [
              <p class='pkg'>
              <span class='inputgroup-left'></span>
                       ];
        }

        ### Other Posting Options
        $out .=
            LJ::Hooks::run_hook( 'add_extra_entryform_fields',
            { opts => $opts, tabindex => $tabindex } )
            || '';

        $out .= "<span class='inputgroup-right'>";

        # extra submit button so make sure it posts the form when person presses enter key
        if ( $opts->{'mode'} eq "edit" ) {
            $out .= "<input type='submit' name='action:save' class='hidden_submit xpost_submit' />";
        }
        if ( $opts->{'mode'} eq "update" ) {
            $out .=
                "<input type='submit' name='action:update' class='hidden_submit xpost_submit' />";
        }

        # submit_value field to emulate the submit button selected if we
        # have to submit with javascript
        $out .= "<input type='hidden' name='submit_value' />";

        my $preview;
        $preview =
              "<input type='button' value='"
            . BML::ml('entryform.preview')
            . "' onclick='entryPreview(this.form)' tabindex='"
            . $tabindex->() . "' />";
        if ( !$opts->{'disabled_save'} ) {
            $out .= <<PREVIEW;
<script type="text/javascript" language="JavaScript">
<!--
if (document.getElementById) {
    document.write("$preview ");
}
//-->
</script>
PREVIEW
        }
        if ( $LJ::SPELLER && !$opts->{'disabled_save'} ) {
            $out .= LJ::html_submit(
                'action:spellcheck',
                BML::ml('entryform.spellcheck'),
                { onclick => 'XPostAccount.doSpellcheck()', tabindex => $tabindex->() }
            ) . "&nbsp;";
        }

        # Update posting date/time
        $out .=
              "<input type='button' value='"
            . BML::ml('entryform.updatedate')
            . "' onclick='settime(\""
            . LJ::ejs( BML::ml('entryform.dateupdated') )
            . "\", this);' tabindex='"
            . $tabindex->() . "' />";
        $out .= "</span>\n";
        $out .= "</p>\n";
    }

    ### Community maintainer bar

    if ( $opts->{'maintainer_mode'} ) {
        $out .= "<p class='pkg'>\n";
        $out .= "<em>" . BML::ml('entryform.maintainer') . "</em>\n";
        $out .= "</p>\n";

        # adult content settings
        if ( LJ::is_enabled('adult_content') ) {
            $out .= "<p class='pkg'>\n";
            my %poster_adult_content_menu = (
                ""       => BML::ml('entryform.adultcontent.default'),
                none     => BML::ml('entryform.adultcontent.none'),
                concepts => BML::ml('entryform.adultcontent.concepts'),
                explicit => BML::ml('entryform.adultcontent.explicit'),
            );

            my @adult_content_menu = (
                "" => BML::ml(
                    'entryform.adultcontent.poster',
                    { setting => $poster_adult_content_menu{ $opts->{prop_adult_content} } }
                ),
                none     => BML::ml('entryform.adultcontent.none'),
                concepts => BML::ml('entryform.adultcontent.concepts'),
                explicit => BML::ml('entryform.adultcontent.explicit'),
            );

            $out .=
                  "<label for='prop_adult_content_maintainer' class='left options'>"
                . BML::ml('entryform.adultcontent.maintainer')
                . "</label>\n";
            $out .= LJ::html_select(
                {
                    name     => 'prop_adult_content_maintainer',
                    id       => 'prop_adult_content_maintainer',
                    class    => 'select',
                    selected => $opts->{prop_adult_content_maintainer} || "",
                    tabindex => $tabindex->(),
                },
                @adult_content_menu
            );
            $out .= LJ::help_icon_html( "adult_content", "", " " );
            $out .= "</p>\n";

            $out .= "<p class='pkg'>";
            $out .=
                  "<label for='prop_adult_content_maintainer_reason' class='left options'>"
                . BML::ml('entryform.adultcontentreason.maintainer')
                . "</label>";
            $out .= LJ::html_text(
                {
                    'name'      => 'prop_adult_content_maintainer_reason',
                    'id'        => 'prop_adult_content_maintainer_reason',
                    'class'     => 'text',
                    'size'      => '35',
                    'maxlength' => '255',
                    'value'     => $opts->{'prop_adult_content_maintainer_reason'},
                    'tabindex'  => $tabindex->(),
                }
            );
            $out .= LJ::help_icon_html('adult_content_reason');
            $out .= "</p>";
        }

        # comment disabling/enabling
        # only possible if comments weren't disabled by poster
        unless ( $opts->{prop_opt_nocomments} ) {
            $out .= "<p class='pkg'>";
            $out .=
                  "<label for='prop_opt_nocomments_maintainer' class='left options'>"
                . BML::ml('entryform.comment.disable')
                . "</label>";

            # comment disabling is done via a checkbox as it has only two settings
            # if we got this far, this is always set to the maintainer setting
            my $selected = $opts->{prop_opt_nocomments_maintainer};
            $out .= LJ::html_check(
                {
                    type     => 'checkbox',
                    name     => "prop_opt_nocomments_maintainer",
                    id       => "prop_opt_nocomments_maintainer",
                    class    => 'check',
                    value    => '1',
                    selected => $selected,
                    tabindex => $tabindex->(),
                }
            );
            $out .= "</p>";
        }
    }

    $out .= "</div><!-- end #options -->\n\n";

    ### Submit Bar
    {
        $out .= "<div id='submitbar' class='pkg'>\n\n";

        # Security
        my $secbar = 0;
        if ( $opts->{'mode'} eq "update" || !$opts->{'disabled_save'} ) {
            my $usejournalu = LJ::load_user( $opts->{usejournal} );
            my $is_comm     = $usejournalu && $usejournalu->is_comm ? 1 : 0;

            my $string_public       = LJ::ejs( BML::ml('label.security.public2') );
            my $string_friends      = LJ::ejs( BML::ml('label.security.accesslist') );
            my $string_friends_comm = LJ::ejs( BML::ml('label.security.members') );
            my $string_private      = LJ::ejs( BML::ml('label.security.private2') );
            my $string_admin        = LJ::ejs( BML::ml('label.security.maintainers') );
            my $string_custom       = LJ::ejs( BML::ml('label.security.custom') );

            $out .= qq{
                    <script>var UpdateFormStrings = new Object();
                    UpdateFormStrings.public = "$string_public";
                    UpdateFormStrings.friends = "$string_friends";
                    UpdateFormStrings.friends_comm = "$string_friends_comm";
                    UpdateFormStrings.private = "$string_private";
                    UpdateFormStrings.custom = "$string_custom";
                    UpdateFormStrings.admin = "$string_admin";</script>
                };

            $$onload .= " setColumns();" if $remote;
            my @secs = (
                "public", $string_public, "friends",
                $is_comm ? $string_friends_comm : $string_friends
            );
            push @secs, ( "private", $string_private ) unless $is_comm;
            push @secs, ( "private", $string_admin )
                if $is_comm && $remote && $remote->can_manage($usejournalu);

            my ( @secopts, @trust_groups );
            @trust_groups = $remote->trust_groups if $remote;
            if ( scalar @trust_groups && !$is_comm ) {
                push @secs, ( "custom", $string_custom );
                push @secopts, ( "onchange" => "customboxes()" );
            }

            if (@secs) {
                $secbar = 1;
                $out .= "<div id='security_container'>\n";
                $out .= "<label for='security'>" . BML::ml('entryform.security2') . " </label>\n";
            }

            $out .= LJ::html_select(
                {
                    'id'          => "security",
                    'name'        => 'security',
                    'include_ids' => 1,
                    'class'       => 'select',
                    'selected'    => $opts->{'security'},
                    'tabindex'    => $tabindex->(),
                    @secopts
                },
                @secs
            ) . "\n";

            # if custom security groups available, show them in a hideable div
            if ( scalar @trust_groups ) {
                my $display = $opts->{security} && $opts->{security} eq "custom" ? "block" : "none";
                $out .= LJ::help_icon( "security", "<span id='security-help'>\n", "\n</span>\n" );
                $out .= "<div id='custom_boxes' class='pkg' style='display: $display;'>\n";
                $out .= "<ul id='custom_boxes_list'>";
                foreach my $group (@trust_groups) {
                    my $fg = $group->{groupnum};
                    $out .= "<li>";
                    $out .= LJ::html_check(
                        {
                            'name'     => "custom_bit_$fg",
                            'id'       => "custom_bit_$fg",
                            'selected' => $opts->{"custom_bit_$fg"}
                                || ( $opts->{security_mask} ? $opts->{security_mask} + 0 : 0 ) &
                                1 << $fg
                        }
                    ) . " ";
                    $out .=
                          "<label for='custom_bit_$fg'>"
                        . LJ::ehtml( $group->{groupname} )
                        . "</label>\n";
                    $out .= "</li>";
                }
                $out .= "</ul>";
                $out .= "</div><!-- end #custom_boxes -->\n";
            }
        }

        if ( $opts->{'mode'} eq "update" ) {
            my $onclick = "";

            my $defaultjournal;
            my $not_a_journal = 0;
            if ( $opts->{'usejournal'} ) {
                $defaultjournal = $opts->{'usejournal'};
            }
            elsif ( $remote && $opts->{auth_as_remote} ) {
                $defaultjournal = $remote->user;
            }
            else {
                $defaultjournal = "Journal";
                $not_a_journal  = 1;
            }

            $$onload .= " changeSubmit('" . BML::ml('entryform.update3') . "', '$defaultjournal');";
            $$onload .= " getUserTags('$defaultjournal');" unless $not_a_journal;
            $$onload .= " changeSecurityOptions('$defaultjournal');" unless $opts->{'security'};

            $out .= LJ::html_submit(
                'action:update',
                BML::ml('entryform.update4'),
                {
                    'onclick'  => $onclick,
                    'class'    => 'update_submit xpost_submit',
                    'id'       => 'formsubmit',
                    'tabindex' => $tabindex->()
                }
            ) . "&nbsp;\n";
        }

        if ( $opts->{'mode'} eq "edit" ) {
            my $onclick = "";

            if ( !$opts->{'disabled_save'} ) {
                $out .= LJ::html_submit(
                    'action:save',
                    BML::ml('entryform.save'),
                    {
                        'onclick'  => $onclick,
                        'disabled' => $opts->{'disabled_save'},
                        'class'    => 'xpost_submit',
                        'tabindex' => $tabindex->()
                    }
                ) . "&nbsp;\n";
            }
            elsif ( $opts->{maintainer_mode} ) {
                $out .= LJ::html_submit(
                    'action:savemaintainer',
                    BML::ml('entryform.save.maintainer'),
                    {
                        'onclick'  => $onclick,
                        'disabled' => !$opts->{'maintainer_mode'},
                        'class'    => 'xpost_submit',
                        'tabindex' => $tabindex->()
                    }
                ) . "&nbsp;\n";
            }

            if ( !$opts->{'disabled_save'} && $opts->{suspended} && !$opts->{unsuspend_supportid} )
            {
                $out .= LJ::html_submit(
                    'action:saveunsuspend',
                    BML::ml('entryform.saveandrequestunsuspend2'),
                    {
                        'onclick'  => $onclick,
                        'disabled' => $opts->{'disabled_save'},
                        'class'    => 'xpost_submit',
                        'tabindex' => $tabindex->()
                    }
                ) . "&nbsp;\n";
            }

            # do a double-confirm on delete if we have crossposts that
            # would also get removed
            my $delete_onclick =
                  "return XPostAccount.confirmDelete('"
                . LJ::ejs( BML::ml('entryform.delete.confirm') ) . "', '"
                . LJ::ejs( BML::ml('entryform.delete.xposts.confirm') ) . "')";
            $out .= LJ::html_submit(
                'action:delete',
                BML::ml('entryform.delete'),
                {
                    'disabled' => $opts->{'disabled_delete'},
                    'class'    => 'xpost_submit',
                    'tabindex' => $tabindex->(),
                    'onclick'  => $delete_onclick
                }
            ) . "&nbsp;\n";

            if ( !$opts->{'disabled_spamdelete'} ) {
                $out .= LJ::html_submit(
                    'action:deletespam',
                    BML::ml('entryform.deletespam'),
                    {
                        'onclick' => "return confirm('"
                            . LJ::ejs( BML::ml('entryform.deletespam.confirm') ) . "')",
                        'class'    => 'xpost_submit',
                        'tabindex' => $tabindex->()
                    }
                ) . "\n";
            }
        }

        $out .= "</div><!-- end #security_container -->\n\n" if $secbar;
        $out .= "</div><!-- end #submitbar -->\n\n";
        $out .= "</div><!-- end #entry-form-wrapper -->\n\n";

        $out .= "<script  type='text/javascript'>\n";
        $out .= "// <![CDATA[ \n ";
        $out .= "init_update_bml() \n";
        $out .= "// ]]>\n";
        $out .= "</script>\n";
    }
    return $out;
}

# entry form subject
sub entry_form_subject_widget {
    my $class = $_[0];

    $class = $class ? qq { class="$class" } : '';

    return qq { <input name="subject" id="subject" $class/> };
}

# entry form hidden date field
sub entry_form_date_widget {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
    $year += 1900;
    $mon  = sprintf( "%02d", $mon + 1 );
    $mday = sprintf( "%02d", $mday );
    $min  = sprintf( "%02d", $min );
    return LJ::html_hidden(
        { 'name' => 'date_ymd_yyyy', 'value' => $year, 'id' => 'update_year' },
        { 'name' => 'date_ymd_dd',   'value' => $mday, 'id' => 'update_day' },
        { 'name' => 'date_ymd_mm',   'value' => $mon,  'id' => 'update_mon' },
        { 'name' => 'hour',          'value' => $hour, 'id' => 'update_hour' },
        { 'name' => 'min',           'value' => $min,  'id' => 'update_min' }
    );
}

# entry form event text box
sub entry_form_entry_widget {
    my $class = $_[0];

    $class = $class ? qq { class="$class" } : '';

    return qq { <textarea cols=50 rows=10 name="event" id="event" $class></textarea> };
}

sub minsec_for_user {
    my $user = LJ::load_user(shift);
    if ( !$user ) {
        return undef;
    }
    return $user->prop('newpost_minsecurity');
}

# entry form "journals can post to" dropdown
# NOTE!!! returns undef if no other journals user can post to
sub entry_form_postto_widget {
    my $remote = shift;

    return undef unless LJ::isu($remote);

    my $ret;

    # log in to get journals can post to
    my $res;
    $res = LJ::Protocol::do_request(
        "login",
        {
            "ver"      => $LJ::PROTOCOL_VER,
            "username" => $remote->{'user'},
        },
        undef,
        {
            "noauth" => 1,
            "u"      => $remote,
        }
    );

    return undef unless $res;

    LJ::need_res( { group => 'jquery' }, 'js/quickupdate.js' );

    my @journals = map {
        {
            value => $_,
            text  => $_,
            data  => { minsecurity => minsec_for_user($_), iscomm => 1 }
        }
    } @{ $res->{'usejournals'} };

    return undef unless @journals;

    my $journal_minsec = $remote && $remote->prop('newpost_minsecurity');
    push @journals,
        {
        value => $remote->{'user'},
        text  => $remote->{'user'},
        data  => { minsecurity => $journal_minsec, iscomm => 0 }
        };
    @journals = sort { $a->{'value'} cmp $b->{'value'} } @journals;
    $ret .= LJ::html_select(
        {
            name     => 'usejournal',
            id       => 'usejournal',
            selected => $remote->user
        },
        @journals
    ) . "\n";
    return $ret;
}

sub entry_form_security_widget {
    my $ret    = '';
    my $remote = LJ::get_remote();
    my $minsec = $remote && $remote->prop('newpost_minsecurity');

    # Don't disable options here: they may be valid to post to a community.
    # quickupdate.js will dynamically disable/enable options according to the
    # post-to dropdown, if JS is on.
    my @secs;
    push @secs,
        {
        value => 'public',
        text  => BML::ml('label.security.public2')
        };
    push @secs,
        {
        value => 'friends',
        text  => BML::ml('label.security.accesslist'),
        data  => { commlabel => BML::ml('label.security.members') }
        };
    push @secs,
        {
        value => 'private',
        text  => BML::ml('label.security.private2'),
        data  => { commlabel => BML::ml('label.security.maintainers') }
        };

    $ret .= LJ::html_select(
        {
            name     => 'security',
            id       => 'security',
            selected => $minsec
        },
        @secs
    );

    return $ret;
}

sub entry_form_tags_widget {
    my $ret = '';

    return '' unless LJ::is_enabled('tags');

    $ret .= LJ::html_text(
        {
            'name'      => 'prop_taglist',
            'id'        => 'prop_taglist',
            'size'      => '35',
            'maxlength' => '255',
        }
    );
    $ret .= LJ::help_icon('addtags');

    return $ret;
}

sub entry_form_usericon_widget {
    my $remote = shift;
    return undef unless LJ::isu($remote);

    my $ret = '';

    my %res;
    LJ::do_request(
        {
            mode      => "login",
            ver       => $LJ::PROTOCOL_VER,
            user      => $remote->user,
            getpickws => 1,
        },
        \%res,
        { noauth => 1, userid => $remote->userid }
    );

    if ( $res{pickw_count} ) {

        my @icons;
        for ( my $i = 1 ; $i <= $res{pickw_count} ; $i++ ) {
            push @icons, $res{"pickw_$i"};
        }

        @icons = sort { lc($a) cmp lc($b) } @icons;
        $ret .= LJ::html_select(
            {
                name => 'prop_picture_keyword',
                id   => 'prop_picture_keyword'
            },
            ( "", BML::ml('entryform.opt.defpic'), map { ( $_, $_ ) } @icons )
        );
    }
    return $ret;
}

sub entry_form_xpost_widget {
    my ($remote) = @_;
    return unless $remote;

    my $ret      = '';
    my @accounts = DW::External::Account->get_external_accounts($remote);
    @accounts = grep { $_->xpostbydefault } @accounts;

    if (@accounts) {
        $ret .= LJ::html_hidden(
            {
                name  => 'prop_xpost_check',
                id    => 'prop_xpost_check',
                value => 1,
            }
        );

        foreach my $acct (@accounts) {
            my $acctid = $acct->acctid;
            $ret .= LJ::html_hidden(
                {
                    name  => "prop_xpost_$acctid",
                    id    => "prop_xpost_$acctid",
                    value => 1,
                }
            );
        }
    }

    return $ret;
}

# <LJFUNC>
# name: LJ::entry_form_decode
# class: web
# des: Decodes an entry_form into a protocol-compatible hash.
# info: Generate form with [func[LJ::entry_form]].
# args: req, post
# des-req: protocol request hash to build.
# des-post: entry_form POST contents.
# returns: req
# </LJFUNC>
sub entry_form_decode {
    my ( $req, $POST ) = @_;

    # find security
    my $sec   = "public";
    my $amask = 0;
    if ( $POST->{'security'} eq "private" ) {
        $sec = "private";
    }
    elsif ( $POST->{'security'} eq "friends" ) {
        $sec   = "usemask";
        $amask = 1;
    }
    elsif ( $POST->{'security'} eq "custom" ) {
        $sec = "usemask";
        foreach my $bit ( 1 .. 60 ) {
            next unless $POST->{"custom_bit_$bit"};
            $amask |= ( 1 << $bit );
        }
    }
    $req->{'security'}  = $sec;
    $req->{'allowmask'} = $amask;

    # date/time
    my $date = LJ::html_datetime_decode( { 'name' => "date_ymd", }, $POST );
    my ( $year, $mon, $day ) = split( /\D/, $date );
    my ( $hour, $min ) = ( $POST->{'hour'}, $POST->{'min'} );

    # TEMP: ease golive by using older way of determining differences
    my $date_old = LJ::html_datetime_decode( { 'name' => "date_ymd_old", }, $POST );
    my ( $year_old, $mon_old, $day_old ) = split( /\D/, $date_old );
    my ( $hour_old, $min_old ) = ( $POST->{'hour_old'}, $POST->{'min_old'} );

    my $different = $POST->{'min_old'}
        && ( ( $year ne $year_old )
        || ( $mon ne $mon_old )
        || ( $day ne $day_old )
        || ( $hour ne $hour_old )
        || ( $min ne $min_old ) );

    # this value is set when the JS runs, which means that the user-provided
    # time is sync'd with their computer clock. otherwise, the JS didn't run,
    # so let's guess at their timezone.
    if ( $POST->{'date_diff'} || $POST->{'date_diff_nojs'} || $different ) {
        delete $req->{'tz'};
        $req->{'year'} = $year;
        $req->{'mon'}  = $mon;
        $req->{'day'}  = $day;
        $req->{'hour'} = $hour;
        $req->{'min'}  = $min;
    }

    # copy some things from %POST
    foreach (
        qw(subject
        prop_picture_keyword prop_current_moodid
        prop_current_mood prop_current_music
        prop_opt_screening prop_opt_noemail
        prop_opt_preformatted prop_opt_nocomments
        prop_current_location prop_current_coords
        prop_taglist )
        )
    {
        $req->{$_} = $POST->{$_};
    }

    if ( $POST->{"subject"} && ( $POST->{"subject"} eq BML::ml('entryform.subject.hint2') ) ) {
        $req->{"subject"} = "";
    }

    $req->{"prop_opt_preformatted"} ||=
          $POST->{'switched_rte_on'} ? 1
        : $POST->{event_format} && $POST->{event_format} eq "preformatted" ? 1
        :                                                                    0;
    $req->{"prop_opt_nocomments"} ||=
        $POST->{comment_settings} && $POST->{comment_settings} eq "nocomments" ? 1 : 0;
    $req->{"prop_opt_noemail"} ||=
        $POST->{comment_settings} && $POST->{comment_settings} eq "noemail" ? 1 : 0;
    $req->{'prop_opt_backdated'} = $POST->{'prop_opt_backdated'} ? 1 : 0;

    if ( LJ::is_enabled('adult_content') ) {
        $req->{prop_adult_content} = $POST->{prop_adult_content} || '';
        $req->{prop_adult_content} = ""
            unless $req->{prop_adult_content} eq "none"
            || $req->{prop_adult_content} eq "concepts"
            || $req->{prop_adult_content} eq "explicit";

        $req->{prop_adult_content_reason} = $POST->{prop_adult_content_reason} || "";
    }

    # nuke taglists that are just blank
    $req->{'prop_taglist'} = "" unless $req->{'prop_taglist'} && $req->{'prop_taglist'} =~ /\S/;

    # Convert the rich text editor output back to parsable lj tags.
    my $event = $POST->{'event'};
    if ( $POST->{'switched_rte_on'} ) {
        $req->{"prop_used_rte"} = 1;

        # We want to see if we can hit the fast path for cleaning
        # if they did nothing but add line breaks.
        my $attempt = $event;
        $attempt =~ s!<br />!\n!g;

        if ( $attempt !~ /<\w/ ) {
            $event = $attempt;

            # Make sure they actually typed something, and not just hit
            # enter a lot
            $attempt =~ s!(?:<p>(?:&nbsp;|\s)+</p>|&nbsp;)\s*?!!gm;
            $event = '' unless $attempt =~ /\S/;

            $req->{'prop_opt_preformatted'} = 0;
        }
        else {
            # Old methods, left in for compatibility during code push
            $event =~ s!<lj-cut class="ljcut">!<lj-cut>!gi;

            $event =~ s!<lj-raw class="ljraw">!<lj-raw>!gi;
        }
    }
    else {
        $req->{"prop_used_rte"} = 0;
    }

    $req->{'event'} = $event;

    ## see if an "other" mood they typed in has an equivalent moodid
    if ( $POST->{'prop_current_mood'} ) {
        if ( my $id = DW::Mood->mood_id( $POST->{'prop_current_mood'} ) ) {
            $req->{'prop_current_moodid'} = $id;
            delete $req->{'prop_current_mood'};
        }
    }

    # process site-specific options
    LJ::Hooks::run_hooks( 'decode_entry_form', $POST, $req );

    return $req;
}

# returns exactly what was passed to it normally.  but in developer mode,
# it includes a link to a page that automatically grants the needed priv.
sub no_access_error {
    my ( $text, $priv, $privarg ) = @_;
    if ($LJ::IS_DEV_SERVER) {
        my $remote = LJ::get_remote();
        return
"$text <b>(DEVMODE: <a href='/admin/priv/?devmode=1&user=$remote->{user}&priv=$priv&arg=$privarg'>Grant $priv\[$privarg\]</a>)</b>";
    }
    else {
        return $text;
    }
}

# Data::Dumper for JavaScript
# use this only when printing out on a page as a JS variable
# do not use for JSON requests -- it is not guaranteed to return
# valid JSON
sub js_dumper {
    my $obj = shift;
    if ( ref $obj eq "HASH" ) {
        my $ret = "{";
        foreach my $k ( keys %$obj ) {

            # numbers as keys need to be quoted.  and things like "null"
            my $kd = ( $k =~ /^\w+$/ ) ? "\"$k\"" : LJ::js_dumper($k);
            $ret .= "$kd: " . js_dumper( $obj->{$k} ) . ",\n";
        }
        if ( keys %$obj ) {
            chop $ret;
            chop $ret;
        }
        $ret .= "}";
        return $ret;
    }
    elsif ( ref $obj eq "ARRAY" ) {
        my $ret = "[" . join( ", ", map { js_dumper($_) } @$obj ) . "]";
        return $ret;
    }
    else {
        $obj = '' unless defined $obj;
        return $obj if $obj =~ /^\d+$/;
        return "\"" . LJ::ejs($obj) . "\"";
    }
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

        my $file  = LJ::resolve_file("htdocs/$key");
        my $mtime = defined $file ? ( stat($file) )[9] : undef;
        return $set->($mtime);
    }
}

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
        );

        my $site_params     = LJ::js_dumper( \%site );
        my $site_param_keys = LJ::js_dumper( [ keys %site ] );

        # include standard JS info
        $ret .= qq {
            <script type="text/javascript">
                var Site;
                if (!Site)
                    Site = {};

                var site_p = $site_params;
                var site_k = $site_param_keys;
                for (var i = 0; site_k.length > i; i++) {
                    Site[site_k[i]] = site_p[site_k[i]];
                }
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
        . BML::ml( 'web.controlstrip.links.create', { 'sitename' => $LJ::SITENAMESHORT } ) . "</a>";

    # Build up some common links
    my %links = (
        'login' =>
            "<a href='$LJ::SITEROOT/?returnto=$euri'>$BML::ML{'web.controlstrip.links.login'}</a>",
        'post_journal' =>
            "<a href='$LJ::SITEROOT/update'>$BML::ML{'web.controlstrip.links.post2'}</a>",
        'home' => "<a href='$LJ::SITEROOT/'>" . $BML::ML{'web.controlstrip.links.home'} . "</a>",
        'recent_comments' =>
"<a href='$LJ::SITEROOT/comments/recent'>$BML::ML{'web.controlstrip.links.recentcomments'}</a>",
        'manage_friends' =>
"<a href='$LJ::SITEROOT/manage/circle/'>$BML::ML{'web.controlstrip.links.managecircle'}</a>",
        'manage_entries' =>
"<a href='$LJ::SITEROOT/editjournal'>$BML::ML{'web.controlstrip.links.manageentries'}</a>",
        'invite_friends' =>
"<a href='$LJ::SITEROOT/manage/circle/invite'>$BML::ML{'web.controlstrip.links.invitefriends'}</a>",
        'create_account' => $create_link,
        'syndicated_list' =>
            "<a href='$LJ::SITEROOT/feeds/list'>$BML::ML{'web.controlstrip.links.popfeeds'}</a>",
        'learn_more' => LJ::Hooks::run_hook('control_strip_learnmore_link')
            || "<a href='$LJ::SITEROOT/'>$BML::ML{'web.controlstrip.links.learnmore'}</a>",
        'explore' => "<a href='$LJ::SITEROOT/explore/'>"
            . BML::ml( 'web.controlstrip.links.explore', { sitenameabbrev => $LJ::SITENAMEABBREV } )
            . "</a>",
        'confirm' =>
            "<a href='$LJ::SITEROOT/register'>$BML::ML{'web.controlstrip.links.confirm'}</a>",
    );

    if ($remote) {
        my $unread = $remote->notification_inbox->unread_count;
        $links{inbox} .= "<a href='$LJ::SITEROOT/inbox/'>$BML::ML{'web.controlstrip.links.inbox'}";
        $links{inbox} .= " ($unread)" if $unread;
        $links{inbox} .= "</a>";

        $links{settings} =
"<a href='$LJ::SITEROOT/manage/settings/'>$BML::ML{'web.controlstrip.links.settings'}</a>";
        $links{'view_friends_page'} =
              "<a href='"
            . $remote->journal_base
            . "/read'>$BML::ML{'web.controlstrip.links.viewreadingpage'}</a>";
        $links{'add_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$BML::ML{'web.controlstrip.links.addtocircle'}</a>";
        $links{'edit_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$BML::ML{'web.controlstrip.links.modifycircle'}</a>";
        $links{'track_user'} =
"<a href='$LJ::SITEROOT/manage/tracking/user?journal=$journal->{user}'>$BML::ML{'web.controlstrip.links.trackuser'}</a>";

        if ( $journal->is_syndicated ) {
            $links{'add_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=subscribe'>$BML::ML{'web.controlstrip.links.addfeed'}</a>";
            $links{'remove_friend'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=remove'>$BML::ML{'web.controlstrip.links.removefeed'}</a>";
        }
        if ( $journal->is_community ) {
            $links{'join_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$BML::ML{'web.controlstrip.links.joincomm'}</a>"
                unless $journal->is_closed_membership;
            $links{'leave_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$BML::ML{'web.controlstrip.links.leavecomm'}</a>";
            $links{'watch_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit?action=subscribe'>$BML::ML{'web.controlstrip.links.watchcomm'}</a>";
            $links{'unwatch_community'} =
"<a href='$LJ::SITEROOT/circle/$journal->{user}/edit'>$BML::ML{'web.controlstrip.links.removecomm'}</a>";
            $links{'post_to_community'} =
"<a href='$LJ::SITEROOT/update?usejournal=$journal->{user}'>$BML::ML{'web.controlstrip.links.postcomm'}</a>";
            $links{'edit_community_profile'} =
"<a href='$LJ::SITEROOT/manage/profile/?authas=$journal->{user}'>$BML::ML{'web.controlstrip.links.editcommprofile'}</a>";
            $links{'edit_community_invites'} =
                  "<a href='"
                . $journal->community_invite_members_url
                . "'>$BML::ML{'web.controlstrip.links.managecomminvites'}</a>";
            $links{'edit_community_members'} =
                  "<a href='"
                . $journal->community_manage_members_url
                . "'>$BML::ML{'web.controlstrip.links.editcommmembers'}</a>";
            $links{'track_community'} =
"<a href='$LJ::SITEROOT/manage/tracking/user?journal=$journal->{user}'>$BML::ML{'web.controlstrip.links.trackcomm'}</a>";
            $links{'queue'} =
                  "<a href='"
                . $journal->moderation_queue_url
                . "'>$BML::ML{'web.controlstrip.links.queue'}</a>";
        }
    }
    my $journal_display = $journal->ljuser_display;
    my %statustext      = (
        'yourjournal'            => $BML::ML{'web.controlstrip.status.yourjournal'},
        'yourfriendspage'        => $BML::ML{'web.controlstrip.status.yourreadingpage'},
        'yourfriendsfriendspage' => $BML::ML{'web.controlstrip.status.yournetworkpage'},
        'personal' => BML::ml( 'web.controlstrip.status.personal', { 'user' => $journal_display } ),
        'personalfriendspage' => BML::ml(
            'web.controlstrip.status.personalreadingpage', { 'user' => $journal_display }
        ),
        'personalfriendsfriendspage' => BML::ml(
            'web.controlstrip.status.personalnetworkpage', { 'user' => $journal_display }
        ),
        'community' =>
            BML::ml( 'web.controlstrip.status.community', { 'user' => $journal_display } ),
        'syn'   => BML::ml( 'web.controlstrip.status.syn',   { 'user' => $journal_display } ),
        'other' => BML::ml( 'web.controlstrip.status.other', { 'user' => $journal_display } ),
        'mutualtrust' =>
            BML::ml( 'web.controlstrip.status.mutualtrust', { 'user' => $journal_display } ),
        'mutualtrust_mutualwatch' => BML::ml(
            'web.controlstrip.status.mutualtrust_mutualwatch',
            { 'user' => $journal_display }
        ),
        'mutualtrust_watch' =>
            BML::ml( 'web.controlstrip.status.mutualtrust_watch', { 'user' => $journal_display } ),
        'mutualtrust_watchedby' => BML::ml(
            'web.controlstrip.status.mutualtrust_watchedby',
            { 'user' => $journal_display }
        ),
        'mutualwatch' =>
            BML::ml( 'web.controlstrip.status.mutualwatch', { 'user' => $journal_display } ),
        'trust_mutualwatch' =>
            BML::ml( 'web.controlstrip.status.trust_mutualwatch', { 'user' => $journal_display } ),
        'trust_watch' =>
            BML::ml( 'web.controlstrip.status.trust_watch', { 'user' => $journal_display } ),
        'trust_watchedby' =>
            BML::ml( 'web.controlstrip.status.trust_watchedby', { 'user' => $journal_display } ),
        'trustedby_mutualwatch' => BML::ml(
            'web.controlstrip.status.trustedby_mutualwatch',
            { 'user' => $journal_display }
        ),
        'trustedby_watch' =>
            BML::ml( 'web.controlstrip.status.trustedby_watch', { 'user' => $journal_display } ),
        'trustedby_watchedby' => BML::ml(
            'web.controlstrip.status.trustedby_watchedby', { 'user' => $journal_display }
        ),
        'maintainer' =>
            BML::ml( 'web.controlstrip.status.maintainer', { 'user' => $journal_display } ),
        'memberwatcher' =>
            BML::ml( 'web.controlstrip.status.memberwatcher', { 'user' => $journal_display } ),
        'watcher' => BML::ml( 'web.controlstrip.status.watcher', { 'user' => $journal_display } ),
        'member'  => BML::ml( 'web.controlstrip.status.member',  { 'user' => $journal_display } ),
        'trusted' => BML::ml( 'web.controlstrip.status.trusted', { 'user' => $journal_display } ),
        'watched' => BML::ml( 'web.controlstrip.status.watched', { 'user' => $journal_display } ),
        'trusted_by' =>
            BML::ml( 'web.controlstrip.status.trustedby', { 'user' => $journal_display } ),
        'watched_by' =>
            BML::ml( 'web.controlstrip.status.watchedby', { 'user' => $journal_display } ),
    );

    # Vars for controlstrip.tt
    my $template_args = {
        'view'         => $view,
        'userpic_html' => '',
        'logo_html'    => ( LJ::Hooks::run_hook( 'control_strip_logo', $remote, $journal ) || '' ),
        'show_login_form' => 0,
        'login_chal'      => '',
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
        if ($userpic) {
            my $wh = $userpic->img_fixedsize( width => 43, height => 43 );
            $template_args->{'userpic_html'} =
                  "<a href='$LJ::SITEROOT/manage/icons'><img src='"
                . $userpic->url
                . "' alt=\"$BML::ML{'web.controlstrip.userpic.alt'}\" title=\"$BML::ML{'web.controlstrip.userpic.title'}\" $wh /></a>";
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
"<a href='$LJ::SITEROOT/manage/icons'><img src='$tinted_nouserpic_img' alt=\"$BML::ML{'web.controlstrip.nouserpic.alt'}\" title=\"$BML::ML{'web.controlstrip.nouserpic.title'}\" height='43' width='43' /></a>";
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
                    "all",             $BML::ML{'web.controlstrip.select.friends.all'},
                    "showpeople",      $BML::ML{'web.controlstrip.select.friends.journals'},
                    "showcommunities", $BML::ML{'web.controlstrip.select.friends.communities'},
                    "showsyndicated",  $BML::ML{'web.controlstrip.select.friends.feeds'}
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

        if ($show_login_form) {
            $template_args->{'login_chal'} = LJ::challenge_generate(300);
        }

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

    my $catref                = delete $opts{'categories'};
    my $journalu              = delete $opts{'journal'} || LJ::get_remote();
    my $formauth              = delete $opts{'formauth'} || LJ::form_auth();
    my $showtracking          = delete $opts{'showtracking'} || 0;
    my $getextra              = delete $opts{'getextra'} || '';
    my $ret_url               = delete $opts{ret_url} || '';
    my $def_notes             = delete $opts{'default_selected_notifications'} || [];
    my $settings_page         = delete $opts{'settings_page'} || 0;
    my $post_to_settings_page = delete $opts{'post_to_settings_page'} || 0;
    my $num_per_page          = delete $opts{num_per_page} || 250;
    my $page                  = delete $opts{page} || 1;

    croak "Invalid user object passed to subscribe_interface" unless LJ::isu($journalu);

    croak "Invalid options passed to subscribe_interface" if ( scalar keys %opts );

    LJ::need_res('stc/esn.css');
    LJ::need_res('js/6alib/core.js');
    LJ::need_res('js/6alib/dom.js');
    LJ::need_res('js/6alib/checkallbutton.js');
    LJ::need_res('js/esn.js');

    my @categories = $catref ? @$catref : ();
    my $ui_inbox   = BML::ml('subscribe_interface.inbox');
    my $ui_manage  = BML::ml('subscribe_interface.manage_settings');
    my $ui_notify =
        BML::ml( 'subscribe_interface.notify_me2', { sitenameabbrev => $LJ::SITENAMEABBREV } );
    my $ui_by = BML::ml('subscribe_interface.by2');

    my $ret = "<div id='manageSettings'>";

    unless ($settings_page) {
        $ret .=
"<span class='esnlinks'><a href='$LJ::SITEROOT/inbox/'>$ui_inbox</a> | $ui_manage</span>";
    }

    if ($post_to_settings_page) {
        $ret .=
"<form method='POST' action='$LJ::SITEROOT/manage/settings/?cat=notifications'>$formauth";
    }
    elsif ( !$settings_page ) {
        $ret .= "<form method='POST' action='$LJ::SITEROOT/manage/tracking/$getextra'>$formauth";
    }

    my $events_table =
        $settings_page
        ? '<table class="Subscribe select-all" style="clear: none;" cellpadding="0" cellspacing="0">'
        : '<table class="Subscribe select-all" cellpadding="0" cellspacing="0">';

    my @notify_classes = LJ::NotificationMethod->all_classes or return "No notification methods";

    # skip the inbox type; it's always on
    @notify_classes = grep { $_ ne 'LJ::NotificationMethod::Inbox' } @notify_classes;

    my $tracking = [];

    # title of the tracking category
    my $tracking_cat = "Subscription Tracking";

    # if showtracking, add things the user is tracking to the categories
    if ($showtracking) {
        my @subscriptions = $u->find_subscriptions( method => 'Inbox' );

        foreach my $subsc ( sort { $a->id <=> $b->id } @subscriptions ) {

            # if this event class is already being displayed above, skip over it
            my $etypeid = $subsc->etypeid or next;
            my ($evt_class) = ( LJ::Event->class($etypeid) =~ /LJ::Event::(.+)/i );
            next unless $evt_class;

            # search for this class in categories
            next if grep { $_ eq $evt_class } map { @$_ } map { values %$_ } @categories;

            push @$tracking, $subsc;
        }
    }

    push @categories, { $tracking_cat => $tracking };

    my @catids;
    my $catid = 0;

    my %shown_subids = ();

# ( LJ::NotificationMethod::Inbox => {active => x, total => y }, LJ::NotificationMethod::Email => ...)
    my %num_subs_by_type = ();

    my $displayed_tracking_start = ( $page - 1 ) * $num_per_page;
    my $displayed_tracking_end   = $displayed_tracking_start + $num_per_page - 1;
    my $displayed_tracking_count = 0;

    foreach my $cat_hash (@categories) {
        my ( $category, $cat_events ) = %$cat_hash;

        push @catids, $catid;

        # pending subscription objects
        my $pending = [];

        my $cat_empty = 1;
        my $cat_html  = '';

        # is this category the tracking category?
        my $is_tracking_category = $category eq $tracking_cat;

        # build table of subscribeble events
        foreach my $cat_event (@$cat_events) {
            if ( ( ref $cat_event ) =~ /Subscription/ ) {
                push @$pending, $cat_event;
            }
            elsif ( $cat_event =~ /^LJ::Setting/ ) {

                # special subscription that's an LJ::Setting instead of an LJ::Subscription
                if ($settings_page) {
                    push @$pending, $cat_event;
                }
                else {
                    next;
                }
            }
            else {
                my $pending_sub = LJ::Subscription::Pending->new(
                    $u,
                    event   => $cat_event,
                    journal => $journalu
                );
                push @$pending, $pending_sub;
            }
        }

        my $cat_title_key = lc($category);
        $cat_title_key =~ s/ /-/g;
        my $cat_title   = BML::ml( 'subscribe_interface.category.' . $cat_title_key );
        my $first_class = $catid == 0 ? " CategoryRowFirst" : "";
        $cat_html .= qq {
            <div class="CategoryRow-$catid">
                <tr class="CategoryRow$first_class" id="category-$cat_title_key">
                <td>
                <span class="CategoryHeading">$cat_title</span><br />
                <span class="CategoryHeadingNote">$ui_notify</span>
                </td>
                <td class="Caption">
                $ui_by
                </td>
            };

        my @pending_subscriptions;

        # build list of subscriptions to show the user
        {
            unless ($is_tracking_category) {
                foreach my $pending_sub (@$pending) {
                    if ( !ref $pending_sub ) {
                        push @pending_subscriptions, $pending_sub;
                    }
                    else {
                        my %sub_args = $pending_sub->sub_info;
                        delete $sub_args{ntypeid};
                        $sub_args{method} = 'Inbox';

                        my @existing_subs = $u->has_subscription(%sub_args);
                        push @pending_subscriptions,
                            ( scalar @existing_subs ? @existing_subs : $pending_sub );
                    }
                }
            }
            else {
                push @pending_subscriptions, @$tracking;
            }
        }

        # add notifytype headings
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

            my $checkall_box = LJ::html_check(
                {
                    id                => "CheckAll-$catid-$ntypeid",
                    'data-select-all' => "$catid-$ntypeid",
                    label             => $title,
                    class             => "CheckAll",
                    noescape          => 1,
                    disabled          => $disabled,
                }
            );

            $cat_html .= qq {
                <td style='vertical-align: bottom;'>
                    $checkall_box
                    </td>
                };
        }

        $cat_html .= '</tr>';

        # inbox method
        my $special_subs     = 0;
        my $unavailable_subs = 0;
        my $sub_count        = 0;
        foreach my $pending_sub (@pending_subscriptions) {
            my $upgrade_notice = ( !$u->is_paid && $pending_sub->disabled($u) ) ? " &dagger;" : "";
            if ( !ref $pending_sub ) {
                next if $u->is_identity && $pending_sub->disabled($u);

                my $disabled_class = $pending_sub->disabled($u) ? "inactive" : "";
                my $altrow_class   = $sub_count % 2 == 1        ? "odd"      : "even";
                my $hidden    = $pending_sub->selected($u) ? "" : " style='visibility: hidden;'";
                my $sub_title = " " . $pending_sub->htmlcontrol_label($u);
                $sub_title = LJ::Hooks::run_hook( "disabled_esn_sub", $u ) . $sub_title
                    if $pending_sub->disabled($u);

                $cat_html .= "<tr class='$disabled_class $altrow_class'>";
                $cat_html .= "<td>" . $pending_sub->htmlcontrol($u) . "$sub_title*";
                $cat_html .= "$upgrade_notice";
                $cat_html .= "</td>";
                $cat_html .= "<td>&nbsp;</td>";
                foreach my $notify_class (@notify_classes) {
                    if ( $notify_class eq "LJ::NotificationMethod::Email" ) {
                        $cat_html .= "<td class='NotificationOptions'$hidden>"
                            . $pending_sub->htmlcontrol(
                            $u, undef, undef,
                            notif         => 1,
                            notif_catid   => $catid,
                            notif_ntypeid => 2
                            ) . "</td>";
                    }
                    else {
                        $cat_html .= "<td class='NotificationOptions'$hidden>"
                            . LJ::html_check( { disabled => 1 } ) . "</td>";
                    }
                }
                $cat_html .= "</tr>";

                $special_subs++;
                $sub_count++;
                next;
            }

            next if $u->is_identity && !$pending_sub->enabled;

            # print option to subscribe to this event, checked if already subscribed
            my $input_name = $pending_sub->freeze  or next;
            my $title      = $pending_sub->as_html or next;
            my $subscribed = !$pending_sub->pending;

            unless ( $pending_sub->enabled ) {
                my $hooktext = LJ::Hooks::run_hook( "disabled_esn_sub", $u ) // '';
                $title = $hooktext . $title . $upgrade_notice;
                $unavailable_subs++;
            }
            next if !$pending_sub->event_class->is_visible && $showtracking;

            my $evt_class = $pending_sub->event_class or next;
            unless ($is_tracking_category) {
                next unless eval { $evt_class->subscription_applicable($pending_sub) };
                next
                    if $u->equals($journalu)
                    && $pending_sub->journalid
                    && $pending_sub->journalid != $u->{userid};
            }
            else {
                my $no_show = 0;

                foreach my $cat_info_ref (@$catref) {
                    while ( my ( $_cat_name, $_cat_events ) = each %$cat_info_ref ) {
                        foreach my $_cat_event (@$_cat_events) {
                            next if $_cat_event =~ /^LJ::Setting/;
                            unless ( ref $_cat_event ) {
                                $_cat_event =
                                    LJ::Subscription::Pending->new( $u, event => $_cat_event );
                            }
                            next unless $pending_sub->equals($_cat_event);
                            $no_show = 1;
                            last;
                        }
                    }
                }

                next if $no_show;
            }

            my $special_selected = 0;

            my $selected = $special_selected || $pending_sub->default_selected;

            my $inactiveclass = $pending_sub->active  ? ''    : 'inactive';
            my $disabledclass = $pending_sub->enabled ? ''    : 'disabled';
            my $altrowclass   = $sub_count % 2 == 1   ? "odd" : "even";

            # it could be cleaner to do this by splicing pending_subs
            # but then you wouldn't be able to count how many active subs there are
            # one of the many ways in which ESN is painful
            my $do_show = 1;
            if ($is_tracking_category) {
                $do_show = 0
                    unless $displayed_tracking_count >= $displayed_tracking_start
                    && $displayed_tracking_count <= $displayed_tracking_end;
                $displayed_tracking_count++;
            }

            $cat_html .= "<tr class='$inactiveclass $disabledclass $altrowclass'><td>"
                if $do_show;

            if ( $do_show && $is_tracking_category && !$pending_sub->pending ) {
                my $subid      = $pending_sub->id;
                my $auth_token = $u->ajax_auth_token(
                    "/__rpc_esn_subs",
                    subid  => $subid,
                    action => 'delsub'
                );
                my $deletesub_url =
                    $settings_page
                    ? "$LJ::SITEROOT/manage/settings/?cat=notifications&deletesub_$subid=1"
                    : "?deletesub_$subid=1";
                $cat_html .=
"<a href='$deletesub_url' class='delete-button' subid=$subid auth_token=$auth_token>";
                $cat_html .= LJ::img( 'btn_trash', '' ) . "</a>\n";
            }
            my $always_checked = eval { "$evt_class"->always_checked; };
            my $disabled       = $always_checked ? 1 : !$pending_sub->enabled;

            if ($do_show) {
                $cat_html .= LJ::html_check(
                    {
                        id       => $input_name,
                        name     => $input_name,
                        class    => "SubscriptionInboxCheck",
                        selected => $selected,
                        noescape => 1,
                        label    => $title,
                        disabled => $disabled,
                    }
                ) . "</td>";

                unless ( $pending_sub->pending ) {
                    $cat_html .= LJ::html_hidden(
                        {
                            name  => "${input_name}-old",
                            value => $subscribed,
                        }
                    );
                }
                $shown_subids{ $pending_sub->id }++ unless $pending_sub->pending;
            }

        # for the inbox
        # "total" includes default subs (those at the top) which are active
        #   and any subs for tracking an entry/comment, whether active or inactive
        # "active" only counts subs which are selected
        # don't count disabled, even if they're checked, because they don't count against your limit
            if ( !$disabled && ( $is_tracking_category || $selected ) ) {
                $num_subs_by_type{"LJ::NotificationMethod::Inbox"}->{total}++;
                $num_subs_by_type{"LJ::NotificationMethod::Inbox"}->{active}++ if $selected;
            }

            $cat_empty = 0;

            # print out notification options for this subscription (hidden if not subscribed)
            $cat_html .= "<td>&nbsp;</td>" if $do_show;
            my $hidden =
                (      $special_selected
                    || $pending_sub->default_selected
                    || ( $subscribed && $pending_sub->active ) )
                ? ''
                : 'style="visibility: hidden;"';

            # is there an inbox notification for this?
            my %sub_args = $pending_sub->sub_info;
            $sub_args{ntypeid} = LJ::NotificationMethod::Inbox->ntypeid;
            delete $sub_args{flags};
            my ($inbox_sub) = $u->find_subscriptions(%sub_args);

            foreach my $note_class (@notify_classes) {
                my $ntypeid = eval { $note_class->ntypeid } or next;

                $sub_args{ntypeid} = $ntypeid;
                my @subs = $u->has_subscription(%sub_args);

                my $note_pending = LJ::Subscription::Pending->new( $u, %sub_args );
                if (@subs) {
                    $note_pending = $subs[0];
                }

                if ( ( $is_tracking_category || $pending_sub->is_tracking_category )
                    && $note_pending->pending )
                {
                    # flag this as a "tracking" subscription
                    $note_pending->set_tracking;
                }

                my $notify_input_name = $note_pending->freeze;

                # select email method by default
                my $note_selected =
                    ( scalar @subs )
                    ? 1
                    : ( ( !$selected || $special_selected )
                        && $note_class eq 'LJ::NotificationMethod::Email' );

                # check the box if it's marked as being selected by default UNLESS
                # there exists an inbox subscription and no email subscription
                $note_selected = 1
                    if ( !$inbox_sub || scalar @subs ) && $selected && grep { $note_class eq $_ }
                    @$def_notes;
                $note_selected &&= $note_pending->active && $note_pending->enabled;

                my $disabled = !$pending_sub->enabled;
                $disabled = 1 unless $note_class->configured_for_user($u);

                $cat_html .= qq {
                    <td class='NotificationOptions' $hidden>
                    }
                    . LJ::html_check(
                    {
                        id                 => $notify_input_name,
                        name               => $notify_input_name,
                        'data-selected-by' => "$catid-$ntypeid",
                        class              => "SubscribeCheckbox-$catid-$ntypeid",
                        selected           => $note_selected,
                        noescape           => 1,
                        disabled           => $disabled,
                    }
                    )
                    . '</td>'
                    if $do_show;

                unless ( $note_pending->pending ) {
                    $cat_html .= LJ::html_hidden(
                        {
                            name               => "${notify_input_name}-old",
                            value              => ( scalar @subs ) ? 1 : 0,
                            'data-selected-by' => "$catid-$ntypeid",
                        }
                    ) if $do_show;
                }

        # for other notification methods
        # "total" includes default subs (those at the top) which are active,
        #   and any subs for tracking an entry/comment, where the sub is active
        #   (because inbox is selected, revealing the notification checkbox)
        # "active" only counts subs which are selected
        # don't count disabled, even if they're checked, because they don't count against your limit
                if ( !$disabled && !$hidden && ( $is_tracking_category || $note_selected ) ) {
                    $num_subs_by_type{$note_class}->{total}++;
                    $num_subs_by_type{$note_class}->{active}++ if $note_selected;
                }

            }

            $cat_html .= "</tr>" if $do_show;
            $sub_count++;
        }

        my $cols = 2 + ( scalar @notify_classes );

        # show blurb if not tracking anything
        if ( $cat_empty && $is_tracking_category ) {
            my $blurb =
                  "<?p <strong>"
                . LJ::Lang::ml('subscribe_interface.nosubs.title2')
                . "</strong><br />";
            $blurb .= LJ::Lang::ml(
                'subscribe_interface.nosubs.text',
                {
                    img => LJ::img(
                        'track', '',
                        {
                            align => 'absmiddle',
                            alt   => $ui_notify
                        }
                    )
                }
            ) . " p?>";

            $cat_html .= "<td colspan='$cols'>$blurb</td>";
        }

        $cat_html .= "</tr>";
        $cat_html .= "<tr><td colspan='$cols' style='font-size: smaller;'>* "
            . LJ::Lang::ml( 'subscribe_interface.special_subs.note',
            { sitenameabbrev => $LJ::SITENAMEABBREV } )
            . "</td></tr>"
            if $special_subs;
        $cat_html .=
              "<tr><td colspan='$cols' style='font-size: smaller;'>&dagger; "
            . LJ::Lang::ml('subscribe_interface.unavailable_subs.note')
            . "</td></tr>"
            if !$u->is_paid && ( $special_subs || $unavailable_subs );
        $cat_html     .= "</div>";
        $events_table .= $cat_html unless ( $is_tracking_category && !$showtracking );

        $catid++;
    }

    $events_table .= '</table>';

    my $pagination = "";
    $pagination = LJ::paging_bar(
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
    ) if $settings_page;

    # pass some info to javascript
    my $catids = LJ::html_hidden(
        {
            'id'    => 'catids',
            'value' => join( ',', @catids ),
        }
    );
    my $ntypeids = LJ::html_hidden(
        {
            'id'    => 'ntypeids',
            'value' => join( ',', map { $_->ntypeid } LJ::NotificationMethod->all_classes ),
        }
    );

    my $subscription_stats = "";
    if ($settings_page) {

        # show how many subscriptions we have active / inactive
        # there's a bit of a trick here: each row counts as a maximum of one subscription.
        # However, forced subscriptions don't count (e.g., "Someone sends me a message" for inbox)
        # Also, if we activate an inbox subscription but not its email, the total number of subs
        # per notification method goes out of sync.
        # Regardless, once we hit the limit for *any* method, we get a warning. So we take
        # whichever method has the most total / active and use that figure in our message.

        my $max_active_method = 0;
        my $max_total_method  = 0;

        foreach my $method_class ( keys %num_subs_by_type ) {
            $max_active_method = $num_subs_by_type{$method_class}->{active}
                if $num_subs_by_type{$method_class}->{active} > $max_active_method;
            $max_total_method = $num_subs_by_type{$method_class}->{total}
                if $num_subs_by_type{$method_class}->{total} > $max_total_method;
        }

        my $paid_max = LJ::get_cap( 'paid', 'subscriptions' );
        my $u_max    = $u->max_subscriptions;

        # max for total number of subscriptions (generally it is $paid_max)
        my $system_max = $u_max > $paid_max ? $u_max : $paid_max;

        $subscription_stats .= "<div class='subscription_stats'>"
            . LJ::Lang::ml(
            'subscribe_interface.subs.total2',
            {
                active     => $max_active_method,
                max_active => $u_max,
                total      => $max_total_method,
                max_total  => $system_max,
            }
            ) . "</div>";
    }

    $ret .= qq {
        $ntypeids
            $catids
            $events_table
            $pagination
            $subscription_stats
        };

    $ret .= LJ::html_hidden( { name => 'mode',                  value => 'save_subscriptions' } );
    $ret .= LJ::html_hidden( { name => 'ret_url',               value => $ret_url } );
    $ret .= LJ::html_hidden( { name => 'post_to_settings_page', value => $post_to_settings_page } );

    # print buttons
    my $referer = BML::get_client_header('Referer') || '';
    my $uri     = $LJ::SITEROOT . DW::Request->get->uri;

    # normalize the URLs -- ../index.bml doesn't make it a different page.
    $uri     =~ s/index\.bml//;
    $referer =~ s/index\.bml//;

    unless ($settings_page) {
        $ret .=
              '<div class="action-box"><ul class="inner nostyle">' . "<li>"
            . LJ::html_submit( BML::ml('subscribe_interface.save') ) . '</li>'
            . (
            $referer && $referer ne $uri
            ? "<li><input type='button' value='"
                . BML::ml('subscribe_interface.cancel')
                . "' onclick='window.location=\"$referer\"' /></li>"
            : ''
            );
        $ret .= "</div><div class='clear-floats'></div>";
    }

    $ret .= "</div>";
    $ret .= "</form>" if !$settings_page || $post_to_settings_page;

    return $ret;
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
    my $lang = eval { BML::get_language() };
    return 80  if !$lang || $lang =~ /^en/;
    return 100 if $lang =~ /\b(hy|az|be|et|ka|ky|kk|lt|lv|mo|ru|tg|tk|uk|uz)\b/i;
    return 80;
}

# Common challenge/response JavaScript, needed by both login pages and comment pages alike.
# Forms that use this should onclick='return sendForm()' in the submit button.
# Returns true to let the submit continue.
$LJ::COMMON_CODE{'chalresp_js'} = qq{
<script type="text/javascript" src="$LJ::JSPREFIX/md5.js"></script>
<script language="JavaScript" type="text/javascript">
    <!--
function sendForm (formid, checkuser)
{
    if (formid == null) formid = 'login';
    // 'checkuser' is the element id name of the username textfield.
    // only use it if you care to verify a username exists before hashing.

    if (! document.getElementById) return true;
    var loginform = document.getElementById(formid);
    if (! loginform) return true;

    // Avoid accessing the password field if there is no username.
    // This works around Opera < 7 complaints when commenting.
    if (checkuser) {
        var username = null;
        for (var i = 0; username == null && i < loginform.elements.length; i++) {
            if (loginform.elements[i].id == checkuser) username = loginform.elements[i];
        }
        if (username != null && username.value == "") return true;
    }

    if (! loginform.password || ! loginform.login_chal || ! loginform.login_response) return true;
    var pass = loginform.password.value;
    var chal = loginform.login_chal.value;
    var res = MD5(chal + MD5(pass));
    loginform.login_response.value = res;
    loginform.password.value = "";  // dont send clear-text password!
    return true;
}
// -->
</script>
};

# Common JavaScript function for auto-checking radio buttons on form
# input field data changes
$LJ::COMMON_CODE{'autoradio_check'} = q{
<script language="JavaScript" type="text/javascript">
    <!--
    /* If radioid exists, check the radio button. */
    function checkRadioButton(radioid) {
        if (!document.getElementById) return;
        var radio = document.getElementById(radioid);
        if (!radio) return;
        radio.checked = true;
    }
// -->
</script>
};

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

# sets up appropriate js for journals that need a special statusvis message at the top
# returns some js that must be added onto the journal page's head
sub statusvis_message_js {
    my $u = shift;

    return "" unless $u;

    return "" unless $u->is_locked || $u->is_memorial || $u->is_readonly;

    my $statusvis_full;
    $statusvis_full = "locked"   if $u->is_locked;
    $statusvis_full = "memorial" if $u->is_memorial;
    $statusvis_full = "readonly" if $u->is_readonly;

    LJ::need_res("js/statusvis_message.js");
    return
          "<script>Site.StatusvisMessage=\""
        . LJ::Lang::ml("statusvis_message.$statusvis_full")
        . "\";</script>";
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
