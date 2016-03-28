(function($,Site) {

var isExpandingAll = 0;

var loadPending = 0;

// Test for SVG support from
// http://stackoverflow.com/questions/654112/how-do-you-detect-support-for-vml-or-svg-in-a-browser
// If we expand SVG usage on the site this function should get
// pulled out of this file.
function supportsSVG() {
            return !!document.createElementNS 
         && !!document.createElementNS('http://www.w3.org/2000/svg', "svg").createSVGRect
         // FF 3.6.8 supports SVG but not inline
         && !isOldFirefox();
}

function isOldFirefox () {
           // check for 3.6.8 or older (hardware limitations cap some users here)
           return !!(jQuery.browser.mozilla && jQuery.browser.version < '1.9.3')
}

if ( supportsSVG() ) {
        var collapse_img        = "/collapse.svg";
        var expand_img          = "/expand.svg";
        var collapseall_img     = "/collapseAll.svg";
        var expandall_img       = "/expandAll.svg";
        var ajaxloader_img      = "/ajax-loader.gif";
        var collapseend_img     = "/collapse-end.svg";
} else {
        var collapse_img        = "/collapse.gif";
        var expand_img          = "/expand.gif";
        var collapseall_img     = "/collapseAll.gif";
        var expandall_img       = "/expandAll.gif";
        var ajaxloader_img      = "/ajax-loader.gif";
        var collapseend_img     = "/collapse-end.gif";
}

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
            "class": "cuttag-action cuttag-action-before"
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

        self._setArrow(collapse_img, self.config.text.expand);

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
        return this.tag.div.hasClass("cuttag-open") ? 1 : 0;
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
        self._setArrow(ajaxloader_img, self.config.text.loading);
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
        this.tag.div.removeClass("cuttag-open");
        this._setArrow(collapse_img, this.config.text.expand);

        this.tag.div.empty();
        this.tag.div.css("display","none");

        $.dw.cuttag_controls.updateAll();
    },
    _setArrow: function(path,str) {
        var i = this.tag.img;
        i.attr("src",Site.imgprefix + path);
        i.attr("alt",str);
        i.attr("title",str);
        i.attr("style","max-width: 100%; width: 1.0em; padding: 0.2em;");
    },
    handleError: function(error) {
        this._setArrow(collapse_img, this.config.text.expand);
        alert(error);
    },
    replaceCutTag: function(resObj) {
        var self = this;
        if ( resObj.error ) {
            self._setArrow(collapse_img, self.config.text.expand);
        } else {
            var replaceDiv = self.tag.div;
            replaceDiv.html(resObj.text)
                .css("display","block").addClass("cuttag-open");

            var closeEnd = $("<span>");
            var a = $("<a>",{
                href: "#cuttag_" + self.identifier,
                "class": "cuttag-action cuttag-action-after"
            });
            var img = $("<img>",{
                style: "border: 0; max-width: 100%; width: 1.0em; padding: 0.2em;",
                src: Site.imgprefix + collapseend_img,
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
                $("html,body").animate({scrollTop: self.element.offset().top - 10});
                self.toggle();
            });

            self._setArrow(expand_img, self.config.text.collapse);

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
        var cuttags = $("span.cuttag[id]");

        if ( cuttags.size() == 0 ) return;

        self.update();
    },
    update: function() {
        var self = this;
        self.element.empty();

        var cuttags = $("span.cuttag[id]");

        var aria_open = "";
        var aria_closed = "";

        cuttags.each(function (_,element) {
            var el = $(element).data("dw-cuttag");
            if ( el.isOpen() ) {
                aria_open += " div-cuttag_" + el.identifier;
            } else {
                aria_closed += " div-cuttag_" + el.identifier;
            }
        });

        var el_exp = $("<img>", {
            alt: self.config.text.expand,
            title: self.config.text.expand,
            src: Site.imgprefix + collapseall_img,
            style: aria_closed ? self.config.image_style.enabled : self.config.image_style.disabled
        });

        if ( isExpandingAll ) {
            el_exp.attr("src",Site.imgprefix + ajaxloader_img);
            el_exp.attr("style",self.config.image_style.enabled);
            el_exp.attr("title",self.config.text.expanding);
            el_exp.attr("alt",self.config.text.expanding);
        }

        if ( aria_closed ) {
            var a_exp = $("<a>",{
                'aria-controls': aria_closed
            });
            a_exp.append(el_exp);
            el_exp = a_exp;

            a_exp.click(function() {
                isExpandingAll = 1;
                var cuttags = $("span.cuttag[id]");
                cuttags.each(function (_,element) {
                    $(element).data("dw-cuttag").open();
                });
            });
        }
        self.element.append(el_exp);

        var el_col = $("<img>", {
            alt: self.config.text.collapse,
            title: self.config.text.collapse,
            src: Site.imgprefix + expandall_img,
            style: aria_open ? self.config.image_style.enabled : self.config.image_style.disabled
        });
        if ( aria_open ) {
            var a_col = $("<a>",{
                'aria-controls': aria_open
            });
            a_col.append(el_col);
            el_col = a_col;
            a_col.click(function() {
                isExpandingAll = 0;
                to_do = 1;
                cuttags.each(function (_,element) {
                    var widget = $(element).data("dw-cuttag");
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
            $(element).data("dw-cuttag_controls").update();
        });
    }
});

$.extend( $.dw.cuttag, {
    initLinks: function(context) {
        var cuttags = $("span.cuttag[id]",context);

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
