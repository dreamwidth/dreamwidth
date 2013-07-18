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
package DW::Controller::RPC::MiscLegacy;

use strict;
use DW::Routing;
use LJ::JSON;
use LJ::CreatePage;

# do not put any endpoints that do not have the "forked from LJ" header in this file
DW::Routing->register_rpc( "checkforusername", \&check_username_handler, format => 'json' );
DW::Routing->register_rpc( "getsecurityoptions", \&get_security_options_handler, format => 'json' );
DW::Routing->register_rpc( "gettags", \&get_tags_handler, format => 'json' );

sub check_username_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;
    my $error = LJ::CreatePage->verify_username( $args->{user} );

    $r->print( to_json({ error => $error ? $error : "" }) );
    return $r->OK;
}

sub get_security_options_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $ret = sub {
        $r->print( to_json( $_[0] ) );
        return $r->OK;
    };

    my $err = sub {
        return $ret->( { 'alert' => $_[0] } );
    };


    my $remote = LJ::get_remote();
    my $user = $args->{user};
    my $u = LJ::load_user($user);

    return $ret->( {} )
        unless $u;

    my %ret = (
        is_comm => $u->is_comm ? 1 : 0,
        can_manage =>  $remote && $remote->can_manage( $u ) ? 1 : 0,
    );

    return $ret->( { ret => \%ret } )
        unless $remote && $remote->can_post_to($u);

    unless ( $ret{is_comm} ) {
        my $friend_groups = $u->trust_groups;
        $ret{friend_groups_exist} = keys %$friend_groups ? 1 : 0;
    }

    $ret{minsecurity} = $u->newpost_minsecurity;

    return $ret->( { ret => \%ret } );
}

sub get_tags_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $err = sub {
        my $msg = shift;
        $r->print( to_json({
            'alert' => $msg,
        }) );
        return $r->OK;
    };

    my $remote = LJ::get_remote();
    my $user = $args->{user};
    my $u = LJ::load_user($user);
    my $tags = $u ? $u->tags : {};

    return $err->("You cannot view this journal's tags.") unless $remote && $remote->can_post_to($u);
    return $err->("You cannot use this journal's tags.") unless $remote->can_add_tags_to($u);

    my @tag_names;
    if (keys %$tags) {
        @tag_names = map { $_->{name} } values %$tags;
        @tag_names = sort { lc $a cmp lc $b } @tag_names;
    }

    $r->print( to_json({ tags => \@tag_names }) );
    return $r->OK;
}
