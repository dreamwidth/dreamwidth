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

### NOTE
# This is only invoked via multisearch.bml! Or in other words, web context,
# where we're able to LJ::get_remote() the person doing the search. It'll need
# to be updated if we want to call it in directory search, because we won't
# have $remote immediately available to us.

package LJ::Directory::Constraint::ContactInfo;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

# wants screen name or handle
sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{screenname} = delete $args{screenname};
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ( $pkg, $args ) = @_;
    return undef unless $args->{screenname};
    return $pkg->new( screenname => $args->{screenname} );
}

sub cache_for { 5 * 60 }

sub screenname { $_[0]->{screenname} }

sub matching_uids {
    my $self = shift;
    return unless $self->screenname;

    my $dbr = LJ::get_dbh("directory") || LJ::get_db_reader();

    my @propids;

    # FIRST: check whether we get matches based on IM services
    foreach my $service (qw(icq jabber skype google_talk)) {
        my $p = LJ::get_prop( "user", $service );
        push @propids, $p->{upropid};
    }

    my $bind = LJ::DB::bindstr(@propids);
    my $rows = $dbr->selectcol_arrayref(
        "SELECT userid FROM userprop WHERE upropid IN ($bind) AND value = ?",
        undef, @propids, $self->screenname );
    die $dbr->errstr if $dbr->err;
    my @uids = @{ $rows || [] };

    # SECOND: check for lj jabber matches
    if ( $self->screenname =~ /(.+)\@$LJ::USER_DOMAIN$/ ) {
        push @uids, LJ::get_userid($1);
    }

    # load 'em up, see if they want to share their info.
    # usually we avoid loading userids at this layer, but the expected
    # size of this set is maybe a dozen, max, so no big deal.

    my $remote = LJ::get_remote();
    my @done;

    my $us = LJ::load_userids(@uids);
    foreach my $u ( values %$us ) {
        next unless $u;
        next unless $u->is_person || $u->is_identity;
        next unless $u->is_visible;
        next unless $u->share_contactinfo($remote);
        push @done, $u->id;
    }

    return @done;
}

1;
