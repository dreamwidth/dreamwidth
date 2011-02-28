LJWidget = new Class(Object, {
    // replace the widget contents with an ajax call to render with params
    updateContent: function (params) {
        if (! params) params = {};
        this._show_frame = params["showFrame"];

        if ( params["method"] ) method = params["method"];
        params["_widget_update"] = 1;

        if (this.doAjaxRequest(params)) {
            // hilight the widget to show that its updating
            this.hilightFrame();
        }
    },

    // returns the widget element
    getWidget: function () {
        return $(this.widgetId);
    },

    // do a simple post to the widget
    doPost: function (params) {
        if (! params) params = {};
        this._show_frame = params["showFrame"];
        var postParams = {};

        var classPrefix = this.widgetClass;
        classPrefix = "Widget[" + classPrefix.replace(/::/g, "_") + "]_";

        for (var k in params) {
            if (! params.hasOwnProperty(k)) continue;

            var class_k = k;
            if (! k.match(/^Widget\[/) && k != 'lj_form_auth' && ! k.match(/^_widget/)) {
                class_k = classPrefix + k;
            }

            postParams[class_k] = params[k];
        }

        postParams["_widget_post"] = 1;

        this.doAjaxRequest(postParams);
    },

    doPostAndUpdateContent: function (params) {
        if (! params) params = {};

        params["_widget_update"] = 1;

        this.doPost(params);
    },

    // do an ajax post of the form passed in
    postForm: function (formElement) {
      if (! formElement) return false;

      var params = {};

      for (var i=0; i < formElement.elements.length; i++) {
        var element = formElement.elements[i];
        var name = element.name;
        var value = element.value;

        params[name] = value;
      }

      this.doPost(params);
    },

    ///////////////// PRIVATE METHODS ////////////////////

    init: function (id, widgetClass, authToken) {
        if ( LJWidget.superClass.init )
            LJWidget.superClass.init.apply(this, arguments);
        this.widgetId = id;
        this.widgetClass = widgetClass;
        this.authToken = authToken;
    },

    hilightFrame: function () {
        if (this._show_frame != 1) return;
        if (this._frame) return;

        var widgetEle = this.getWidget();
        if (! widgetEle) return;

        var widgetParent = widgetEle.parentNode;
        if (! widgetParent) return;

        var enclosure = document.createElement("fieldset");
        enclosure.style.borderColor = "red";
        var title = document.createElement("legend");
        title.innerHTML = "Updating...";
        enclosure.appendChild(title);

        widgetParent.appendChild(enclosure);
        enclosure.appendChild(widgetEle);

        this._frame = enclosure;
    },

    removeHilightFrame: function () {
        if (this._show_frame != 1) return;

        var widgetEle = this.getWidget();
        if (! widgetEle) return;

        if (! this._frame) return;

        var par = this._frame.parentNode;
        if (! par) return;

        par.appendChild(widgetEle);
        par.removeChild(this._frame);

        this._frame = null;
    },

    method: "POST",
    endpoint: "widget",
    requestParams: {},

    doAjaxRequest: function (params) {
        if (! params) params = {};

        if (this._ajax_updating) return false;
        this._ajax_updating = true;

        params["_widget_id"]     = this.widgetId;
        params["_widget_class"]  = this.widgetClass;

        params["auth_token"]  = this.authToken;

        if ($('_widget_authas')) {
            params["authas"] = $('_widget_authas').value;
        }

        var reqOpts = {
            method:  this.method,
            data:    HTTPReq.formEncoded(params),
            url:     LiveJournal.getAjaxUrl(this.endpoint),
            onData:  this.ajaxDone.bind(this),
            onError: this.ajaxError.bind(this)
        };

        for (var k in params) {
          if (! params.hasOwnProperty(k)) continue;
          reqOpts[k] = params[k];
        }

        HTTPReq.getJSON(reqOpts);

        return true;
    },

    ajaxDone: function (data) {
        this._ajax_updating = false;
        this.removeHilightFrame();

        if (data.auth_token) {
            this.authToken = data.auth_token;
        }

        if (data.errors && data.errors != '') {
            return this.ajaxError(data.errors);
        }

        if (data.error) {
            return this.ajaxError(data.error);
        }

        // call callback if one exists
        if (this.onData) {
             this.onData(data);
        }

        if (data["_widget_body"]) {
            // did an update request, got the new body back
            var widgetEle = this.getWidget();
            if (! widgetEle) {
              // widget is gone, ignore
              return;
            }

            widgetEle.innerHTML = data["_widget_body"];

            if (this.onRefresh) {
                this.onRefresh();
            }
        }
    },

    ajaxError: function (err) {
        this._ajax_updating = false;

        if (this.onError) {
            // use class error handler
            this.onError(err);
        } else {
            // use generic error handler
            LiveJournal.ajaxError(err);
        }
    }
});

LJWidget.widgets = [];
