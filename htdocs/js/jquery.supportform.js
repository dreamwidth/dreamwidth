(function($) {

$.supportform = {
    init: function() {
        $( "select[name=faqid]" ).change( function() {
            var $link = $("#faqlink");
            if ( this.value === "0" ) {
                $link.hide();
            } else {
                $link.show().attr( "href", 'faqbrowse?faqid=' + this.value + '&view=full' );
            }
        } ).triggerHandler( "change" );


        $( "#replytype" ).change( function(e) {
            $( "#bounce_email" ).toggle( this.value == "bounce" );

            var $tier = $("#tier_cell");
            var $approveans = $("#approveans");
            if ( $tier.length > 0 && $approveans.length === 0 ) {
                $tier.toggle( this.value === "answer" || this.value === "internal" );
            }

            e.stopPropagation();
        }).triggerHandler( "change" );


        $( "select, input" ).filter( "[name=changecat], [name=changelanguage], [name=touch], [name=untouch], [name=approveans]" )
            .change( function() {
                $.supportform.makeInternal();
            });


        $( "#changesum" ).click(function() {
            if ( this.checked ) $.supportform.makeInternal();
        });

        $( "input[name=summary]").change( function(){
            $( "#changesum" ).attr( "checked", "checked" );
            $.supportform.makeInternal();
        } );


        $( "#clear" ).click(function(e) {
            $("#body").val( "" ).focus();
            e.preventDefault();
        }).focus(function() {
            $("#submitpost").focus();
        });
    },

    makeInternal: function() {
        $( "#replytype" ).val( "internal" ).triggerHandler( "change" );
    }
};

})(jQuery);

jQuery(document).ready(function($) {
    $.supportform.init();
});
