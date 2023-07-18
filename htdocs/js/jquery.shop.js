    var initDate = function() {
        function zeropad(num) { return num < 10 ? "0" + num : num }
        function padAll(text, sep) {
            return $.map( text.split(sep), function(value, index) {
                return zeropad(parseInt(value, 10));
            } ).join(sep);
        }

        // Hack: the 3rd-party date/time picker expects a trigger button with no
        // child elements, causing bad behavior on our icon <button>s.
        // jQuery can't do capturing events, so we do this raw.
        document.getElementById('deliverydate')
            .addEventListener('click', mungePickerTargets, true);
        function mungePickerTargets(e) {
            if ( $(e.target).is('#js-deliverydate-button > span') ) {
                e.stopPropagation();
                e.preventDefault();
                e.target.parentNode.click();
            }
        }

        $("#js-deliverydate").pickadate({
            editable: true,
            format: 'yyyy-mm-dd',

            trigger: document.getElementById("js-deliverydate-button"),
            container: '#deliverydate .picker-output',

            klass: {
                picker: 'picker picker--date',

                navPrev: 'picker__nav--prev fi-icon fi-arrow-left',
                navNext: 'picker__nav--next fi-icon fi-arrow-right',

                buttonClear: 'picker__button--clear secondary',
                buttonToday: 'picker__button--today',
                buttonClose: 'picker__button--close secondary'
            }
        }).change(function(e) {
            var picker = $(e.target).pickadate('picker');
            var oldValue = picker.get('select', 'yyyy-mm-dd');
            var newValue = padAll(picker.get('value'), '-');

            if ( oldValue !== newValue ) {
                picker.set('select', newValue);
            }
        });
    };

if (document.getElementById('deliverydate')) {
    initDate();
}

if( document.getElementById('points-cost')) {
    setInterval(
        function() {
            $('#points-cost').html( 'Cost: <strong>$' + ($('#points').val() / 10).toFixed(2) + ' USD</strong>' );
        }, 250 );
};

if( document.getElementById('icons-cost')) {
    setInterval(
        function() {
            $('#icons-cost').html( 'Cost: <strong>$' + ($('#icons').val() / 1).toFixed(2) + ' USD</strong>' );
        }, 250 );
};