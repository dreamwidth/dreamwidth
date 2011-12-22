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
test( "initialize tagselector", 3, function() {
    $("textarea").tagselector();
    equal($("button").length, 1);

    equal($(".tagselector.ui-widget").length, 0);
    $("button").click();
    equal($(".tagselector.ui-widget").length, 1);

    $(".tagselector.ui-widget").hide();
} );

test( "test tag input", 2, function() {
    // test data
    var tags = [
            "\"something in quotes\"",
            "#etc","$test","+test",":test",
            "<strong>abc</strong>",
            "1337"];

    // we expect that this set of input will break the selector
    // (so we must fix this at a server level)
    var breaking = [ 1337 ];

    // FIXME: needs to be more generic
    var tags_data = { currentCache: "foo",
                      cache: { "foo": tags, "breaking": breaking },
                      cachemap: {},
                      tagslist: [] };
    $("textarea").data("autocompletewithunknown", tags_data);

    $("textarea").tagselector();
    $("button").click();

    equal($(".tagselector.ui-widget :checkbox").length, tags.length);
    $("#tagselector_select").click();   // close the dialog

    raises(function() {
        tags_data.currentCache = "breaking";
        $("textarea").tagselector();
        $("button").click();
    }, /has no method 'replace'/, "Confirm kind of input that can break the tagselector");

    $(".tagselector.ui-widget").hide();
});



