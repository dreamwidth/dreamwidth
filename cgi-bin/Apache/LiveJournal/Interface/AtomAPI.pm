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
# AtomAPI support for LJ

package Apache::LiveJournal::Interface::AtomAPI;

use strict;
use Apache2::Const qw(:common);
use Digest::SHA1;
use MIME::Base64;
use lib "$LJ::HOME/cgi-bin";
use LJ::ModuleCheck;
use LJ::ParseFeed;

# for Class::Autouse (so callers can 'ping' this method to lazy-load this class)
sub load { 1 }

# check allowed Atom upload filetypes
sub check_mime
{
    my $mime = shift;
    return unless $mime;

    # TODO: add audio/etc support
    my %allowed_mime = (
        image => qr{^image\/(?:gif|jpe?g|png|tiff?)$}i,
        #audio => qr{^(?:application|audio)\/(?:(?:x-)?ogg|wav)$}i
    );

    foreach (keys %allowed_mime) {
        return $_ if $mime =~ $allowed_mime{$_}
    }
    return;
}

sub respond {
    my ($r, $status, $body, $type) = @_;

    my %msgs = (
        200 => 'OK',
        201 => 'Created',

        400 => 'Bad Request',
        401 => 'Authentication Failed',
        403 => 'Forbidden',
        404 => 'Not Found',
        500 => 'Server Error',
    ),

    my %mime = (
        html => 'text/html',
        atom => 'application/x.atom+xml',
        xml  => "text/xml; charset='utf-8'",
    );

    # if the passed in body was a reference, send it
    # without any modification.  otherwise, send some
    # prettier html to the client.
    my $out;
    if (ref $body) {
        $out = $$body;
    } else {
        $out = <<HTML;
<html><head><title>$status $msgs{$status}</title></head><body>
<h1>$msgs{$status}</h1><hr /><p>$body</p>
</body></html>
HTML
    }

    $type = $mime{$type} || 'text/html';
    $r->status_line("$status $msgs{$status}");
    $r->content_type($type);
    $r->print($out);
    return OK;
};

sub handle_upload
{
    my ($r, $remote, $u, $opts, $entry) = @_;

    # entry could already be populated from a standalone
    # service.post posting.
    my $standalone = $entry ? 1 : 0;
    unless ($entry) {
        my $buff;

        # Check length
        my $len = $r->header_in("Content-length");
        return respond($r, 400, "Content is too long")
            if $len > $LJ::MAX_ATOM_UPLOAD;

        $r->read($buff, $len);

        eval { $entry = XML::Atom::Entry->new( \$buff ); };
        return respond($r, 400, "Could not parse the entry due to invalid markup.<br /><pre>$@</pre>")
            if $@;
    }

    my $mime = $entry->content()->type();
    my $mime_area = check_mime( $mime );
    return respond($r, 400, "Unsupported MIME type: $mime") unless $mime_area;

    if ($mime_area eq 'image') {
        return respond( $r, 400, "Unable to upload media." );
    }
}

