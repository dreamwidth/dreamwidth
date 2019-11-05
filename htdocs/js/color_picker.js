jQuery(function($){

var defaults = {
    theme: 'monolith',
    useAsButton: true,

   components: {

        // Main components
        preview: true,
        opacity: false,
        hue: true,

        // Input / output Options
        interaction: {
            cancel: true,
            clear: true,
            save: true
        }
    }
}


$('.color_picker_button').click( function () {
    var input = $(this);
    var container = $(this).parent('.color_picker_input');
    var text = container.siblings(".color_picker_text");

    var pickr = Pickr.create($.extend({}, defaults, {el: this, default: text.val(), container: container[0]}));
    pickr.show();

    text.blur(function(e) {
        input.css("background-color", text.val() );
    });

    pickr.on('save', function(color, instance) {
    	var colorstring = "";
    	if (color != null) {
    		colorstring = color.toHEXA().toString();
    	}
        input.css("background-color", colorstring );
        text.val(colorstring);
        instance.hide();
    });

    function delayDestroy(instance) {
        instance.destroyAndRemove();
    }
    pickr.on('clear', function(instance) { instance.hide();});
    pickr.on('cancel', function(instance) { instance.hide();});
    pickr.on('hide', function(instance) { text.focus(); window.setTimeout(delayDestroy, 400, instance);});


})



});
