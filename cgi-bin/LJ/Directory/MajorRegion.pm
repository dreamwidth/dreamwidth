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

package LJ::Directory::MajorRegion;
use strict;
use warnings;

# helper functions for location canonicalization and equivalance, etc.

my @reg = @LJ::MAJ_REGION_LIST;
if ( !@reg || $LJ::_T_DEFAULT_MAJREGIONS ) {
    @reg = (
        [ 1, "US" ],
        [ 2,  'US-AA', part_of => 'US' ],
        [ 3,  'US-AE', part_of => 'US' ],
        [ 4,  'US-AK', part_of => 'US' ],
        [ 5,  'US-AL', part_of => 'US' ],
        [ 6,  'US-AP', part_of => 'US' ],
        [ 7,  'US-AR', part_of => 'US' ],
        [ 8,  'US-AS', part_of => 'US' ],
        [ 9,  'US-AZ', part_of => 'US' ],
        [ 10, 'US-CA', part_of => 'US' ],
        [ 11, 'US-CO', part_of => 'US' ],
        [ 12, 'US-CT', part_of => 'US' ],
        [ 13, 'US-DC', part_of => 'US' ],
        [ 14, 'US-DE', part_of => 'US' ],
        [ 15, 'US-FL', part_of => 'US' ],
        [ 16, 'US-FM', part_of => 'US' ],
        [ 17, 'US-GA', part_of => 'US' ],
        [ 18, 'US-GU', part_of => 'US' ],
        [ 19, 'US-HI', part_of => 'US' ],
        [ 20, 'US-IA', part_of => 'US' ],
        [ 21, 'US-ID', part_of => 'US' ],
        [ 22, 'US-IL', part_of => 'US' ],
        [ 23, 'US-IN', part_of => 'US' ],
        [ 24, 'US-KS', part_of => 'US' ],
        [ 25, 'US-KY', part_of => 'US' ],
        [ 26, 'US-LA', part_of => 'US' ],
        [ 27, 'US-MA', part_of => 'US' ],
        [ 28, 'US-MD', part_of => 'US' ],
        [ 29, 'US-ME', part_of => 'US' ],
        [ 30, 'US-MH', part_of => 'US' ],
        [ 31, 'US-MI', part_of => 'US' ],
        [ 32, 'US-MN', part_of => 'US' ],
        [ 33, 'US-MO', part_of => 'US' ],
        [ 34, 'US-MP', part_of => 'US' ],
        [ 35, 'US-MS', part_of => 'US' ],
        [ 36, 'US-MT', part_of => 'US' ],
        [ 37, 'US-NC', part_of => 'US' ],
        [ 38, 'US-ND', part_of => 'US' ],
        [ 39, 'US-NE', part_of => 'US' ],
        [ 40, 'US-NH', part_of => 'US' ],
        [ 41, 'US-NJ', part_of => 'US' ],
        [ 42, 'US-NM', part_of => 'US' ],
        [ 43, 'US-NV', part_of => 'US' ],
        [ 44, 'US-NY', part_of => 'US' ],
        [ 45, 'US-OH', part_of => 'US' ],
        [ 46, 'US-OK', part_of => 'US' ],
        [ 47, 'US-OR', part_of => 'US' ],
        [ 48, 'US-PA', part_of => 'US' ],
        [ 49, 'US-PR', part_of => 'US' ],
        [ 50, 'US-RI', part_of => 'US' ],
        [ 51, 'US-SC', part_of => 'US' ],
        [ 52, 'US-SD', part_of => 'US' ],
        [ 53, 'US-TN', part_of => 'US' ],
        [ 54, 'US-TX', part_of => 'US' ],
        [ 55, 'US-UT', part_of => 'US' ],
        [ 56, 'US-VA', part_of => 'US' ],
        [ 57, 'US-VI', part_of => 'US' ],
        [ 58, 'US-VT', part_of => 'US' ],
        [ 59, 'US-WA', part_of => 'US' ],
        [ 60, 'US-WI', part_of => 'US' ],
        [ 61, 'US-WV', part_of => 'US' ],
        [ 62, 'US-WY', part_of => 'US' ],

        [ 63, 'RU' ],
        [
            64, 'RU-41',
            part_of => 'RU',
            spelled => [
                qr/^RU-.*-Mos[ck]ow/i,    # english
                                          # cyrillic. ignore state. capital or lowercase M.
                qr/^RU-.*-\xd0[\x9c\xbc]\xd0\xbe\xd1\x81\xd0\xba\xd0\xb2\xd0\xb0/,
                qr/^RU-.*-(Mo[sc]kau|Moskva|Msk)/i,
            ],
        ],
        [
            65,
            'RU-58',
            part_of => 'RU',
            spelled => [

                # Sankt-Peterburg:
qr/^RU-.*-\xd0\xa1\xd0\xb0\xd0\xbd\xd0\xba\xd1\x82-\xd0\x9f\xd0\xb5\xd1\x82\xd0\xb5\xd1\x80\xd0\xb1\xd1\x83\xd1\x80\xd0\xb3/,

                # Piter:
                qr/^RU-.*-\xd0\x9f\xd0\xb8\xd1\x82\xd0\xb5\xd1\x80/,
                qr/^RU-.*-P[ie]ter/,

                # English variations:
                qr/^RU-.*-((Saint|St|Sankt|S)[\. \-]{0,2})?P[ei]ters?b(u|i|e|ou)rg/i,

                # SPB:
                qr/^RU-.*-\xd0\xa1\xd0\x9f\xd0\xb1/,
                qr/^RU-.*-SPB/i,

                # Peterburg:
                qr/^RU-.*-\xd0\x9f\xd0\xb5\xd1\x82\xd0\xb5\xd1\x80\xd0\xb1\xd1\x83\xd1\x80\xd0\xb3/,
            ]
        ],
        [ 66, "CA" ],
        [ 152, 'CA-AB', part_of => 'CA' ],
        [ 153, 'CA-BC', part_of => 'CA' ],
        [ 154, 'CA-MB', part_of => 'CA' ],
        [ 155, 'CA-NB', part_of => 'CA' ],
        [ 156, 'CA-NL', part_of => 'CA' ],
        [ 157, 'CA-NT', part_of => 'CA' ],
        [ 158, 'CA-NS', part_of => 'CA' ],
        [ 159, 'CA-NU', part_of => 'CA' ],
        [ 160, 'CA-ON', part_of => 'CA' ],
        [ 161, 'CA-PE', part_of => 'CA' ],
        [ 162, 'CA-QC', part_of => 'CA' ],
        [ 163, 'CA-SK', part_of => 'CA' ],
        [ 164, 'CA-YT', part_of => 'CA' ],

        #                [67, "UK"],
        [ 68, "AU" ],
        [ 165, 'AU-ACT', part_of => 'AU' ],
        [ 166, 'AU-NSW', part_of => 'AU' ],
        [ 167, 'AU-NT',  part_of => 'AU' ],
        [ 168, 'AU-QLD', part_of => 'AU' ],
        [ 169, 'AU-SA',  part_of => 'AU' ],
        [ 170, 'AU-TAS', part_of => 'AU' ],
        [ 171, 'AU-VIC', part_of => 'AU' ],
        [ 172, 'AU-WA',  part_of => 'AU' ],

        [ 69,  'RU-1',  part_of => 'RU' ],
        [ 70,  'RU-2',  part_of => 'RU' ],
        [ 71,  'RU-3',  part_of => 'RU' ],
        [ 72,  'RU-4',  part_of => 'RU' ],
        [ 73,  'RU-5',  part_of => 'RU' ],
        [ 74,  'RU-6',  part_of => 'RU' ],
        [ 75,  'RU-7',  part_of => 'RU' ],
        [ 76,  'RU-8',  part_of => 'RU' ],
        [ 77,  'RU-9',  part_of => 'RU' ],
        [ 78,  'RU-10', part_of => 'RU' ],
        [ 79,  'RU-11', part_of => 'RU' ],
        [ 80,  'RU-12', part_of => 'RU' ],
        [ 81,  'RU-13', part_of => 'RU' ],
        [ 82,  'RU-14', part_of => 'RU' ],
        [ 83,  'RU-15', part_of => 'RU' ],
        [ 84,  'RU-16', part_of => 'RU' ],
        [ 85,  'RU-17', part_of => 'RU' ],
        [ 86,  'RU-18', part_of => 'RU' ],
        [ 87,  'RU-19', part_of => 'RU' ],
        [ 88,  'RU-20', part_of => 'RU' ],
        [ 89,  'RU-21', part_of => 'RU' ],
        [ 90,  'RU-22', part_of => 'RU' ],
        [ 91,  'RU-23', part_of => 'RU' ],
        [ 92,  'RU-24', part_of => 'RU' ],
        [ 93,  'RU-25', part_of => 'RU' ],
        [ 94,  'RU-26', part_of => 'RU' ],
        [ 95,  'RU-27', part_of => 'RU' ],
        [ 96,  'RU-28', part_of => 'RU' ],
        [ 97,  'RU-29', part_of => 'RU' ],
        [ 98,  'RU-30', part_of => 'RU' ],
        [ 99,  'RU-31', part_of => 'RU' ],
        [ 100, 'RU-32', part_of => 'RU' ],
        [ 101, 'RU-33', part_of => 'RU' ],
        [ 102, 'RU-34', part_of => 'RU' ],
        [ 103, 'RU-35', part_of => 'RU' ],
        [ 104, 'RU-36', part_of => 'RU' ],
        [ 105, 'RU-37', part_of => 'RU' ],
        [ 106, 'RU-38', part_of => 'RU' ],
        [ 107, 'RU-39', part_of => 'RU' ],
        [ 108, 'RU-40', part_of => 'RU' ],
        [ 109, 'RU-42', part_of => 'RU' ],
        [ 110, 'RU-43', part_of => 'RU' ],
        [ 111, 'RU-44', part_of => 'RU' ],
        [ 112, 'RU-45', part_of => 'RU' ],
        [ 113, 'RU-46', part_of => 'RU' ],
        [ 114, 'RU-47', part_of => 'RU' ],
        [ 115, 'RU-48', part_of => 'RU' ],
        [ 116, 'RU-49', part_of => 'RU' ],
        [ 117, 'RU-50', part_of => 'RU' ],
        [ 118, 'RU-51', part_of => 'RU' ],
        [ 119, 'RU-52', part_of => 'RU' ],
        [ 120, 'RU-53', part_of => 'RU' ],
        [ 121, 'RU-54', part_of => 'RU' ],
        [ 122, 'RU-55', part_of => 'RU' ],
        [ 123, 'RU-56', part_of => 'RU' ],
        [ 124, 'RU-57', part_of => 'RU' ],
        [ 125, 'RU-59', part_of => 'RU' ],
        [ 126, 'RU-60', part_of => 'RU' ],
        [ 127, 'RU-61', part_of => 'RU' ],
        [ 128, 'RU-62', part_of => 'RU' ],
        [ 129, 'RU-63', part_of => 'RU' ],
        [ 130, 'RU-64', part_of => 'RU' ],
        [ 131, 'RU-65', part_of => 'RU' ],
        [ 132, 'RU-66', part_of => 'RU' ],
        [ 133, 'RU-67', part_of => 'RU' ],
        [ 134, 'RU-68', part_of => 'RU' ],
        [ 135, 'RU-69', part_of => 'RU' ],
        [ 136, 'RU-70', part_of => 'RU' ],
        [ 137, 'RU-71', part_of => 'RU' ],
        [ 138, 'RU-72', part_of => 'RU' ],
        [ 139, 'RU-73', part_of => 'RU' ],
        [ 140, 'RU-74', part_of => 'RU' ],
        [ 141, 'RU-75', part_of => 'RU' ],
        [ 142, 'RU-76', part_of => 'RU' ],
        [ 143, 'RU-77', part_of => 'RU' ],
        [ 144, 'RU-78', part_of => 'RU' ],
        [ 145, 'RU-79', part_of => 'RU' ],
        [ 146, 'RU-80', part_of => 'RU' ],
        [ 147, 'RU-81', part_of => 'RU' ],
        [ 148, 'RU-82', part_of => 'RU' ],
        [ 149, 'RU-83', part_of => 'RU' ],
        [ 150, 'RU-84', part_of => 'RU' ],
        [ 151, 'RU-85', part_of => 'RU' ],
    );
}

