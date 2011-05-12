(function($){

$.widget("dw.mediaplaceholder", {
    _create: function() {
        var parent = this.element.closest(".LJ_Placeholder_Container");
        var container = parent.find("div.LJ_Container");
        var html = parent.find("div.LJ_Placeholder_HTML");

        if ( parent.size == 0 || container.size == 0 || html.size == 0 ) return;

        this.element.click(function(e){
            e.stopPropagation();
            e.preventDefault();

            console.log(html);
            var originalembed = $(unescape(html.html()))
                .wrap("<span></span>"); // IE weirdness
            container.append(originalembed);
            $(this).hide();
        });

    }
});

})(jQuery);

jQuery(document).ready(function($){
    $("img.LJ_Placeholder").mediaplaceholder();
    $(document.body).delegate("*","updatedcontent.entry", function(e) {
        $(this).find("img.LJ_Placeholder").mediaplaceholder();
    });
});
