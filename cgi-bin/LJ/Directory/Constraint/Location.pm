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

package LJ::Directory::Constraint::Location;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);
use LJ::Directory::MajorRegion;
use LJ::Directory::SetHandle::MajorRegion;

sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} || "" foreach qw(country state city);
    croak "unknown args" if %args;

    return $self;
}

sub country { $_[0]->{country} }
sub state   { $_[0]->{state} }
sub city    { $_[0]->{city} }

sub new_from_formargs {
    my ( $pkg, $args ) = @_;
    my $cn = $args->{loc_cn};
    my $st = $args->{loc_st} || '';
    return undef unless $cn || $st;
    $cn ||= "US";
    $cn = uc $cn;

    my $stateable = exists $LJ::COUNTRIES_WITH_REGIONS{$cn};

    ## Convert full region name to code, if possible
    if ($stateable) {
        my %regions;    ## state code --> state full name
        LJ::load_codes( { $LJ::COUNTRIES_WITH_REGIONS{$cn}->{'type'} => \%regions } );
        my %full_name_to_code = reverse %regions;
        $st = $full_name_to_code{$st} if exists $full_name_to_code{$st};
        $st = uc($st);
    }

    return $pkg->new(
        country => $cn,
        state   => $st,
        city    => $args->{loc_ci}
    );

}

sub cached_sethandle {
    my ($self) = @_;
    my @regids =
        LJ::Directory::MajorRegion->region_ids( $self->country, $self->state, $self->city );
    if (@regids) {
        return LJ::Directory::SetHandle::MajorRegion->new(@regids);
    }

    return undef;
}

sub cache_for { 86400 }

sub matching_uids {
    my $self = shift;
    my $db   = LJ::get_dbh("directory") || LJ::get_db_reader();

    my $p = LJ::get_prop( "user", "sidx_loc" )
        or die "no sidx_loc prop";

    my $country = $self->country || '';
    my $state   = $self->state   || '';
    my $city    = $self->city    || '';

    $country =~ s/[\_\%]//g;    # remove LIKE magic wildcards (underscore and percent)
    $state   =~ s/[\_\%]//g;
    $city    =~ s/[\_\%]//g;

    $state = '%' unless $state;    # unset? any region will ok
    $city  = '%' unless $city;

    my $prefix = join( "-", $country, $state, $city );
    $prefix =~ s/\%-\%$/%/;        # Country-%-%  --> Country-%

    my $uids =
        $db->selectcol_arrayref( "SELECT userid FROM userprop WHERE upropid=? AND value LIKE ?",
        undef, $p->{id}, $prefix )
        || [];
    return @$uids;
}

1;
