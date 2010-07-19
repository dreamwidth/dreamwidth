LJWidgetIPPU = new Class(LJWidget, {
    init: function (opts, reqParams) {
        var title = opts.title;
        var widgetClass = opts.widgetClass;
        var authToken = opts.authToken;
        var nearEle = opts.nearElement;

        if (! reqParams) reqParams = {};
        this.reqParams = reqParams;

        // construct a container ippu for this widget
        var ippu = new LJ_IPPU(title, nearEle);
        this.ippu = ippu;
        var c = document.createElement("div");
        c.id = "LJWidgetIPPU_" + Unique.id();
        ippu.setContentElement(c);

        if (opts.width && opts.height)
          ippu.setDimensions(opts.width, opts.height);

        if (opts.overlay) {
            if (IPPU.isIE()) {
                this.ippu.setModal(true);
                this.ippu.setOverlayVisible(true);
                this.ippu.setClickToClose(false);
            } else {
                this.ippu.setModal(true);
                this.ippu.setOverlayVisible(true);
            }
        }

        if (opts.center) ippu.center();
        ippu.show();

        var loadingText = document.createElement("div");
        loadingText.style.fontSize = '1.5em';
        loadingText.style.fontWeight = 'bold';
        loadingText.style.margin = '5px';
        loadingText.style.textAlign = 'center';

        loadingText.innerHTML = "Loading...";

        this.loadingText = loadingText;

        c.appendChild(loadingText);

        // id, widgetClass, authToken
        var widgetArgs = [c.id, widgetClass, authToken]
        LJWidgetIPPU.superClass.init.apply(this, widgetArgs);

        if (!widgetClass)
            return null;

        this.widgetClass = widgetClass;
        this.authToken = authToken;
        this.title = title;
        this.nearEle = nearEle;

        window.setInterval(this.animateLoading.bind(this), 20);

        this.loaded = false;

        // start request for this widget now
        this.loadContent();
    },

    animateCount: 0,

    animateLoading: function (i) {
      var ele = this.loadingText;

      if (this.loaded || ! ele) {
        window.clearInterval(i);
        return;
      }

      this.animateCount += 0.05;
      var intensity = ((Math.sin(this.animateCount) + 1) / 2) * 255;
      var hexColor = Math.round(intensity).toString(16);

      if (hexColor.length == 1) hexColor = "0" + hexColor;
      hexColor += hexColor + hexColor;

      ele.style.color = "#" + hexColor;
      this.ippu.center();
    },

    // override doAjaxRequest to add _widget_ippu = 1
    doAjaxRequest: function (params) {
      if (! params) params = {};
      params['_widget_ippu'] = 1;
      LJWidgetIPPU.superClass.doAjaxRequest.apply(this, [params]);
    },

    close: function () {
      this.ippu.hide();
    },

    loadContent: function () {
      var reqOpts = this.reqParams;
      this.updateContent(reqOpts);
    },

    method: "POST",

    // request finished
    onData: function (data) {
      this.loaded = true;
    },

    render: function (params) {

    }
});
