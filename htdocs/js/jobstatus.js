/* This is a library for querying an asychronous task's progress or result */
JobStatus = new Class(Object, {
    init: function (handle, statusCallback) {
        if (! handle) return null;

        this.handle = handle;
        this.statusCallback = statusCallback;
        this.updateStatus();
    },

    updateStatus: function () {
        var params = {taskhandle: this.handle};

        var opts = {
            url: LiveJournal.getAjaxUrl("jobstatus"),
            method: "POST",
            data: HTTPReq.formEncoded(params),
            onData: this.gotData.bind(this),
            onError: this.gotError.bind(this)
        };
        HTTPReq.getJSON(opts);
    },

    gotData: function (res) {
        if (res.error) return gotError(res.error);
        this.statusCallback(res);
    },

    gotError: function (err) {
        LiveJournal.ajaxError(err);
    }
});