sub handle_post {
    my ($r, $remote, $u, $opts) = @_;
    my ($buff, $entry);

    # Check length
    my $len = $r->header_in("Content-length");
    return respond($r, 400, "Content is too long")
        if $len > $LJ::MAX_ATOM_UPLOAD;

    # read the content
    $r->read($buff, $len);

    # try parsing it
    eval { $entry = XML::Atom::Entry->new( \$buff ); };
    return respond($r, 400, "Could not parse the entry due to invalid markup.<br /><pre>$@</pre>")
        if $@;

    # on post, the entry must NOT include an id
    return respond($r, 400, "Must not include an <b>&lt;id&gt;</b> field in a new entry.")
        if $entry->id;

    # detect 'standalone' media posts
    return handle_upload( @_, $entry )
        if $entry->get("http://sixapart.com/atom/typepad#", 'standalone');

    # remove the SvUTF8 flag. See same code in synsuck.pl for
    # an explanation
    $entry->title(   LJ::no_utf8_flag( $entry->title         ));
    $entry->link(    LJ::no_utf8_flag( $entry->link          ));
    $entry->content( LJ::no_utf8_flag( $entry->content->body ));

    my @tags;

    eval {
        my @subjects = $entry->getlist('http://purl.org/dc/elements/1.1/', 'subject');
        push @tags, @subjects;
    };
    warn "Subjects parsing from ATOM died: $@" if $@;

    eval {
        my @categories = $entry->categories;
        push @tags, map { $_->label || $_->term } @categories;
    };
    warn "Categories parsing from ATOM died: $@" if $@;

    my $security_opts = { security => 'public' };

    # TODO Add code for handling this with XML::Atom::ext
    if ($XML::Atom::Version <= .13) {
        eval {
            foreach my $allow_element (map { XML::Atom::Util::nodelist($_, 'http://www.sixapart.com/ns/atom/privacy', 'allow') }
                                             XML::Atom::Util::nodelist($entry->{doc}, 'http://www.sixapart.com/ns/atom/privacy', 'privacy')) {

                my $policy = $allow_element->getAttribute('policy');
                next unless $policy eq 'http://www.sixapart.com/ns/atom/permissions#read';

                my $ref = $allow_element->getAttribute('ref');

                if ($ref =~ m/#(everyone|friends|self)$/) {
                    $security_opts = {
                        everyone => {
                            security => 'public',
                        },
                        friends  => {
                            security => 'usemask',
                            allowmask => 1,
                        },
                        self     => {
                            security => 'private',
                        },
                    }->{$1};
                }
            }
        };

        if ($@) {
            warn "While parsing privacy handling on AtomAPI call: $@\n";
        }
    }

    my $preformatted = $entry->get
        ("http://sixapart.com/atom/post#", "convertLineBreaks") eq 'false' ? 1 : 0;

    # build a post event request.
    my $req = {
        'usejournal'  => ( $remote->{'userid'} != $u->{'userid'} ) ? $u->{'user'} : undef,
        'ver'         => 1,
        'username'    => $u->{'user'},
        'lineendings' => 'unix',
        'subject'     => $entry->title(),
        'event'       => $entry->content()->body(),
        'props'       => { opt_preformatted => $preformatted, taglist => \@tags },
        'tz'          => 'guess',
        %$security_opts,
    };

    $req->{'props'}->{'interface'} = "atom";

    my $err;
    my $res = LJ::Protocol::do_request("postevent",
                                       $req, \$err, { 'noauth' => 1 });

    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return respond($r, 500, "Unable to post new entry. Protocol error: <b>$errstr</b>.");
    }

    my $atom_reply = XML::Atom::Entry->new();
    $atom_reply->title( $entry->title );

    my $content_body = $entry->content->body;
    $atom_reply->summary( substr( $content_body, 0, 100 ) );
    $atom_reply->content( $content_body );

    my $lj_entry = LJ::Entry->new($u, jitemid => $res->{itemid});
    $atom_reply->id( $lj_entry->atom_id );

    my $link;
    my $edit_url = "$LJ::SITEROOT/interface/atom/edit/$res->{'itemid'}";

    my $add_category = sub {
        my $category = XML::Atom::Category->new;
        $category->term(shift);
        $atom_reply->add_category($category);
    };

    # Old versions of XML::Atom don't have a category object, do it manually
    if ($XML::Atom::VERSION <= .21) {
        $add_category = sub {
            my $term = shift;
            $atom_reply->category(undef, { term => $term });
        };
    }

    foreach my $tag (@tags) {
        local $@;
        eval { $add_category->($tag) };
        warn "Unable to add category to XML::Atom feed: $@"
            if $@;
    }

    $link = XML::Atom::Link->new();
    $link->type('application/x.atom+xml');
    $link->rel('service.edit');
    $link->href( $edit_url );
    $link->title( $entry->title() );
    $atom_reply->add_link($link);

    $link = XML::Atom::Link->new();
    $link->type('text/html');
    $link->rel('alternate');
    $link->href( $res->{url} );
    $link->title( $entry->title() );
    $atom_reply->add_link($link);

    $r->header_out("Location", $edit_url);
    return respond($r, 201, \$atom_reply->as_xml(), 'atom');
}

