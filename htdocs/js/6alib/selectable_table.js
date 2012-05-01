/*
  This is a datasource you can attach to a table. It will enable
  the selection of rows or cells in the table.

  The data in the datasource is elements that are selected.

  $id:$
*/

SelectableTable = new Class(DataSource, {

    // options:
    //   table: what table element to attach to
    //   selectableClass: if you only want elements with a certain class to be selectable,
    //       specifiy this class with selectableClass
    //   multiple: can more than one thing be selected at once? default is true
    //   selectedClass: class to apply to selected elements
    //   checkboxClass: since there are frequently checkboxes associated with selectable elements,
    //       you can specify the class of your checkboxes to make them stay in sync
    //   selectableItem: What type of elements can be selected. Values are "cell" or "row"
    init: function (opts) {
        if ( SelectableTable.superClass.init )
            SelectableTable.superClass.init.apply(this, []);

        var table = opts.table;
        var selectableClass = opts.selectableClass;
        var multiple = opts.multiple;
        var selectedClass = opts.selectedClass
        var checkboxClass = opts.checkboxClass
        var selectableItem = opts.selectableItem;

        selectableItem = selectableItem == "cell" ? "cell" : "row";

        if (!defined(multiple)) multiple = true;

        this.table = table;
        this.selectableClass = selectableClass;
        this.multiple = multiple;
        this.selectedClass = opts.selectedClass;
        this.checkboxClass = opts.checkboxClass;

        this.selectedElements = [];

        // if it's not a table, die
        if (!table || !table.tagName || table.tagName.toLowerCase() != "table") return null;

        // get selectable items
        var tableElements = table.getElementsByTagName("*");

        var selectableElements;

        if (selectableItem == "cell") {
            selectableElements = DOM.filterElementsByTagName(tableElements, "td");
        } else {
            selectableElements = DOM.filterElementsByTagName(tableElements, "tr");
        }

        var self = this;
        selectableElements.forEach(function(ele) {
            // if selectableClass is defined and this element doesn't have the class, skip it
            if (selectableClass && !DOM.hasClassName(ele, selectableClass)) return;

            // attach click handler to every element inside the element
            var itemElements = ele.getElementsByTagName("*");
            for (var i = 0; i < itemElements.length; i++) {
                self.attachClickHandler(itemElements[i], ele);
            }

            // attach click handler to the element itself
            self.attachClickHandler(ele, ele);
        });
    },

    // stop our handling of this event
    stopHandlingEvent: function (evt) {
        if (!evt) return;

        // w3c
        if (evt.stopPropagation)
        evt.stopPropagation();

        // ie
        try {
            event.cancelBubble = true;
        } catch(e) {}
    },

    // attach a click handler to this element
    attachClickHandler: function (ele, parent) {
        if (!ele) return;

        var self = this;

        var rowClicked = function (evt) {
            // if it was a control-click or a command-click
            // they're probably trying to open a new tab or something.
            // let's not handle it
            if (evt && (evt.ctrlKey || evt.metaKey)) return false;

            var tagName = ele.tagName.toLowerCase();

            // if this is a link or has an onclick handler,
            // return true and tell other events to return true
            if ((ele.href && tagName != "img") || ele.onclick) {
                self.stopHandlingEvent(evt);
                return true;
            }

            // if this is the child of a link, propagate the event up
            var ancestors = DOM.getAncestors(ele, true);
            for (var i = 0; i < ancestors.length; i++) {
                var ancestor = ancestors[i];
                if (ancestor.href && ancestor.tagName.toLowerCase() != "img") {
                    return true;
                }
            }

            // if this is an input or select element, skip it
            if ((tagName == "select" || tagName == "input") && parent.checkbox != ele) {
                self.stopHandlingEvent(evt);
                return true;
            }

            // toggle selection of this parent element
            if (self.selectedElements.indexOf(parent) != -1) {
                if (self.selectedClass) DOM.removeClassName(parent, self.selectedClass);

                self.selectedElements.remove(parent);
            } else {
                if (self.selectedClass) DOM.addClassName(parent, self.selectedClass);

                if (self.multiple) {
                    self.selectedElements.push(parent);
                } else {
                    if (self.selectedClass && self.selectedElements.length > 0) {
                        var oldParent = self.selectedElements[0];
                        if (oldParent) {
                            DOM.removeClassName(oldParent, self.selectedClass);
                            if (oldParent.checkbox) oldParent.checkbox.checked = "";
                        }
                    }

                    self.selectedElements = [parent];
                }
            }

            // update our data
            self.setData(self.selectedElements);

            // if there's a checkbox associated with this parent, set it's value
            // to the parent selected value
            if (parent.checkbox) parent.checkbox.checked = (self.selectedElements.indexOf(parent) != -1) ? "on" : '';
            if (parent.checkbox == ele) { self.stopHandlingEvent(evt); return true; }

            // always? not sure
            if (evt)
                Event.stop(evt);
        }

        // if this is a checkbox we need to keep in sync, set up its event handler
        if (this.checkboxClass && ele.tagName.toLowerCase() == "input"
            && ele.type == "checkbox" && DOM.hasClassName(ele, this.checkboxClass)) {

            parent.checkbox = ele;

            // override default event handler for the checkbox
            DOM.addEventListener(ele, "click", function (evt) {
                return true;
            });
        }

        // attach a method to the row so other people can programatically
        // select it.
        ele.rowClicked = rowClicked;

        DOM.addEventListener(ele, "click", rowClicked);
    }

});
