vcl 4.0;

backend default {
    .host = "127.0.0.1";
    .port = "80";
}

sub vcl_recv {
    # Newer versions of Apache disallow underscores in hostnames; handle
    # these with synthetic redirect response via status 750 and x-redir header.
    if (req.http.host ~ "_") {
        set req.http.x-redir = "https://" + regsuball(req.http.host, "_", "-") + req.url;
        return(synth(750, ""));
    }
}

sub vcl_synth {
    if (resp.status == 750) {
        # Status 750 = synthetic redirect
        set resp.status = 302;
        set resp.http.Location = req.http.x-redir;
        return(deliver);
    }
}
