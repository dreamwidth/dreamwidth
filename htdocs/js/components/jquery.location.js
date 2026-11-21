(function($) {
function CountryRegions( $element ) {
    this.countrySelect = $element.find("select[name=country]");
    this.stateField = $element.find(".state-field")
    this.stateSelect = $element.find("select[name=statedrop]");
    this.stateText = $element.find("input[name=stateother]");

    this.initializeCountriesWithRegions( $element.data("country-regions").split(/\s+/) );

    this.showStateOptions( this.stateSelect.find("option").length > 1 );
    this.countrySelect.change(this.countryChanged.bind(this));
}

CountryRegions.prototype = {
    countrySelect: undefined,
    countriesWithRegions: {},

    initializeCountriesWithRegions: function(countries) {
        for ( var i = 0; i < countries.length; i++ ) {
            this.countriesWithRegions[countries[i]] = true;
        }
    },

    countryChanged: function(e) {
        this.selectedCountry = this.countrySelect.val();

        if ( this.countriesWithRegions[this.selectedCountry] ) {
            $.post( $.endpoint( "load_state_codes" ), { "country" : this.selectedCountry } )
                .then(this.updateStateOptions.bind(this));
        }

        this.updateStateOptions();
    },

    updateStateOptions: function( stateData ) {
        var stateSelect = this.stateSelect.get(0);

        stateSelect.options.length = 0; // discard previous
        stateSelect.value = '';

        if ( stateData && stateData.states.length > 0 ) {
            stateSelect.options[0] = new Option( stateData.head, "" );
            var states = stateData.states;
            for (var i = 0; i < states.length / 2; i++ ) {
                stateSelect.options[i + 1] = new Option( states[2 * i + 1], states[2 * i] );
            }
        }

        this.showStateOptions( stateSelect.options.length > 1 );
    },

    showStateOptions: function( hasOptions ) {
        this.stateField.toggleClass( "has-state-options", hasOptions );
        this.stateSelect.prop( "disabled", !hasOptions );
        this.stateText.prop( "disabled", hasOptions );
        if ( hasOptions ) this.stateText.val( '' );
    }
};

$.fn.extend({
    countryRegions: function() {
        new CountryRegions( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $("[data-country-regions]").countryRegions();
});
