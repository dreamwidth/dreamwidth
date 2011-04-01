(function($) {
var _ok;
var qrdiv;
var customsubject;
var previous;

function can_continue() {
    if ( _ok == undefined )
        _ok =
            ($("#parenttalkid,#replyto,#dtid,#qrdiv,#qrformdiv,#qrform,#subject").length == 7);
    return _ok;
}

function update(data,widget) {
    $("#parenttalkid, #replyto").val(data.pid);
    $("#dtid").val(data.dtid);
    
    var old_subject;
    if ( previous ) {
        old_subject = previous.subject;
        previous.widget.hide();
    }
    
    var subject = $("#subject");
    var cur_subject = subject.val();

    if ( old_subject != undefined && cur_subject != old_subject ) 
        customsubject = true;
    if ( ! customsubject || cur_subject == "" )
        subject.val(data.subject);

    $("#qrdiv").show().appendTo(widget);
    widget.show();
    $("#body").focus();
    
    previous = {
        subject: data.subject,
        widget: widget
    };
};

$.widget("dw.quickreply", {
    options: {
        dtid: undefined,
        pid: undefined,
        subject: undefined
    },
    _create: function() {
        var self = this;
        self.element.click(function(e){
            if ( ! can_continue() ) return;
            e.stopPropagation();
            e.preventDefault();
            update(self.options, self.widget())
        }).click();
    },
    widget: function() {
        return this.options.dtid ? $("#ljqrt"+this.options.dtid) : [];
    }
});

$.extend( $.dw.quickreply, {
    can_continue: function() { return _ok; }
} );

})(jQuery);

jQuery(document).ready(function($) {
    function submitform(e) {
        e.preventDefault();
        e.stopPropagation();

        $("#submitmoreopts, #submitpview, #submitpost").attr("disabled", "disabled");

        var dtid = $("#dtid");
        if ( ! Number(dtid.val()) )
            dtid.val("0");

        $("#qrform")
            .attr("action", Site.siteroot + "/talkpost_do" )
            .submit();
    }

    $("#submitpview").live("click", function(e){
        $("#qrform input[name='submitpreview']").val(1);
        submitform(e);
    });
    $("#submitpost").live("click", function(e){
        var maxlength = 16000;
        var length = $("#body").val().length;
        if ( length > maxlength ) {
            alert("Sorry, but your comment of " + length + " characters exceeds the maximum character length of " + maxlength + ". Please try shortening it and then post again");

            e.stopPropagation();
            e.preventDefault();
        } else {
            submitform(e);
        }
    });
    $("#submitmoreopts").live("click", function(e) {
        var replyto = Number($("#dtid").val());
        var pid = Number($("#parenttalkid").val());
        var basepath = $("#basepath").val();

        e.stopPropagation();
        e.preventDefault();

        if(replyto > 0 && pid > 0) {
            $("#qrform").attr("action", basepath + "replyto=" + replyto );
        } else {
            $("#qrform").attr("action", basepath + "mode=reply" );
        }

        $("#qrform").submit();
    });

    $("#randomicon").live("click", function(e){
        e.stopPropagation();
        e.preventDefault();

        var iconslist = $("#prop_picture_keyword").get(0);
        if ( !iconslist ) return;

        // take a random number, ignoring the "(default)" option
        var randomnumber = Math.floor(Math.random() * (iconslist.length-1) ) + 1;
        iconslist.selectedIndex = randomnumber;
    });
});


function quickreply(dtid, pid, newsubject, trigger) {
    trigger = trigger || document;
    $(trigger).quickreply({ dtid: dtid, pid: pid, subject: newsubject })
            .attr("onclick", null);
    return ! $.dw.quickreply.can_continue();
}
