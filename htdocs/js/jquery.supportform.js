(function($) {

function approve(e) {
    e.preventDefault();

    var id = $(this.parentNode).data( 'dw-screened' );
    var y_pos = $("#approveans").val( id )
        .offset().top;

    scrollTo( 0, y_pos );
}

$.supportform = {
    init: function() {
        var $faq_ref = $("<input type='text' size='3' />").change(function() {
            $("#faqid").val(this.value).triggerHandler("change");
        });

        $("#faqid").after(" <a href='#' id='faqlink'>View FAQ</a>").change( function() {
            var $link = $("#faqlink");
            if ( this.value === "0" ) {
                $link.hide();
            } else {
                $link.show().attr( "href", 'faqbrowse?faqid=' + this.value + '&view=full' );
            }
        } )
        .after(" or enter FAQ id ", $faq_ref)
        .triggerHandler( "change" );

        $("#canned").change(function() {
            if ( this.value != -1 )
                $("#reply").val( $("#reply").val() + canned[this.value] );
        });


        $( "#internaltype" ).change( function(e) {
            $( "#bounce_email" ).toggle( this.value == "bounce" );
        }).triggerHandler( "change" );


        $( "select, input" ).filter( "[name=changecat], [name=touch], [name=untouch], [name=approveans]" )
            .change( function() {
                $.supportform.makeInternal();
            });


        $( "#changesum" ).click(function() {
            if ( this.checked ) $.supportform.makeInternal();
        });

        $( "input[name=summary]").change( function(){
            $( "#changesum" ).prop( "checked", true );
            $.supportform.makeInternal();
        } );

        $(".approve").append($("<a href='#''>approve this answer</a>").click(approve));
    },

    makeInternal: function() {
        $( "#internaltype" ).val( "internal" ).triggerHandler( "change" );
    }
};

})(jQuery);

jQuery(document).ready(function($) {
    $.supportform.init();
});
