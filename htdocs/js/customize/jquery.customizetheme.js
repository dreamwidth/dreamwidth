(function($) {

function CustomizeTheme() {
    var customizeTheme = this;
    customizeTheme.init();
}

CustomizeTheme.prototype = {
        form_changed: false,

        navclick_save: function (evt) {
            var customizeTheme = this;
            var confirmed = false;
            if (customizeTheme.form_changed == false) {
                return true;
            } else {
                confirmed = confirm("Save your changes?");
            }
            console.log(confirmed);
            if (confirmed) {
                console.log("we're confirmed!~");
                var form = $('#customize-form');
                console.log(form);
                $('#customize-form').submit(function( event ) {
  console.log( "Handler for .submit() called." );
});
                $('#customize-form').trigger( "submit" );
            }
        },

        init: function () {
            var customizeTheme = this;
            // confirmation when reseting the form
            $('#reset_btn_top').click(function (evt) { customizeTheme.confirmReset(evt) });
            $('#reset_btn_bottom').click(function (evt) { customizeTheme.confirmReset(evt) });

            customizeTheme.form_changed = false;
            // capture onclicks on the nav links to confirm form saving
            var links = $('#customize_theme_nav_links a').each( function(){
                if ($(this).attr('href') != "") {
                    $(this).click(function (evt) { customizeTheme.navclick_save(evt) })
                }
            }
            )
            // register all form changes to confirm them later
            $('#customize-form select').change( function() { customizeTheme.form_change() });
            $('#customize-form input').change( function() { customizeTheme.form_change() });
            $('#customize-form textarea').change( function() { customizeTheme.form_change() });

            // initialize the expand and collapse links

            // add event listeners to all of the subheaders
             $(".subheader").click(function (evt) { customizeTheme.alterSubheader($(this)) });
            // show the expand/collapse links
             $(".s2propgroup-outer-expandcollapse").css("display", "inline");
            // add event listeners to all of the expand/collapse links
            $(".s2propgroup-expandcollapse").click( function (evt) { customizeTheme.expandCollapseAll(evt, $(this).attr('id')); } );


        },

        confirmReset: function (evt) {
            if (! confirm("Are you sure you want to reset all changes on this page to their defaults?")) {
                Event.stop(evt);
            }
        },

        form_change: function () {
            var customizeTheme = this;
            if (customizeTheme.form_changed == true) { return; }
            customizeTheme.form_changed = true;
        },

        alterSubheader: function (subheaderid, override) {
            var self = this;
            var proplistid = subheaderid.attr('id').replace(/subheader/, 'proplist');

            // figure out whether to expand or collapse
            var expand = !subheaderid.hasClass('expanded');
            if (override) {
                if (override == "expand") {
                    expand = 1;
                } else {
                    expand = 0;
                }
            }
            if (expand) {
                // expand
                subheaderid.removeClass('collapsed').addClass('expanded');
                subheaderid.children('.collapse-button').text (ml.expanded);
                $('#'+ proplistid).css('display', "block");
            } else {
                // collapse
                subheaderid.removeClass('expanded').addClass('collapsed');
                subheaderid.children('.collapse-button').text(ml.collapsed);
                $('#'+ proplistid).css('display', "none");
            }
        },

        expandCollapseAll: function (evt, ec_linkid) {
            var customizeTheme = this;
            evt.preventDefault();
            var action = ec_linkid.replace(/.+__(.+)/, '$1');
            var propgroup = ec_linkid.replace(/(.+)__.+/, '$1');
            var propgroupSubheaders = $(".subheader-" + propgroup);
            propgroupSubheaders.each(function () {
                customizeTheme.alterSubheader($(this), action);
            });
            evt.preventDefault();
        },
};

$.fn.extend({
    customizeTheme: function() {
        new CustomizeTheme( $(this) );
    }
});
})(jQuery);

jQuery(function($){
    $().customizeTheme();
    $("body").collapse();
});
