LJWidgetIPPU_ContentFlagReporters = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::ContentFlagReporters";
    LJWidgetIPPU_ContentFlagReporters.superClass.init.apply(this, arguments);
  },

  onRefresh: function () {
    var banbtn = $('banreporters');
    if (! banbtn ) return;

    DOM.addEventListener(banbtn, 'click', this.banChecked.bindEventListener(this));
    DOM.addEventListener($('banreporters_cancel'), 'click', this.cancel.bindEventListener(this));
    DOM.addEventListener($('banreporters_do'), 'click', this.ban.bindEventListener(this));
  },

  cancel: function (e) {
    this.close();
  },

  ban: function (e) {
    this.postForm($('banreporters_form'));
  },

  banChecked: function (e) {
    $('banreporters_do').disabled = ! $('banreporters').checked;
  },

  // post finished
  onData: function (data) {
    if (! data.res || ! data.res.banned) return;
    var banned = data.res.banned;
    
    LJ_IPPU.showNote("Banned users: " + banned.join(', '));
    this.close();
  }
});
