LJProgressBar = new Class(ProgressBar, {
  init: function () {
    LJProgressBar.superClass.init.apply(this, arguments);

    this.containerClassName = "lj_progresscontainer";
    this.indefiniteClassName = "lj_progressindefinite";
    this.overlayClassName = "lj_progressoverlay";
  }
});
