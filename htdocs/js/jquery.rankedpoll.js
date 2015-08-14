$( document ).ready(function() {
    $('head').append('<link rel="stylesheet" type="text/css" href="//code.jquery.com/ui/1.11.4/themes/smoothness/jquery-ui.css">');
    $( ".rankedpoll_sortable_to" ).sortable({
        connectWith: "ul",
        update: function( event, ui ) {
            var elements = $(this).sortable("toArray") ;
            var questionnumber = $(this)[0].id.split("-")[1];
            $('input[id^="polltuple-'+questionnumber+ '-"]').val(''); // clear all boxes in the poll/qn
            for ( var i = 0; i < elements.length; i++ ) {
                var id = elements[i];
                var parts = id.split("-");
                $('input[id="polltuple-' + questionnumber + "-" + parts[2] + '"]').val(i+1); // ranking is 1-based not 0-based
            }
        }
    });
    $( ".rankedpoll_sortable_from" ).sortable({
      connectWith: "ul"
    });
    $( ".rankedpoll_sortable_to, .rankedpoll_sortable_from" ).disableSelection();

   // $( ".rankedpoll_hideable" ).css( "display","none" );
     
});
