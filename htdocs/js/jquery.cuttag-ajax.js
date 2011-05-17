(function($,Site) {

var isExpandingAll = 0;

var loadPending = 0;

$.widget("dw.cuttag", {
    options: {
        journal: undefined,
        ditemid: undefined,
        cutid: undefined
    },
    config: {
        text: {
            collapse: 'Collapse',
            expand: 'Expand',
            loading: 'Expanding'
        }
    },
    _create: function() {
        var self = this;
        var spanid = self.element.attr("id");

        self.options.journal = spanid.replace( /^span-cuttag_(.*)_[0-9]+_[0-9]+/, "$1");
        self.options.ditemid = spanid.replace( /^.*_([0-9]+)_[0-9]+/, "$1");
        self.options.cutid = spanid.replace( /^.*_([0-9]+)/, "$1");

        var identifier = self.options.journal + '_' + self.options.ditemid + '_' + self.options.cutid;

        self.identifier = identifier;
        self.ajaxUrl = "/__rpc_cuttag?journal=" + self.options.journal + "&ditemid=" + self.options.ditemid + "&cutid=" + self.options.cutid;

        var a = $("<a>",{
            href: "#",
            id: "cuttag_" + identifier,
            "class": "cuttag-action"
        });
        var img = $("<img>",{
            style: "border: 0;",
            "aria-controls": 'div-cuttag_' + identifier
        });
        a.append(img);

        var theDiv = $("#div-cuttag_" + identifier);

        self.tag = {
            "a": a,
            "img": img,
            "div": theDiv
        };

        self._setArrow("/collapse.gif", self.config.text.expand);

        self.element.append(a);

        a.click(function(e) {
            isExpandingAll = 0;
            e.stopPropagation();
            e.preventDefault();
            self.toggle();
        });

        self.element.css("display","inline");

        if ( isExpandingAll )
            this.open();
    },
    isOpen: function() {
        return this.element.hasClass("cuttag-open") ? 1 : 0;
    },
    toggle: function() {
        if ( this.isOpen() )
            this.close();
        else
            this.open();
    },
    open: function() {
        var self = this;
        if ( self.isOpen() )
            return;

        loadPending++;
        self._setArrow("/ajax-loader.gif", self.config.text.loading);
        $.ajax({
            "method": "GET",
            "url": self.ajaxUrl,
            success: function(data) {
                self.replaceCutTag(data);
            },
            error: function(jqXHR, error) {
                self.handleError(error);
            }
        });
    },
    close: function() {
        if ( ! this.isOpen() )
            return;
        this.element.removeClass("cuttag-open");
        this._setArrow("/collapse.gif", this.config.text.expand);

        this.tag.div.empty();
        this.tag.div.css("display","none");

        $.dw.cuttag_controls.updateAll();
    },
    _setArrow: function(path,str) {
        var i = this.tag.img;
        i.attr("src",Site.imgprefix + path);
        i.attr("alt",str);
        i.attr("title",str);
    },
    handleError: function(error) {
        this._setArrow("/collapse.gif", this.config.text.expand);
        alert(error);
    },
    replaceCutTag: function(resObj) {
        var self = this;
        if ( resObj.error ) {
            self._setArrow("/collapse.gif", self.config.text.expand);
        } else {
            var replaceDiv = self.tag.div;
            replaceDiv.html(resObj.text);
            replaceDiv.css("display","block");

            var closeEnd = $("<span>");
            var a = $("<a>",{
                href: "#cuttag_" + self.identifier,
                "class": "cuttag-action"
            });
            var img = $("<img>",{
                style: "border: 0;",
                src: Site.imgprefix + "/collapse-end.gif",
                "aria-controls": 'div-cuttag_' + self.identifier,
                alt: self.config.text.collapse,
                title: self.config.text.collapse
            });
            a.append(img);
            closeEnd.append(a);
            replaceDiv.append(closeEnd);

            a.click(function(e) {
                e.stopPropagation();
                e.preventDefault();
                self.toggle();
            });

            self.element.addClass("cuttag-open");
            self._setArrow("/expand.gif", self.config.text.collapse);

            replaceDiv.trigger( "updatedcontent.entry" );
            $.dw.cuttag.initLinks(replaceDiv);

            loadPending--;

            if ( loadPending == 0 ) {
                isExpandingAll = 0;
            }

            $.dw.cuttag_controls.updateAll();
        }
    }
});

$.widget("dw.cuttag_controls", {
    config: {
        text: {
            collapse: 'Collapse All Cut Tags',
            expand: 'Expand All Cut Tags',
            expanding: 'Expanding All Cut Tags'
        },
        image_style: {
            enabled: "border: 0;",
            disabled: "border: 0; opacity: 0.4; filter: alpha(opacity=40); zoom: 1;"
        }
    },
    _create: function() {
        var self = this;
        var cuttags = $("span.cuttag");

        if ( cuttags.size() == 0 ) return;

        self.update();
    },
    update: function() {
        var self = this;
        self.element.empty();

        var cuttags = $("span.cuttag");

        var aria_open = "";
        var aria_closed = "";

        cuttags.each(function (_,element) {
            var el = $(element).data("cuttag");
            if ( el.isOpen() ) {
                aria_open += " div-cuttag_" + el.identifier;
            } else {
                aria_closed += " div-cuttag_" + el.identifier;
            }
        });

        var el_exp = $("<img>", {
            alt: self.config.text.expand,
            title: self.config.text.expand,
            src: Site.imgprefix + "/collapseAll.gif",
            style: aria_closed ? self.config.image_style.enabled : self.config.image_style.disabled
        });

        if ( isExpandingAll ) {
            el_exp.attr("src",Site.imgprefix + "/ajax-loader.gif");
            el_exp.attr("style",self.config.image_style.enabled);
            el_exp.attr("title",self.config.text.expanding);
            el_exp.attr("alt",self.config.text.expanding);
        }

        if ( aria_closed ) {
            var a_exp = $("<a>",{
                'aria-controls': aria_closed,
            });
            a_exp.append(el_exp);
            el_exp = a_exp;

            a_exp.click(function() {
                isExpandingAll = 1;
                var cuttags = $("span.cuttag");
                cuttags.each(function (_,element) {
                    $(element).data("cuttag").open();
                });
            });
        }
        self.element.append(el_exp);

        var el_col = $("<img>", {
            alt: self.config.text.collapse,
            title: self.config.text.collapse,
            src: Site.imgprefix + "/expandAll.gif",
            style: aria_open ? self.config.image_style.enabled : self.config.image_style.disabled
        });
        if ( aria_open ) {
            var a_col = $("<a>",{
                'aria-controls': aria_open,
            });
            a_col.append(el_col);
            el_col = a_col;
            a_col.click(function() {
                isExpandingAll = 0;
                to_do = 1;
                cuttags.each(function (_,element) {
                    var widget = $(element).data("cuttag");
                    if ( widget )
                        widget.close();
                });
            });
        }
        self.element.append(el_col);
    }
});

$.extend( $.dw.cuttag_controls, {
    initControls: function() {
        var controls = $(".cutTagControls");

        controls.each(function (_,element) {
            $(element).cuttag_controls();
        });
    },
    updateAll: function() {
        var controls = $(".cutTagControls");

        controls.each(function (_,element) {
            $(element).data("cuttag_controls").update();
        });
    }
});

$.extend( $.dw.cuttag, {
    initLinks: function(context) {
        var cuttags = $("span.cuttag",context);

        cuttags.each(function (_,element) {
            $(element).cuttag();
        });
    }
});

})(jQuery,Site);

jQuery(document).ready(function($) {
    $.dw.cuttag.initLinks(document);
    $.dw.cuttag_controls.initControls();
});