my %code2reg;    # "US" => LJ::Directory::MajorRegion object
my %id2reg;      # id   => LJ::Directory::MajorRegion object

build_reg_objs();

sub build_reg_objs {
    my $n = 0;
    foreach my $reg (@reg) {
        my ( $id, $code, %args ) = @$reg;
        die "Duplicate ID $id"     if $id2reg{$id};
        die "Duplicate code $code" if $code2reg{$code};
        $id2reg{$id} = $code2reg{$code} = LJ::Directory::MajorRegion->new(
            id          => $id,
            code        => $code,
            parent_code => $args{part_of},
            spelled     => $args{spelled}
        );
    }
}

# --------------------------------------------------------------------------
# Instance methods

sub id   { $_[0]{id} }
sub code { $_[0]{code} }

sub has_ancestor_id {
    my ( $reg, $ancid ) = @_;
    my $iter = $reg;
    while ( $iter->{parent_code} && ( $iter = $code2reg{ $iter->{parent_code} } ) ) {
        return 1 if $iter->id == $ancid;
    }
    return 0;
}

# --------------------------------------------------------------------------
# Package methods

sub new {
    my ( $pkg, %args ) = @_;
    return bless \%args, $pkg;
}

# returns list of region ids from a search request ($countrycode,
# $statecode||$state, $city) that are part of that region.  returns
# empty list if unrecognized.
sub region_ids {
    my ( $pkg, $country, $state, $city ) = @_;
    my $regid = $pkg->region_id( $country, $state, $city )
        or return ();
    return ( $regid, $pkg->subregion_ids($regid) );
}

