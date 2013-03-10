jQuery(function($) {

var dependencies = {
    "lj_entries_remap_icon" : [ "lj_entries" ],
    "lj_comments"           : [ "lj_entries" ],
    "lj_entries"            : [ "lj_tags", "lj_friendgroups" ],
    "lj_friends"            : [ "lj_friendgroups" ]
};

var reverseDependencies = {};
$.each(dependencies, function(origElement, deps) {
    $.each(deps,function(index,dependency) {
        if ( reverseDependencies[dependency] === undefined )
            reverseDependencies[dependency] = [];
        reverseDependencies[dependency].push( origElement );
    });
});

$.fn.toggleDependencies = function( dependencyMap, enable ) {
    // first get all dependencies for this element and check / uncheck them
    // then look for all dependencies of those dependencies
    $(dependencyMap[this.attr("id")].map(function(value){ return "#"+value; }).join(","))
        .prop( "checked", enable )
        .trigger( enable ? "dw.importer.on" : "dw.importer.off" );
};

$.each(dependencies, function(elementId) {
    // enable everything this item is dependent on
    $("#"+elementId).click(function(e) {
        $(this).filter(":checked").trigger( "dw.importer.on" );
    }).bind( "dw.importer.on", function() {
        $(this).toggleDependencies( dependencies, true );
    });
});

$.each(reverseDependencies, function(elementId) {
    // disable everything that's dependent upon this item
    $("#"+elementId).click(function(e) {
        $(this).filter(":not(:checked)").trigger( "dw.importer.off" );
    }).bind( "dw.importer.off", function () {
        $(this).toggleDependencies( reverseDependencies, false );
    });
});

});