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

package LJ::Widget::Location;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use DateTime::TimeZone;
use DW::Countries;

my @location_props = qw/ country state city sidx_loc /;

sub authas   { 1 }
sub need_res { qw(js/countryregions.js) }

## The following options are supported by the render_body method
##      country         - initially selected country in country-dropbox; user prop is used for default value
##      city            - initial city value
##      state           - initial state value
##      skip_timezone   - timezone input is not displayed if true, defaults to 0
##      skip_city       - city input is not displayed if true, defaults to 0
sub render_body {
    my $class = shift;
    my %opts  = (

        # immediate values
        @_
    );

    my $minimal_display = $opts{minimal_display} ? 1 : '';

    # use "authas"-aware code
    my $u = $class->get_effective_remote;

    push @location_props, 'timezone' unless $opts{skip_timezone};
    $u->preload_props(@location_props);

    # displayed country may be specified in %opts hash
    my $effective_country = exists $opts{'country'} ? $opts{'country'} : $u->prop('country');

    # displayed state and city may be specified in %opts hash
    my $effective_state = exists $opts{'state'} ? $opts{'state'} : $u->prop('state');
    my $effective_city  = exists $opts{'city'}  ? $opts{'city'}  : $u->prop('city');

# hashref of all available countries (country code => country name), it is passed to html_select method later
    my $country_options = $class->country_options;

    # check if specified country has regions
    my $regions_cfg = $class->country_regions_cfg($effective_country);

# hashref of all regions for the specified country; it is initialized and used only if $regions_cfg is defined, i.e. the country has regions (states)
    my $state_options = $regions_cfg ? $class->region_options($regions_cfg) : undef;

    my $state_inline_desc = $class->ml('widget.location.fn.state.inline2');
    my $city_inline_desc  = $class->ml('widget.location.fn.city.inline');

    my $ret;

    unless ($minimal_display) {
        $ret .= "<table summary='' class='field_block'>\n";

        $ret .=
            "<tr><td class='field_class'>" . $class->ml('widget.location.fn.country') . "</td><td>";
    }
    $ret .= $class->html_select(
        id       => 'country_choice',
        name     => 'country',
        title    => $class->ml('widget.location.fn.country'),
        selected => $effective_country,
        class    => 'country_choice_select',
        list     => $country_options,
        %{ $opts{'country_input_attributes'} or {} },
    );
    if ($minimal_display) {
        $ret .= "<br />";
    }
    else {
        $ret .= "</td></tr>\n";

        $ret .=
            "<tr><td class='field_class'>" . $class->ml('widget.location.fn.state') . "</td><td>";
    }

    # state
    $ret .= $class->html_select(
        id       => 'reloadable_states',
        name     => 'statedrop',
        title    => $class->ml('widget.location.fn.state'),
        selected => ( $regions_cfg ? $effective_state : '' ),
        list     => $state_options,
        style    => 'display:' . ( $regions_cfg ? 'inline' : 'none' ),
        %{ $opts{'state_inputselect_attributes'} or {} },
    );

    # other state?
    my $state_val          = "";
    my $state_inline_color = "";
    unless ($regions_cfg) {
        $state_val = $state_inline_desc if $minimal_display;
        $state_val = $effective_state   if $effective_state;

        $state_inline_color = " color: #999;"
            if $minimal_display && $state_val eq $state_inline_desc;
    }

    my %minimal_display_state_attrs;
    if ($minimal_display) {
        $minimal_display_state_attrs{onfocus} =
              "if (this.value == '"
            . $state_inline_desc
            . "') { this.value = ''; this.style.color = ''; }";
        $minimal_display_state_attrs{onblur} =
              "if (this.value == '') { this.value = '"
            . $state_inline_desc
            . "'; this.style.color = '#999'; }";
    }

    $ret .= "<span style='white-space: nowrap'> ";
    $ret .= $class->html_text(
        'id'        => 'written_state',
        'name'      => 'stateother',
        'value'     => $state_val,
        'size'      => '12',
        'style'     => 'display:' . ( $regions_cfg ? 'none' : 'inline' ) . ";$state_inline_color",
        'maxlength' => '50',
        %minimal_display_state_attrs,
        %{ $opts{'state_inputtext_attributes'} or {} },
    );
    $ret .= "</span>";

    if ($minimal_display) {
        $ret .= " ";
    }
    else {
        $ret .= "</td></tr>\n";
    }

    # city
    unless ( $opts{'skip_city'} ) {
        my $city_val          = "";
        my $city_inline_color = "";
        $city_val = $city_inline_desc if $minimal_display;
        $city_val = $effective_city   if $effective_city;
        $city_inline_color = " color: #999;" if $minimal_display && $city_val eq $city_inline_desc;

        my %minimal_display_city_attrs;
        if ($minimal_display) {
            $minimal_display_city_attrs{onfocus} =
                  "if (this.value == '"
                . $city_inline_desc
                . "') { this.value = ''; this.style.color = ''; }";
            $minimal_display_city_attrs{onblur} =
                  "if (this.value == '') { this.value = '"
                . $city_inline_desc
                . "'; this.style.color = '#999'; }";
        }

        $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.city') . "</td><td>"
            unless $minimal_display;
        $ret .= $class->html_text(
            id        => 'city',
            name      => 'city',
            title     => $class->ml('widget.location.fn.city'),
            value     => $city_val,
            size      => '20',
            maxlength => '255',
            style     => "display: inline;$city_inline_color",
            %minimal_display_city_attrs,
            %{ $opts{'state_input_attributes'} or {} },
        );
        $ret .= "</td></tr>\n" unless $minimal_display;
    }

    # timezone
    unless ( $opts{'skip_timezone'} ) {
        $ret .=
              "<tr><td class='field_class'>"
            . $class->ml('widget.location.fn.timezone')
            . "</td><td>"
            unless $minimal_display;
        {
            my $map = DateTime::TimeZone::links();
            my $usmap =
                { map { $_ => $map->{$_} } grep { m!^US/! && $_ ne "US/Pacific-New" } keys %$map };
            my $camap = { map { $_ => $map->{$_} } grep { m!^Canada/! } keys %$map };

            $ret .= $class->html_select(
                name     => 'timezone',
                selected => $u->{'timezone'},
                title    => $class->ml('widget.location.fn.timezone'),
                list     => [
                    "",
                    $class->ml('widget.location.timezone.select'),
                    ( map { $usmap->{$_}, $_ } sort keys %$usmap ),
                    ( map { $camap->{$_}, $_ } sort keys %$camap ),
                    map { $_, $_ } DateTime::TimeZone::all_names()
                ]
            );
        }
        $ret .= "</td></tr>\n" unless $minimal_display;
    }

    $ret .= "</table>\n" unless $minimal_display;

    $ret .= $class->html_hidden(
        { name => "minimal_display", value => $minimal_display, id => "minimal_display" } );

# javascript code in js/countryregions.js accepts list of countries with regions as a space-delimited list
    $ret .=
"<script> var countryregions = new CountryRegions('country_choice', 'reloadable_states', 'written_state', '"
        . LJ::ejs($state_inline_desc)
        . "', 'city', '"
        . LJ::ejs($city_inline_desc) . "', '"
        . join( " ", $class->countries_with_regions )
        . "'); </script>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    # use "authas"-aware code
    my $u = $class->get_effective_remote;

    # load country codes
    my %countries;
    DW::Countries->load( \%countries );

    my $state_inline_desc   = $class->ml('widget.location.fn.state.inline2');
    my $state_from_dropdown = $class->ml('states.head.defined');
    my $city_inline_desc    = $class->ml('widget.location.fn.city.inline');

    $post->{stateother} = ""
        if $post->{stateother} eq $state_inline_desc || $post->{stateother} eq $state_from_dropdown;
    $post->{city} = "" if $post->{city} eq $city_inline_desc;

    my $regions_cfg = $class->country_regions_cfg( $post->{'country'} );
    if ( $regions_cfg && $post->{'stateother'} ) {
        $class->error( $class->ml('widget.location.error.locale.country_ne_state') );
    }
    elsif ( !$regions_cfg && $post->{'statedrop'} ) {
        $class->error( $class->ml('widget.location.error.locale.state_ne_country') );
    }

    if ( $post->{'country'} && !defined( $countries{ $post->{'country'} } ) ) {
        $class->error( $class->ml('widget.location.error.locale.invalid_country') );
    }

    return if $class->error_list;

    $post->{timezone} = ""
        unless $post->{timezone}
        && grep { $post->{timezone} eq $_ } DateTime::TimeZone::all_names();

    # check if specified country has states
    if ($regions_cfg) {

        # if it is - use region select dropbox
        $post->{'state'} = $post->{'statedrop'};

        # mind save_region_code also
        unless ( $regions_cfg->{'save_region_code'} ) {

            # save region name instead of code
            my $regions_arrayref = $class->region_options($regions_cfg);
            my %regions_as_hash  = @$regions_arrayref;
            $post->{'state'} = $regions_as_hash{ $post->{'state'} };
        }
    }
    else {
        # use state input box
        $post->{'state'} = $post->{'stateother'};
    }

    $post->{'sidx_loc'} = undef;
    if ( $opts{'save_search_index'} && $post->{'country'} ) {
        $post->{'sidx_loc'} =
            sprintf( "%2s-%s-%s", $post->{'country'}, $post->{'state'}, $post->{'city'} );
    }

    # set userprops
    $u->set_prop( $_, $post->{$_} ) foreach @location_props;

    return;
}

sub country_regions_cfg {
    my ( $class, $country ) = @_;
    return unless defined $country;
    return $LJ::COUNTRIES_WITH_REGIONS{$country};
}

sub countries_with_regions {
    keys %LJ::COUNTRIES_WITH_REGIONS;
}

sub country_options {
    my $class = shift;

    my %countries;

    # load country codes
    DW::Countries->load( \%countries );
    delete $countries{UK}
        ;    # we need to include UK in the hash for legacy reasons -- some users still have
             # their country set as UK -- but UK is mapped to GB, so there's no need to confuse
             # users by offering them expansions of both "UK" and "GB" in the drop-down.

    my $options = [
        ''   => $class->ml('widget.location.country.choose'),
        'US' => 'United States',
        map { $_, $countries{$_} } sort { $countries{$a} cmp $countries{$b} } keys %countries
    ];
    return $options;
}

sub region_options {
    my $class              = shift;
    my $country_region_cfg = shift;

    my %states = ();
    LJ::load_codes( { $country_region_cfg->{'type'} => \%states } );

    my $options = [
        '' => $class->ml('states.head.defined'),
        map { $_, $states{$_} }
            sort { $states{$a} cmp $states{$b} }
            keys %states
    ];
    return $options;
}

1;