sub handle_edit {
    my ($r, $remote, $u, $opts) = @_;

    my $method = $opts->{'method'};

    # first, try to load the item and fail if it's not there
    my $jitemid = $opts->{'param'};
    my $req = {
        'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
            $u->{'user'} : undef,
         'ver' => 1,
         'username' => $u->{'user'},
         'selecttype' => 'one',
         'itemid' => $jitemid,
    };

    my $err;
    my $olditem = LJ::Protocol::do_request("getevents",
                                           $req, \$err, { 'noauth' => 1 });

    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return respond($r, 404, "Unable to retrieve the item requested for editing. Protocol error: <b>$errstr</b>.");
    }
    $olditem = $olditem->{'events'}->[0];

    if ($method eq "GET") {
        # return an AtomEntry for this item
        # use the interface between make_feed and create_view_atom in
        # ljfeed.pl

        # get the log2 row (need logtime for createtime)
        my $row = LJ::get_log2_row($u, $jitemid) ||
            return respond($r, 404, "Could not load the original entry.");

        # we need to put into $item: itemid, ditemid, subject, event,
        # createtime, eventtime, modtime

        my $ctime = LJ::mysqldate_to_time($row->{'logtime'}, 1);

        my $tagstring = $olditem->{'props'}->{'taglist'} || '';
        my $tags = [ split(/\s*,\s*/, $tagstring) ];

        my $item = {
            'itemid'     => $olditem->{'itemid'},
            'ditemid'    => $olditem->{'itemid'}*256 + $olditem->{'anum'},
            'eventtime'  => LJ::alldatepart_s2($row->{'eventtime'}),
            'createtime' => $ctime,
            'modtime'    => $olditem->{'props'}->{'revtime'} || $ctime,
            'subject'    => $olditem->{'subject'},
            'event'      => $olditem->{'event'},
            'tags'       => $tags,
        };

        my $ret = LJ::Feed::create_view_atom(
            { 'u' => $u },
            $u,
            {
                'single_entry' => 1,
                'apilinks'     => 1,
            },
            [$item]
        );

        return respond($r, 200, \$ret, 'xml');
    }

    if ($method eq "PUT") {
        # Check length
        my $len = $r->header_in("Content-length");
        return respond($r, 400, "Content is too long")
            if $len > $LJ::MAX_ATOM_UPLOAD;

        # read the content
        my $buff;
        $r->read($buff, $len);

        # try parsing it
        my $entry;
        eval { $entry = XML::Atom::Entry->new( \$buff ); };
        return respond($r, 400, "Could not parse the entry due to invalid markup.<br /><pre>$@</pre>")
            if $@;

        # remove the SvUTF8 flag. See same code in synsuck.pl for
        # an explanation
        $entry->title(   LJ::no_utf8_flag( $entry->title         ));
        $entry->link(    LJ::no_utf8_flag( $entry->link          ));
        $entry->content( LJ::no_utf8_flag( $entry->content->body ));

        # the AtomEntry must include <id> which must match the one we sent
        # on GET
        unless ($entry->id =~ m#,\d{4}-\d{2}-\d{2}:$u->{userid}:(\d+)$# &&
                $1 == $olditem->{'itemid'}*256 + $olditem->{'anum'}) {
            return respond($r, 400, "Incorrect <b>&lt;id&gt;</b> field in this request.");
        }

        # build an edit event request. Preserve fields that aren't being
        # changed by this item (perhaps the AtomEntry isn't carrying the
        # complete information).

        $req = {
            'usejournal'  => ( $remote->{'userid'} != $u->{'userid'} ) ? $u->{'user'} : undef,
            'ver'         => 1,
            'username'    => $u->{'user'},
            'itemid'      => $jitemid,
            'lineendings' => 'unix',
            'subject'     => $entry->title() || $olditem->{'subject'},
            'event'       => $entry->content()->body() || $olditem->{'event'},
            'props'       => $olditem->{'props'},
            'security'    => $olditem->{'security'},
            'allowmask'   => $olditem->{'allowmask'},
        };

        $err = undef;
        my $res = LJ::Protocol::do_request("editevent",
                                           $req, \$err, { 'noauth' => 1 });

        if ($err) {
            my $errstr = LJ::Protocol::error_message($err);
            return respond($r, 500, "Unable to update entry. Protocol error: <b>$errstr</b>.");
        }

        return respond($r, 200, "The entry was successfully updated.");
    }

    if ($method eq "DELETE") {

        # build an edit event request to delete the entry.

        $req = {
            'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
                $u->{'user'}:undef,
            'ver' => 1,
            'username' => $u->{'user'},
            'itemid' => $jitemid,
            'lineendings' => 'unix',
            'event' => '',
        };

        $err = undef;
        my $res = LJ::Protocol::do_request("editevent",
                                           $req, \$err, { 'noauth' => 1 });

        if ($err) {
            my $errstr = LJ::Protocol::error_message($err);
            return respond($r, 500, "Unable to delete entry. Protocol error: <b>$errstr</b>.");
        }

        return respond($r, 200, "Entry successfully deleted.");
    }

}

