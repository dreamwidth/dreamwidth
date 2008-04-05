// This is for the ESN manage pages. It handles showing and hiding of the
// correct fields for event arg1 and arg2s

ESNManager = new Class(Object, {
  init: function (etypeids) {
    ESNManager.superClass.init.apply(this, arguments);

    if (!etypeids)
      etypeids = [];

    this.etypeids = etypeids;
    this.hideAllFields();
  },

  hideAllFields: function () {
    var etypeids = this.etypeids;
    if (!etypeids)
      return;

    for (var i=0; i < etypeids.length; i++) {
      var field = $("argOptsContainer" + etypeids[i]);
      if (!field) continue;

      field.style.display = "none";
    }
  },

  show: function (etypeid) {
    this.hideAllFields();
    if (!etypeid) return;
    var field = $("argOptsContainer" + etypeid);
    if (!field) return;
    field.style.display = "block";
  }
});
