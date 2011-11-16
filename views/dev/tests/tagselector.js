/* INCLUDE:
jquery: js/jquery/jquery.ui.core.js
jquery: js/jquery/jquery.ui.widget.js
jquery: js/jquery/jquery.ui.dialog.js
jquery: js/jquery.tagselector.js
*/

module( "old" );
test( "no corresponding old function", function() {
    expect(0);
});

module( "jquery" );
test( "initialize tagselector", function() {
    $("textarea").tagselector();

    expect(1);

    equal($("button").length, 1);
} );