# fetch lj tags, display as categories
sub handle_categories
{
    my ($r, $remote, $u, $opts) = @_;
    my $ret = '<?xml version="1.0"?>';
    $ret .= '<categories xmlns="http://sixapart.com/atom/category#">';

    my $tags = LJ::Tags::get_usertags($u, { remote => $remote }) || {};
    foreach (sort { $a->{name} cmp $b->{name} } values %$tags) {
        $ret .= "<subject xmlns=\"http://purl.org/dc/elements/1.1/\">$_->{name}</subject>";
    }
    $ret .= '</categories>';

    return respond($r, 200, \$ret, 'xml');
}

sub handle_feed {
    my ($r, $remote, $u, $opts) = @_;

    # simulate a call to the S1 data view creator, with appropriate
    # options

    my %op = ('pathextra' => "/atom",
              'apilinks'  => 1,
              );
    my $ret = LJ::Feed::make_feed($r, $u, $remote, \%op);

    unless (defined $ret) {
        if ($op{'redir'}) {
            # this happens if the account was renamed or a syn account.
            # the redir URL is wrong because ljfeed.pl is too
            # dataview-specific. Since this is an admin interface, we can
            # just fail.
            return respond ($r, 404, "The account <b>$u->{'user'} </b> is of a wrong type and does not allow AtomAPI administration.");
        }
        if ($op{'handler_return'}) {
            # this could be a conditional GET shortcut, honor it
            $r->status($op{'handler_return'});
            return OK;
        }
        # should never get here
        return respond ($r, 404, "Unknown error.");
    }

    # everything's fine, return the XML body with the correct content type
    return respond($r, 200, \$ret, 'xml');

}

