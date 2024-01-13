
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