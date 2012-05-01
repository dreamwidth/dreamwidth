// the V in MVC
// renders content into "view" element, calls data() on "datasource"

View = new Class(Object, {

  init: function (opts) {
    if ( View.superClass.init )
        View.superClass.init.apply(this, arguments);
    this.watchers = [];
    this.datasource = opts.datasource;
    this.view = opts.view;
    this.controller = opts.controller;

    this.rendered = false;

    if (opts.showHourglass) {
      this.hourglass = new Hourglass();
      this.hourglass.init(view);
    }

    if (opts.datasource)
      opts.datasource.addWatcher(this.dataUpdated.bind(this));
  },

  addWatcher: function (callback) {
    if (!this.watchers)
      return;

    this.watchers.add(callback);
  },

  removeWatcher: function (callback) {
    if (!this.watchers)
      return;

    this.watchers.remove(callback);
  },

  callWatchers: function () {
    if (!this.watchers)
      return;

    for (var i = 0; i < this.watchers.length; i++)
      this.watchers[i].apply(this);
  },

  getView: function () {
    return this.view;
  },

  dataUpdated: function () {
    this._render();

    if (this.hourglass) {
      this.hourglass.hide();
      this.hourglass = null;
    }
  },

  setContent: function (content) {
      if (this.view) {
          var children = this.view.childNodes;
          for (var i = 0; i < children.length; i++) {
              this.view.removeChild(children[i]);
          }
      }

      this.view.appendChild(content);
  },

  _render: function () {
    var ds = this.datasource;
    var view = this.view;

    if (!view)
      return;

    var data;

    if (ds) {
      data = ds.data();
      if (!this.rendered && this.unRender)
        this.unRender(data, ds);
    }

    if (this.render) {
      this.render(data, ds);
      this.rendered = true;
    }

    this.callWatchers();
  },

  destroy: function () {
    if (this.rendered)
      this.unRender();
  }

});
