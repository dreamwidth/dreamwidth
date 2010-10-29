jQuery(function($) {
    var select = $( '#edit_theme' );
    var optgr = $( 'optgroup', select );

    var theme_layers = {};
    var out_layers = $( '<select />' );
    select.before( out_layers );

    $.each( optgr, function(_, x) {
        var themes = $( 'option', x );
        theme_layers[ x.label ] = $.map( themes, function (y) { 
            return y.text;
        });
        out_layers.append( $("<option/>", {
            'value': x.label,
            'text': x.label
        }) );
    });
    select.empty();
    
    var update_themes = function () {
        select.empty();
        var lay = out_layers[0].value;
        if ( theme_layers[ lay ] == undefined ) return;
        $.each( theme_layers[ lay ], function(_, x) {
            select.append( $("<option/>", {
                'value': lay + "/" + x,
                'text': x
            }) );
        }); 
    };

    out_layers.change( update_themes );
    update_themes();

    window._dbg = theme_layers;
});
