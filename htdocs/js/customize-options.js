       function initNavStripChooser () {
            var self = this;
            if (!$('#control_strip_color_custom')) return;
            self.hideSubDivs();
            if ($('#control_strip_color_custom').checked) this.showSubDiv("custom_subdiv");
            DOM.addEventListener($('#control_strip_color_dark'), "click", function (evt) { hideSubDivs() });
            DOM.addEventListener($('#control_strip_color_light'), "click", function (evt) { hideSubDivs() });
            DOM.addEventListener($('#control_strip_color_custom'), "click", function (evt) { showSubDiv() });
        }
        function hideSubDivs () {
            $('custom_subdiv').css('display', "none");
        }
        function showSubDivs () {
            $('custom_subdiv').css('display', "block");
        }
        function onRefresh (data) {
            initNavStripChooser();
            initCustomizeTheme();
        }

        function initCustomizeTheme () {
            // confirmation when reseting the form
            $('#reset_btn_top').click(function (evt) { confirmReset(evt) });
            $('#reset_btn_bottom').click(function (evt) { confirmReset(evt) });

            form_changed = false;
            // capture onclicks on the nav links to confirm form saving
            var links = $('#customize_theme_nav_links a').each( function(){
                if ($(this).attr('href') != "") {
                    $(this).click(function (evt) { navclick_save(evt) })
                }
            }
            )
            // register all form changes to confirm them later
            $('#customize-form select').change( function() { form_change() });
            $('#customize-form input').change( function() { form_change() });
            $('#customize-form textarea').change( function() { form_change() });

        }
        function confirmReset (evt) {
            if (! confirm("Are you sure you want to reset all changes on this page to their defaults?")) {
                Event.stop(evt);
            }
        }
        function navclick_save (evt) {
            var confirmed = false;
            if (form_changed == false) {
                return true;
            } else {
                confirmed = confirm("Save your changes?");
            }
            if (confirmed) {
                $('customize-form').submit();
            }
        }
        function form_change  () {
            if (form_changed == true) { return; }
            form_changed = true;
        }



        function alterSubheader (subheaderid, override) {
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
        }
        function expandCollapseAll (evt, ec_linkid) {
            evt.preventDefault();
            var action = ec_linkid.replace(/.+__(.+)/, '$1');
            var propgroup = ec_linkid.replace(/(.+)__.+/, '$1');
            var propgroupSubheaders = $(".subheader-" + propgroup);
            propgroupSubheaders.each(function () {
                alterSubheader($(this), action);
            });
            evt.preventDefault();
        }




        function initMoodThemeChooser () {
            var self = this;
            DOM.addEventListener($('moodtheme_dropdown'), "change", function (evt) { previewMoodTheme(evt, self) });
        }
        function previewMoodTheme (evt, elem) {
            var opt_forcemoodtheme = 0;
            if ($('opt_forcemoodtheme').checked) opt_forcemoodtheme = 1;
            self.updateContent({
                preview_moodthemeid: $('moodtheme_dropdown').value,
                forcemoodtheme: opt_forcemoodtheme
            });
        }
        function onRefresh (data) {
            initMoodThemeChooser ();
        }

        function initExpandCollapse () {
            var self = this;
            // add event listeners to all of the subheaders
             $(".subheader").click(function (evt) { alterSubheader($(this)) });
            // show the expand/collapse links
             $(".s2propgroup-outer-expandcollapse").css("display", "inline");
            // add event listeners to all of the expand/collapse links
            $(".s2propgroup-expandcollapse").click( function (evt) { expandCollapseAll(evt, $(this).attr('id')); } );

        }


//Initialize everything
$(document).ready(function(){

        initNavStripChooser();
        initMoodThemeChooser();
        initExpandCollapse();
        initCustomizeTheme();
});

