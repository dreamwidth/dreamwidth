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
    var targetParts = data.target.split("-");
    if ( targetParts.length === 1 ) {
        data.dtid = data.target;
    } else {
        data.dtid = 0;
        $("#journal").val(targetParts[1]);
        $("#itemid").val(targetParts[2]);
    }

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

    $("#qrdiv").show().css("display", "inline").appendTo(widget);
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
        target: undefined,
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
        return this.options.target ? $("#ljqrt"+this.options.target) : [];
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

        $("#submitmoreopts, #submitpview, #submitpost").prop("disabled", true);

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

    $("#prop_picture_keyword").live("change", function(e) {
        e.stopPropagation();
        e.preventDefault();

        $(".qr-icon").find("img")
            .attr("src", $(this).find("option:selected").data("url"))
            .removeAttr("width").removeAttr("height").removeAttr("alt");
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


function quickreply(target, pid, newsubject, trigger) {
    trigger = trigger || document;

    $(trigger).quickreply({ target: target, pid: pid, subject: newsubject })
            .attr("onclick", null);
    return ! $.dw.quickreply.can_continue();
}
