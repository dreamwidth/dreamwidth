LJWidgetIPPU_SettingProd = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::SettingProd";
    this.width = opts.width; // Use for resizing later
    this.height = opts.height; // Use for resizing later
    this.setting = params.setting;
    this.field = params.field;
    opts.overlay = true;
    if ( LJWidgetIPPU_SettingProd.superClass.init )
        LJWidgetIPPU_SettingProd.superClass.init.apply(this, arguments);
  },

  updatesettings: function (evt, form) {
    var setting_key = form["Widget[IPPU_SettingProd]_setting_key"].value + "";
    var field = "LJ__Setting__"+this.setting+"_"+this.field;
    var post = new Object();
    post['lj_form_auth'] = form["lj_form_auth"].value + "";
    post['setting'] = this.setting;
    if (form[field].type == 'checkbox') {
      if (form[field].checked)
        post[field] = form[field].value;
      this.doPost(post);
    } else {
      post[field] = form[field].value + "";
      if (post[field] && post[field] != "") this.doPost(post);
    }

    Event.stop(evt);
  },

  onData: function (data) {
    var success;
    var extra = '';
    if (data.res && data.res.success) success = data.res.success;
    if (data.res && data.res.extra) extra = data.res.extra;
    if (success) {
      LJ_IPPU.showNote("Settings updated."+extra);
      this.ippu.hide();
    }
  },

  onError: function (msg) {
    LJ_IPPU.showErrorNote("Error: " + msg);
  },

  onRefresh: function () {
    var self = this;
    var form = $("settingprod_form");
    DOM.addEventListener(form, "submit", function(evt) { self.updatesettings(evt, form) });
  },

  cancel: function (e) {
    this.close();
  }
});
