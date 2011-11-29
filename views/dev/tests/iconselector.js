/* INCLUDE:
jquery: js/jquery/jquery.ui.core.js
jquery: js/jquery/jquery.ui.widget.js
jquery: js/jquery/jquery.ui.dialog.js
jquery: js/jquery.iconselector.js
*/

module( "old" );
test( "no corresponding old function", 0, function() {
});

module( "jquery" );
test( "initialize iconselector", 4, function() {
    // setup callback
    var server = sinon.sandbox.useFakeServer();

    var icons = {
        "pics": {},
        "ids" : []
    };
    var data = [
        {
            "id"     : 1,
            "url"    : "/img/ajax-loader.gif",
            "state"  : "A",
            "width"  : 16,
            "height" : 16,
            "alt"    : "swirling loading icon",
            "comment": "by ...",
            "keywords": ["loading", "animated"]
        }
    ];
    var keywords = [ "" ];
    for ( var i = 0; i < data.length; i++ ) {
        var icon = data[i];
        icons.pics[icon.id] = icon;
        icons.ids.push( icon.id )

        for ( var k = 0; k < icon.keywords.length; k++ ) {
            keywords.push(icon.keywords[k]);
        }
    }

    server.respondWith( /userpicselect/, [
        200,
        {},
        JSON.stringify(icons)
    ] );

    var $select = $("select");
    $.map(keywords, function(keyword) {
        $("<option></option>").val(keyword).text(keyword).appendTo($select)
    })
    equals( $select.val(), "", "currently selected the first item in the dropdown (blank)" )

    // setup the icon selector
    var selectCount = 0;
    $select.iconselector({
        selectorButtons: "#browse-icons",
        onSelect: function() { selectCount++ }
    });

    $("#browse-icons").click();
    server.respond();

    $("#iconselector_icons .keyword:contains('animated')").click();
    equals( $select.val(), "", "one click doesn't do anything");

    $("#iconselector_icons .keyword:contains('animated')").dblclick();
    equals( $select.val(), "animated", "two clicks selects");
    equals( selectCount, 1, "select done once");
} )
