function lastfm_current ( username, show_error ) {
    document.getElementById('prop_current_music').value = show_error ? "Running, please wait..." : "";

    var req = { method : "POST", 
        data : HTTPReq.formEncoded({ "username" : username }),
        url : "/tools/endpoints/lastfm_current_track.bml",
        onData : function (info) { import_handle(info, show_error) },
        onError : import_error
    };
    HTTPReq.getJSON(req);
};

var jobstatus;
var timer;

function import_handle(info, show_error) {
    if (info.error) {
        document.getElementById('prop_current_music').value = info.error;
        return import_error(info.error);
    }

    if (info.handle) {
        jobstatus = new JobStatus(info.handle, function (info) { got_track(info, show_error) } );
        timer = window.setInterval(jobstatus.updateStatus.bind(jobstatus), 1500);
    } else if (show_error) {
        document.getElementById('prop_current_music').value = "TODO: Gearman no job. Please run";
        import_error('TODO: Gearman no job. Please run.');
    }

    done = 0; // If data already received or not
};

function got_track (info, show_error) {
    if (info.running) {
    } else {
        window.clearInterval(timer);

        if (info.status == "success") {
            if (done)
                return;

            done = 1;

            eval('var result = ' + info.result);
            if (result.error) {
                document.getElementById('prop_current_music').value = '';
                if (show_error) {
                    LiveJournal.ajaxError(result.error);
                }
            } else {
                document.getElementById('prop_current_music').value = result.data;
            }
        } else {
            document.getElementById('prop_current_music').value = '';
            if (show_error) {
                LiveJournal.ajaxError('Failed to receive track from Last.fm.');
            }
        }
    }
}

function import_error(msg) {
    LiveJournal.ajaxError(msg);
}

