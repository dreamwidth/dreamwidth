
if( document.getElementById('points-cost')) {
    setInterval(
        function() {
            document.getElementById('points-cost').innerHTML = 'Cost: <strong>$' + (document.getElementById('points').value / 10).toFixed(2) + ' USD</strong>';
        }, 250 );
};

if( document.getElementById('icons-cost')) {
    setInterval(
        function() {
            document.getElementById('icons-cost').innerHTML = 'Cost: <strong>$' + (document.getElementById('icons').value / 1).toFixed(2) + ' USD</strong>';
        }, 250 );
};
