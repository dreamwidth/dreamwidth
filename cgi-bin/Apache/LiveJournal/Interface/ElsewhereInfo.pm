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

package Apache::LiveJournal::Interface::ElsewhereInfo;

use strict;
use Apache2::Const qw(:common);
use lib "$LJ::HOME/cgi-bin";
use JSON;

# for Class::Autouse (so callers can 'ping' this method to lazy-load this class)
sub load { 1 }

sub should_handle {
    my $r = shift;

    # FIXME: trust specific consumers of this data?
    return $LJ::IS_DEV_SERVER ? 1 : 0;
}

# this routine accepts the apache request handle, performs
# authentication, calls the appropriate method handler, and
# prints the response.
sub handle {
    shift if $_[0] eq __PACKAGE__;
    my $r = shift;

    my %args = $r->args;

    # should we handle this request due according to access rules?
    unless (should_handle($r)) {
        return respond($r, 403, "Forbidden");
    }

    # find what node_u we're dealing with
    my $u;
    if (my $id = $args{id}) {
        $u = LJ::load_userid($id);
        return respond($r, 404, "Invalid id: $id")
            unless $u;
    } elsif (my $node = $args{ident}) {
        $u = LJ::load_user($node);
        return respond($r, 404, "Invalid ident: $node")
            unless $u;
    } else {
        return respond($r, 400, "Must specify 'id' or 'ident'");
    }

    # find what node type we're dealing with
    my $node_type;
    my $node_ident = $u->user;
    if ( $u->is_community ) {
        $node_type = 'group';
    } elsif ( $u->is_person ) {
        $node_type = 'person';
    } elsif ( $u->is_identity ) {
        $node_type = 'openid';
        $node_ident = $u->url; # should be identity type O
    } else {
        return respond($r, 403, "Node is neither person, group, nor openid: " . $u->user . " (" . $u->id . ")");
    }

    # response hash to pass to JSON
    my %resp = (
                node_id    => $u->id,
                node_ident => $node_ident,
                node_type  => $node_type,
                );

    if (my $digest = $u->validated_mbox_sha1sum) {
        $resp{mbox_sha1sum} = $digest;
    }

    if (my $url = $u->url) {
        $resp{claimed_urls} = [ $url, 
                                # FIXME: collect more sites!
                              ];
    }

    # is the caller requesting edges for the requested node?
    my $want_edges = $args{want_edges} ? 1 : 0;

    if ($want_edges) {
        $resp{edges_in}  = [ map { $_ } $u->friendof_uids ];
        $resp{edges_out} = [ map { $_ } $u->friend_uids   ];
    }

    respond($r, 200, JSON::objToJson(\%resp));

    return OK;
}

sub respond {
    my ($r, $status, $body) = @_;

    my %msgs = (
                200 => 'OK',
                400 => 'Bad Request',
                403 => 'Forbidden',
                404 => 'Not Found',
                500 => 'Server Error',
                );

    $r->status_line(join(" ", grep { length } $status, $msgs{$status}));
    $r->content_type('text/html');#'application/json');
    $r->send_http_header();
    $r->print($body);

    return OK;
};

1;
