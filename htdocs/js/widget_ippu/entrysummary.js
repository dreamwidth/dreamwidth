LJWidgetIPPU_EntrySummary = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::EntrySummary";
    LJWidgetIPPU_ContentFlagReporters.superClass.init.apply(this, arguments);
  },

  onRefresh: function () {
    var cancelBtn = $('entrysummary_cancel');
    if (! cancelBtn) return;

    DOM.addEventListener(cancelBtn, 'click', this.cancel.bindEventListener(this));
  },

  cancel: function (e) {
    this.close();
  }
});
