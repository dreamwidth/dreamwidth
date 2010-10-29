jQuery(function($) {
    $("#clear_visible").click(function (event) {
        $("#table_data tr:visible input[type='checkbox']:checked").each( function (_,x) {
            x.checked = false;
        } );
        event.preventDefault();
    });
    
    $("#check_visible").click(function (event) {
        $("#table_data tr:visible input[type='checkbox']").each( function (_,x) {
            x.checked = true;
        } );
        event.preventDefault();
    });

    $("#filter_apply").click(function () {
        var act = $("#filter_act")[0].value;
        var redist = $("#filter_redist")[0].value;
        var header;
        var ct;
        var handle_header = function ( nh ) {
            if ( header != undefined )
                if ( ct == 0 )
                    header.hide();
                else
                    header.show();
            header = nh;
            ct = 0; 
        }
        $("#table_data tr").each( function (_,x) {
            var xj = $(x);
            if ( xj.attr('data-header') )
                return handle_header( xj );
            var vl = $("input[type='checkbox']", x)[0];
            var show = 1;
            if ( show && act == "active" )
                show = vl.checked ? 1 : 0;
            else if ( show && act == "inactive" )
                show = vl.checked ? 0 : 1;
            if ( show && redist.length > 0 &&
                    xj.attr('data-redist').indexOf( redist ) == -1 )
                show = false;
            if ( show ) { 
                ct++;
                xj.show();
            } else {
                xj.hide();
            }
        });
        handle_header();
    });
});
