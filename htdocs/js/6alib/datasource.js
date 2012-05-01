// datasource base class, the "M" in MVC
// subclass this and override theData to provide your data

DataSource = new Class(Object, {

  init: function (initialData) {
    if ( DataSource.superClass.init )
        DataSource.superClass.init.apply(this, arguments);
    this.watchers = [];
    this.theData = defined(initialData) ? initialData : [];
    this.sortField = "";
    this.sortType = "";
    this.sortDesc = false;
  },

  addWatcher: function (callback) {
    this.watchers.add(callback);
  },

  removeWatcher: function (callback) {
    this.watchers.remove(callback);
  },

  // call this if updating data and not using _setData
  _updated: function () {
    this.callWatchers();
  },

  callWatchers: function () {
    for (var i = 0; i < this.watchers.length; i++)
      this.watchers[i].apply(this, [this.data()]);
  },

  setData: function (theData) {
    this.theData = theData;

    if (this.sortField)
      this.sortDataBy(this.sortField, this.sortType, this.sortDesc);

    this._setData(theData);
  },

  _setData: function (theData) {
    this.theData = theData;
    this.callWatchers();
    return theData;
  },

  data: function () {
    return this.theData;
  },

  sortBy: function () {
    return this.sortField;
  },

  sortInverted: function () {
    return this.sortDesc;
  },

  // mimic some array functionality
  push: function (data) {
    this.theData.push(data);
    this.callWatchers();
  },

  pop: function () {
    var val = this.theData.pop();
    this.callWatchers();
    return val;
  },

  indexOf: function (value) {
    return this.theData.indexOf(value);
  },

  remove: function (value) {
    this.theData.remove(value);
    this.callWatchers();
  },

  empty: function () {
    this.theData = [];
    this.callWatchers();
  },

  length: function () {
    return this.theData.length;
  },

  totalLength: function () {
    return this.allData().length;
  },

  allData: function () {
    var theData = this.theData;

    if (this.dataField && theData)
      theData = theData[this.dataField];

    return theData;
  },

  sortDataBy: function (field, type, invert) {
    this.sortField = field;
    this.sortDesc = invert;
    this.sortType = type;

    if (!field || !this.theData || !this.theData.sort)
      return;

    var sorted = this.theData.sort(function (a, b) {
      var ad = a[""+field], bd = b[""+field];
      ad = ad ? ad : "";
      bd = bd ? bd : "";

      switch(type) {

      case "string":
        var aname = ad.toUpperCase(), bname = bd.toUpperCase();

        if (aname < bname)
          return -1;
        else if (aname > bname)
          return 1;
        else
          return 0;

      case "isodate":
        var datA = Date.fromISOString(ad) || new Date(0);
        var datB = Date.fromISOString(bd) || new Date(0);

        return ((datA - datB) || 0);

      default:
      case "numeric":
        return ad - bd;

      }
    });

    if (invert)
      sorted.reverse();

    this._setData(sorted);
  }

});