sub subregion_ids {
    my ( $pkgid, $rootid ) = @_;
    my @ret;
    foreach my $reg ( values %code2reg ) {
        push @ret, $reg->id if $reg->has_ancestor_id($rootid);
    }
    return @ret;
}

sub region_id {
    my ( $pkg, $country, $state, $city ) = @_;
    $country ||= "";
    $state   ||= "";
    $city    ||= "";
    my $locstr = join( "-", $country, $state, $city );

    if ( defined $code2reg{"$country-$state-$city"} ) {
        return $code2reg{"$country-$state-$city"}->{id};
    }
    if ( !$city and defined $code2reg{"$country-$state"} ) {
        return $code2reg{"$country-$state"}->{id};
    }
    if ( !$city and !$state and defined $code2reg{$country} ) {
        return $code2reg{$country}->{id};
    }
    foreach my $reg ( values %code2reg ) {
        next unless defined $reg->{spelled};

        foreach my $spi ( @{ $reg->{spelled} } ) {
            return $reg->id
                if ( ref $spi && $locstr =~ /$spi/ )
                or $locstr eq $spi;
        }
    }

    return;
}

sub most_specific_matching_region_id {
    my ( $pkg, $country, $state, $city ) = @_;
    return
           $pkg->region_id( $country, $state, $city )
        || $pkg->region_id( $country, $state )
        || $pkg->region_id($country);
}

1;
