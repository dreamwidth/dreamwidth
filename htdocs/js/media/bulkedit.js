jQuery(function($) {
    function selectForDelete() {
        var $this = $(this);
        $this.closest(".inner").toggleClass("ui-state-highlight", $this.is(":checked") );
    }

    function doDelete(e) {
        var form = this.form;
        e.preventDefault();
        var response = confirm( "Are you sure you want to delete these files?" );

        if ( response ) {
            var data = $(form).serializeArray();
            data.push({ name: "action:delete", value: true});
            // Reload so the server can clamp the page and redraw pagination after deletion.
            $.post( form.action, data, function() {
                window.location.href = form.action;
            } );
        }
    }

    $("#media-manage input[name=delete]").change(selectForDelete);
    $("#media-manage input[name='action:delete']").click(doDelete);
})