# this routine accepts the apache request handle, performs
# authentication, calls the appropriate method handler, and
# prints the response.
sub handle {
    # FIXME: Move this up to caller(s).
    my $r = DW::Request->get;

    return respond($r, 404, "This server does not support the Atom API.")
        unless LJ::ModuleCheck->have_xmlatom;

    # break the uri down: /interface/atom/<verb>[/<number>]
    # or old format:      /interface/atomapi/<username>/<verb>[/<number>]
    my $uri = $r->uri;

    # convert old format to new format:
    my $username;   # old
    if ($uri =~ s!^/interface/atomapi/(\w+)/!/interface/atom/!) {
        $username = $1;
    }

    $uri =~ s!^/interface/atom/?!! or return respond($r, 404, "Bogus URL");
    my ($action, $param) = split(m!/!, $uri);

    my $valid_actions = qr{feed|edit|post|upload|categories};

    # let's authenticate.
    #
    # if wsse information is supplied, use it.
    # if not, fall back to digest.
    my $wsse = $r->header_in('X-WSSE');
    my $nonce_dup;
    my $u = $wsse ? auth_wsse($wsse, \$nonce_dup) : LJ::auth_digest($r);
    return respond( $r, 401, "Authentication failed for this AtomAPI request.")
        unless $u;

    return respond( $r, 401, "Authentication failed for this AtomAPI request.")
        if $nonce_dup && $action && $action ne 'post';

    # service autodiscovery
    # TODO: Add communities?
    my $method = $r->method;
    if ( $method eq 'GET' && ! $action ) {
        my $title = $u->prop( 'journaltitle' ) || $u->user;
        my $feed = XML::Atom::Feed->new();

        my $add_link = sub {
            my $subservice = shift;
            my $link = XML::Atom::Link->new();
            $link->title($title);
            $link->type('application/x.atom+xml');
            $link->rel("service.$subservice");
            $link->href("$LJ::SITEROOT/interface/atom/$subservice");
            $feed->add_link($link);
        };

        foreach my $subservice (qw/ post edit feed categories /) {
            $add_link->($subservice);
        }

        my $link = XML::Atom::Link->new();
        $link->title($title);
        $link->type('text/html');
        $link->rel('alternate');
        $link->href( $u->journal_base );
        $feed->add_link($link);

        return respond($r, 200, \$feed->as_xml(), 'atom');
    }

    $action =~ /^$valid_actions$/
      or return respond($r, 400, "Unknown URI scheme: /interface/atom/<b>" . LJ::ehtml($action) . "</b>");

    unless (($action eq 'feed' and $method eq 'GET')  or
            ($action eq 'categories' and $method eq 'GET') or
            ($action eq 'post' and $method eq 'POST') or
            ($action eq 'upload' and $method eq 'POST') or
            ($action eq 'edit' and
             {'GET'=>1,'PUT'=>1,'DELETE'=>1}->{$method})) {
        return respond($r, 400, "URI scheme /interface/atom/<b>" . LJ::ehtml($action) . "</b> is incompatible with request method <b>$method</b>.");
    }

    if (($action ne 'edit' && $param) or
        ($action eq 'edit' && $param !~ m#^\d+$#)) {
        return respond($r, 400, "Either the URI lacks a required parameter, or its format is improper.");
    }

    # we've authenticated successfully and remote is set. But can remote
    # manage the requested account?
    my $remote = LJ::get_remote();
    unless ( $remote && $remote->can_manage( $u ) ) {
        return respond( $r, 403, "User <b>$remote->{user}</b> has no administrative access to account <b>$u->{user}</b>." );
    }

    # handle the requested action
    my $opts = {
        'action' => $action,
        'method' => $method,
        'param'  => $param
    };

    {
        'feed'       => \&handle_feed,
        'post'       => \&handle_post,
        'edit'       => \&handle_edit,
        'upload'     => \&handle_upload,
        'categories' => \&handle_categories,
    }->{$action}->( $r, $remote, $u, $opts );

    return OK;
}

# Authenticate via the WSSE header.
# Returns valid $u on success, undef on failure.
sub auth_wsse
{
    my ($wsse, $nonce_dup) = @_;
    my $fail = sub {
        my $reason = shift;
        return undef;
    };
    $wsse =~ s/UsernameToken // or return $fail->("no username token");

    # parse credentials into a hash.
    my %creds;
    foreach (split /, /, $wsse) {
        my ($k, $v) = split '=', $_, 2;
        $v =~ s/^[\'\"]//;
        $v =~ s/[\'\"]$//;
        $v =~ s/=$// if $k =~ /passworddigest/i; # strip base64 newline char
        $creds{ lc($k) } = $v;
    }

    # invalid create time?  invalid wsse.
    my $ctime = LJ::ParseFeed::w3cdtf_to_time( $creds{created} ) or
        return $fail->("no created date");

    # prevent replay attacks.
    $ctime = LJ::mysqldate_to_time( $ctime, 'gmt' );
    return $fail->("replay time skew") if abs(time() - $ctime) > 42300;

    my $u = LJ::load_user( LJ::canonical_username( $creds{'username'} ) )
        or return $fail->("invalid username [$creds{username}]");

    if (@LJ::MEMCACHE_SERVERS && ref $nonce_dup) {
        $$nonce_dup = 1
          unless LJ::MemCache::add( "wsse_auth:$creds{username}:$creds{nonce}", 1, 180 )
    }

    # validate hash
    my $hash =
      Digest::SHA1::sha1_base64(
        $creds{nonce} . $creds{created} . $u->password );

    if (LJ::login_ip_banned($u)) {
        return $fail->("ip_ratelimiting");
    }

    # Nokia's WSSE implementation is incorrect as of 1.5, and they
    # base64 encode their nonce *value*.  If the initial comparison
    # fails, we need to try this as well before saying it's invalid.
    if ($hash ne $creds{passworddigest}) {

        $hash =
          Digest::SHA1::sha1_base64(
                MIME::Base64::decode_base64( $creds{nonce} ) .
                $creds{created} .
                $u->password );

        if ($hash ne $creds{passworddigest}) {
            LJ::handle_bad_login($u);
            return $fail->("hash wrong");
        }
    }

    # If we're here, we're valid.
    LJ::set_remote($u);
    return $u;
}

1;
