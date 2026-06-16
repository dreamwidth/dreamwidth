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
# DW::Controller::Tools::Endpoints - AJAX endpoints used by the legacy entry
# editor. Migrated from htdocs/tools/endpoints/{ljuser,draft}.bml.

package DW::Controller::Tools::Endpoints;

use strict;

use DW::Routing;
use DW::Request;
use DW::RPC;

use DW::External::User;
use LJ::JSON;
use Storable ();

DW::Routing->register_string(
    "/tools/endpoints/ljuser", \&ljuser_handler,
    app    => 1,
    format => 'json'
);
DW::Routing->register_string(
    "/tools/endpoints/draft", \&draft_handler,
    app    => 1,
    format => 'json'
);

# Resolve a username (optionally on an external site) to its rendered
# <user>/ljuser markup, for the rich-text editor's user-tag insertion.
sub ljuser_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    my $username = $post->{username};
    my $site     = $post->{site};

    my %ret;
    my $u;

    if ($site) {

        # verify that this is a proper site
        $u = DW::External::User->new( user => $username, site => $site );
        if ($u) {
            $ret{userstr} = '<user site="' . $u->site->{domain} . '" name="' . $u->user . '">';
            $ret{ljuser}  = $u->ljuser_display;
        }
    }

    unless ($u) {
        $u            = LJ::load_user($username);
        $ret{userstr} = "<user name=\"$username\">";
        $ret{ljuser}  = LJ::ljuser($u);
    }

    # more general error message if we may have been trying to show an external site
    return DW::RPC->err("Error: Invalid user or site") if $site && !$u;

    # more specific error message if we are loading a user on the site
    return DW::RPC->err("Error: No such user") unless $u;

    sleep(1.5) if $LJ::IS_DEV_SERVER;

    $ret{success} = 1;
    return DW::RPC->out(%ret);
}

# Save, load, and clear the user's autosaved entry draft (body + properties),
# stored in the draft_properties / draft_text userprops.
sub draft_handler {
    my $r    = DW::Request->get;
    my $get  = $r->get_args;
    my $post = $r->post_args;

    # faithful to the original: errors are returned as { alert => ... }
    my $alert = sub {
        $r->print( to_json( { alert => $_[0] } ) );
        return $r->OK;
    };

    # get user
    my $u = LJ::get_remote()
        or return $alert->("User logged in");

    # check referers. should only be accessed from the update page at the moment
    LJ::check_referer("/update.bml")
        or return $alert->("Invalid referer");

    my $ret = {};

    # This thaws the contents of the userprop 'draft_properties' and
    # sends them back as a JS object.
    if ( defined $get->{getProperties} ) {
        my $rv =
            $u->prop('draft_properties')
            ? Storable::thaw( $u->prop('draft_properties') )
            : {};

        return DW::RPC->out(%$rv);
    }

    # This clears out all the fields of the user's draft, except the
    # draft body itself.
    if ( defined $post->{clearProperties} ) {
        $u->clear_prop('draft_properties');
    }

    # If even one property of the draft was changed, this saves them all into a
    # new draft (in order to avoid multiple HTTP posts which would decrease
    # performance considerably). This is checked as one big condition to avoid
    # tying draft property saving to the draft body save logic, so that users
    # won't have to change their draft body every time they want to get their
    # properties saved.
    if (   defined $post->{saveSubject}
        || defined $post->{saveUserpic}
        || defined $post->{saveTaglist}
        || defined $post->{saveMoodID}
        || defined $post->{saveMood}
        || defined $post->{saveLocation}
        || defined $post->{saveMusic}
        || defined $post->{saveAdultReason}
        || defined $post->{saveCommentSet}
        || defined $post->{saveCommentScr}
        || defined $post->{saveAdultCnt} )
    {
        my %properties = (
            subject     => $post->{saveSubject},
            userpic     => $post->{saveUserpic},
            taglist     => $post->{saveTaglist},
            moodid      => $post->{saveMoodID},
            mood        => $post->{saveMood},
            location1   => $post->{saveLocation},
            music       => $post->{saveMusic},
            adultreason => $post->{saveAdultReason},
            commentset  => $post->{saveCommentSet},
            commentscr  => $post->{saveCommentScr},
            adultcnt    => $post->{saveAdultCnt},
        );

        # If the property is null, a default menu selection or a JS undefined
        # value, we don't want to save it.
        foreach my $key ( keys %properties ) {
            my $val = $properties{$key};
            delete $properties{$key}
                if !defined $val || $val eq '' || $val eq '0' || $val eq 'undefined';
        }

        # Freeze the hash into a frozen storable string. If the hash is not empty
        # save it to the userprop. If it is, delete it.
        my $frozen_properties = Storable::nfreeze( \%properties );
        if ( $frozen_properties =~ /\w/ ) {
            $u->set_prop( 'draft_properties', $frozen_properties );
        }
        else {
            $u->clear_prop('draft_properties');
        }
    }

    # This saves the main body of the draft.
    if ( defined $post->{saveDraft} ) {
        $u->set_draft_text( $post->{saveDraft} );

        # This clears out the main body of the draft.
    }
    elsif ( $post->{clearDraft} ) {
        $u->set_draft_text('');

    }
    else {
        $ret->{draft} = $u->draft_text;
    }

    sleep 1 if $LJ::IS_DEV_SERVER;

    return DW::RPC->out(%$ret);
}

1;
