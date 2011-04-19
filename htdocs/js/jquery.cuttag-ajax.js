(function($,Site) {

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
            e.stopPropagation();
            e.preventDefault();
            self.toggle();
        });

        self.element.css("display","inline");
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
        this.element.removeClass("cuttag-open");
        this._setArrow("/collapse.gif", this.config.text.expand);

        this.tag.div.empty();
        this.tag.div.css("display","none");
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

            $.dw.cuttag.initLinks(replaceDiv);
        }
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
});
