var Customize = new Object();

Customize.init = function () {
    Customize.cat = "";
    Customize.layoutid = 0;
    Customize.designer = "";
    Customize.search = "";
    Customize.page = 1;
    Customize.show = 12;
    Customize.hourglass = null;

    var pageGetArgs = LiveJournal.parseGetArgs(document.location.href);

    if (pageGetArgs["cat"]) {
        Customize.cat = pageGetArgs["cat"];
    }

    if (pageGetArgs["layoutid"]) {
        Customize.layoutid = pageGetArgs["layoutid"];
    }

    if (pageGetArgs["designer"]) {
        Customize.designer = pageGetArgs["designer"];
    }

    if (pageGetArgs["search"]) {
        Customize.search = pageGetArgs["search"];
    }

    if (pageGetArgs["page"]) {
        Customize.page = pageGetArgs["page"];
    }

    if (pageGetArgs["show"]) {
        Customize.show = pageGetArgs["show"];
    }
}

Customize.resetFilters = function () {
    Customize.cat = "";
    Customize.layoutid = 0;
    Customize.designer = "";
    Customize.search = "";
    Customize.page = 1;
}

Customize.cursorHourglass = function (evt) {
    var pos = DOM.getAbsoluteCursorPosition(evt);
    if (!pos) return;

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.init();
        Customize.hourglass.hourglass_at(pos.x, pos.y);
    }
}

Customize.elementHourglass = function (element) {
    if (!element) return;

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.init();
        Customize.hourglass.hourglass_at_widget(element);
    }
}

Customize.hideHourglass = function () {
    if (Customize.hourglass) {
        Customize.hourglass.hide();
        Customize.hourglass = null;
    }
}

LiveJournal.register_hook("page_load", Customize.init);

//from ThemeChooser

initWidget: function () {
            var self = this;

            var filter_links = DOM.getElementsByClassName(document, "theme-cat");
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-layout"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-designer"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-page"));

            // add event listeners to all of the category, layout, designer, and page links
            // adding an event listener to page is done separately because we need to be sure to use that if it is there,
            //     and we will miss it if it is there but there was another arg before it in the URL
            filter_links.forEach(function (filter_link) {
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                if (getArgs["page"]) {
                    DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", getArgs["page"]) });
                } else {
                    for (var arg in getArgs) {
                        if (!getArgs.hasOwnProperty(arg)) continue;
                        if (arg == "authas" || arg == "show") continue;
                        DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, arg, getArgs[arg]) });
                        break;
                    }
                }
            });

            // add event listeners to all of the apply theme forms
            var apply_forms = DOM.getElementsByClassName(document, "theme-form");
            apply_forms.forEach(function (form) {
                DOM.addEventListener(form, "submit", function (evt) { self.applyTheme(evt, form) });
            });

            // add event listeners to the preview links
            var preview_links = DOM.getElementsByClassName(document, "theme-preview-link");
            preview_links.forEach(function (preview_link) {
                DOM.addEventListener(preview_link, "click", function (evt) { self.previewTheme(evt, preview_link.href) });
            });

            // add event listener to the page and show dropdowns
            DOM.addEventListener($('page_dropdown_top'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_top').value) });
            DOM.addEventListener($('page_dropdown_bottom'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", $('page_dropdown_bottom').value) });
            DOM.addEventListener($('show_dropdown_top'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "show", $('show_dropdown_top').value) });
            DOM.addEventListener($('show_dropdown_bottom'), "change", function (evt) { Customize.ThemeNav.filterThemes(evt, "show", $('show_dropdown_bottom').value) });
        },
        applyTheme: function (evt, form) {
            var given_themeid = form["Widget[ThemeChooser]_apply_themeid"].value + "";
            var given_layoutid = form["Widget[ThemeChooser]_apply_layoutid"].value + "";
            $("theme_btn_" + given_layoutid + given_themeid).disabled = true;
            DOM.addClassName($("theme_btn_" + given_layoutid + given_themeid), "theme-button-disabled disabled");

            this.doPost({
                apply_themeid: given_themeid,
                apply_layoutid: given_layoutid
            });

            Event.stop(evt);
        },
        onData: function (data) {
            Customize.ThemeNav.updateContent({
                method: "GET",
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                search: Customize.search,
                page: Customize.page,
                show: Customize.show,
                theme_chooser_id: $('theme_chooser_id').value
            });
            alert(Customize.ThemeChooser.confirmation);
            LiveJournal.run_hook("update_other_widgets", "ThemeChooser");
        },
        previewTheme: function (evt, href) {
            window.open(href, 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }



    //from ThemeNav

        initWidget: function () {
            var self = this;

            if ($('search_box')) {
                var keywords = new InputCompleteData(Customize.ThemeNav.searchwords, "ignorecase");
                var ic = new InputComplete($('search_box'), keywords);

                var text = "theme, layout, or designer";
                var color = "#999";
                $('search_box').style.color = color;
                $('search_box').value = text;
                DOM.addEventListener($('search_box'), "focus", function (evt) {
                    if ($('search_box').value == text) {
                        $('search_box').style.color = "";
                        $('search_box').value = "";
                    }
                });
                DOM.addEventListener($('search_box'), "blur", function (evt) {
                    if ($('search_box').value == "") {
                        $('search_box').style.color = color;
                        $('search_box').value = text;
                    }
                });
            }

            // add event listener to the search form
            DOM.addEventListener($('search_form'), "submit", function (evt) { self.filterThemes(evt, "search", $('search_box').value) });

            var filter_links = DOM.getElementsByClassName(document, "theme-nav-cat");

            // add event listeners to all of the category links
            filter_links.forEach(function (filter_link) {
                var evt_listener_added = 0;
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                for (var arg in getArgs) {
                    if (!getArgs.hasOwnProperty(arg)) continue;
                    if (arg == "authas" || arg == "show") continue;
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, arg, unescape( getArgs[arg] ) ) });
                    evt_listener_added = 1;
                    break;
                }

                // if there was no listener added to a link, add it without any args (for the 'featured' category)
                if (!evt_listener_added) {
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, "", "") });
                }
            });
        },
        filterThemes: function (evt, key, value) {
            if (key == "show") {
                // need to go back to page 1 if the show amount was switched because
                // the current page may no longer have any themes to show on it
                Customize.page = 1;
            } else if (key != "page") {
                Customize.resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                Event.stop(evt);
                return;
            }

            if (key == "cat") Customize.cat = value;
            if (key == "layoutid") Customize.layoutid = value;
            if (key == "designer") Customize.designer = value;
            if (key == "search") Customize.search = value;
            if (key == "page") Customize.page = value;
            if (key == "show") Customize.show = value;

            this.updateContent({
                method: "GET",
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                search: Customize.search,
                page: Customize.page,
                show: Customize.show,
                theme_chooser_id: $('theme_chooser_id').value
            });

            Event.stop(evt);

            if (key == "search") {
                $("search_btn").disabled = true;
            } else if (key == "page" || key == "show") {
                $("paging_msg_area_top").innerHTML = "<em>Please wait...</em>";
                $("paging_msg_area_bottom").innerHTML = "<em>Please wait...</em>";
            } else {
                Customize.cursorHourglass(evt);
            }
        },
        onData: function (data) {
            Customize.CurrentTheme.updateContent({
                show: Customize.show
            });
            Customize.hideHourglass();
        },
        onRefresh: function (data) {
            this.initWidget();
            Customize.ThemeChooser.initWidget();
        }
