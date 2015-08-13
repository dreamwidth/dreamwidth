(function($){

$.widget("dw.dynamicpoll", {
    _init: function() {
        this._initForm();
        this._initResults();
    },
    _initResults: function() {
        var self = this;
        var $results = self.element.children(":not(form.LJ_PollForm)");
        if ( $results.length == 0 ) return;

        $results.find("a.LJ_PollAnswerLink").click(function(e){
            e.stopPropagation();
            e.preventDefault();

            var $clicked = $(this);
            var pollid = $clicked.attr("lj_pollid");
            var pollqid = $clicked.attr("lj_qid");

            if ( ! pollid || ! pollqid ) return;

            $clicked.ajaxtip() // init
            .ajaxtip("load", {
                endpoint: "poll",

                ajax : {
                    type: "POST",

                    data: {
                        pollid  : pollid,
                        pollqid : pollqid,
                        page    : $clicked.attr("lj_page"),
                        pagesize: $clicked.attr("lj_pagesize"),
                        action  : "get_answers"
                    },

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $clicked.ajaxtip( "error", data.error )
                        } else {
                            var pollid = data.pollid;
                            var pollqid = data.pollqid;
                            if ( ! pollid || ! pollqid ) {
                                $clicked.ajaxtip( "error", "Error fetching poll results." );
                            } else {
                                $clicked.ajaxtip( "close" );

                                var page = data.page;

                                var $pageEle;
                                var $answerEle;

                                if ( page ) {
                                    $pageEle = $clicked.closest("div.lj_pollanswer_paging");
                                    $answerEle = $pageEle.prev("div.lj_pollanswer");
                                } else {
                                    $pageEle = $("<div class='lj_pollanswer_paging'></div>");
                                    $answerEle = $("<div class='lj_pollanswer'></div>");

                                    $clicked.after($answerEle,$pageEle).hide();
                                }
                                $pageEle.html( data.paging_html || "" );
                                $answerEle.html( data.answer_html || "(No answers)" );


                                $answerEle.append("<div class='hideanswers'><p></p><a href='#'>Hide Answers</a></div>" );

                                $(".hideanswers").click(function(e2) {
                                    e2.stopPropagation();
                                    e2.preventDefault();
                                    $(this).closest(".lj_pollanswer")
                                        .siblings(".lj_pollanswer_paging").remove().end()
                                        .siblings(".LJ_PollAnswerLink").show().end()
                                        .remove();
                                });
                                $pageEle.trigger( "updatedcontent.poll" );
                                $answerEle.trigger( "updatedcontent.poll" );
                            }
                        }
                    }
                }
            });
        }).end()
        .filter(".respondents").children("a.LJ_PollRespondentsLink").click(function(e){
            e.stopPropagation();
            e.preventDefault();

            var $clicked = $(this);
            var pollid = $clicked.attr("lj_pollid");

            $clicked.ajaxtip() // init
            .ajaxtip("load", {
                endpoint: "poll",

                ajax : {
                    type: "POST",

                    data: {
                        pollid  : pollid,
                        action  : "get_respondents"
                    },

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $clicked.ajaxtip( "error", data.error )
                        } else {
                            $clicked.ajaxtip( "close" ).hide();
                            $clicked.closest("div").append(data.answer_html);
                            $clicked.closest("div").parent().trigger( "updatedcontent.poll" );
                        }
                    }
                }
            });

        }).end().end()
        .filter("a.LJ_PollChangeLink").click(function(e){
            e.stopPropagation();
            e.preventDefault();

            var $clicked = $(this);
            $clicked.ajaxtip() // init
            .ajaxtip( "load", {
                endpoint: "pollvote",
                ajax: {
                    context: self,

                    type: "POST",
                    data: { action: "change",
                            pollid: $clicked.attr('lj_pollid')},

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $clicked.ajaxtip( "error", data.error )
                        } else {
                            $clicked.ajaxtip( "close" );
                            this.element.html(data.results_html)
                                .trigger( "updatedcontent.poll" );
                        }
                    }
                }
            });
        }).end();

        $("a.LJ_PollUserAnswerLink").click(function(e){
            e.stopImmediatePropagation();
            e.preventDefault();

            var $clicked = $(this);

            var pollid = $clicked.attr("lj_pollid");
            var userid = $clicked.attr("lj_userid");

            if ( ! pollid || ! userid ) return;

            if ( $clicked.prop('innerHTML') === "[-]" ) {
                $clicked.siblings(".useranswer").remove()
                    .end().siblings(".polluser").show();
                $clicked.html("[+]");
            } else {
                $clicked.ajaxtip() // init
                .ajaxtip( "load", {
                    endpoint: "poll",

                    ajax: {
                        type: "POST",

                        data: {
                            pollid  : pollid,
                            userid  : userid,
                            action  : "get_user_answers"
                        },

                        success: function( data, status, jqxhr ) {
                            if ( data.error ) {
                                $clicked.ajaxtip( "error", data.error )
                            } else {
                                var pollid = data.pollid;
                                var userid = data.userid;
                                if ( ! pollid || ! userid ) {
                                    $clicked.ajaxtip( "error", "Error fetching poll results." );
                                } else {
                                    $clicked.ajaxtip( "close" );

                                    $clicked.html("[-]");
                                    $clicked.siblings(".polluser").hide()
                                        .closest("div").append(data.answer_html);
                                }
                            }
                        }
                    }
                });
            }
        });

    },
    _initForm: function() {
        var self = this;
        var $poll = self.element.children("form.LJ_PollForm");
        if ( $poll.length == 0 ) return;

        $poll.find("input.LJ_PollSubmit").click(function(e){
            e.preventDefault();
            e.stopPropagation();

            var dataarray = new Array();
            dataarray = $poll.serializeArray();
            dataarray.push({'name': 'action', 'value': "vote"});
            var $submit = $(this);

            $submit.ajaxtip() // init
            .ajaxtip("load", {
                endpoint: "pollvote",

                ajax: {
                    context: self,

                    type: "POST",
                    data: dataarray,

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $submit.ajaxtip( "error", data.error )
                        } else {
                            $submit.ajaxtip( "close" );
                            this.element.html(data.results_html)
                                .trigger( "updatedcontent.poll" );
                        }
                    }
                }
            });
        }).end()
        .find("a.LJ_PollClearLink").click(function(e){
            e.stopPropagation();
            e.preventDefault();

            $poll.find("input").each(function(){
                if ( this.type == "text" )
                    this.value = "";
                else if ( this.type == "radio" || this.type == "checkbox" )
                    this.checked = false;
                // don't touch hidden and submit
            });
            $poll.find("select").each(function() { this.selectedIndex = 0 });
        }).end()
        .find("a.LJ_PollDisplayLink").click(function(e){
            e.stopPropagation();
            e.preventDefault();

            var $clicked = $(this);
            $clicked.ajaxtip() // init
            .ajaxtip("load", {
                endpoint: "pollvote",

                ajax: {
                    context: self,

                    type: "POST",
                    data: { action: "display",
                            pollid: $clicked.attr('lj_pollid')},

                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $clicked.ajaxtip( "error", data.error )
                        } else {
                            $clicked.ajaxtip( "close" );
                            this.element.html(data.results_html)
                                .trigger( "updatedcontent.poll" );
                        }
                    }
                }
            });
    });


    }
});

})(jQuery);

jQuery(document).ready(function($){
    $(".poll-container").dynamicpoll()
    $(document.body).delegate("*", "updatedcontent.entry.poll", function(e) {
        e.stopPropagation();
        $(this).find(".poll-container").andSelf().dynamicpoll();
    });
});

  
// ADAM's ADDITIONS
   
$('head').append('<link rel="stylesheet" type="text/css" href="//code.jquery.com/ui/1.11.4/themes/smoothness/jquery-ui.css">');
$('head').append('<style>\
  #sortable1, #sortable2 {\
    border: 1px solid #eee;\
    width: 142px;\
    min-height: 20px;\
    list-style-type: none;\
    margin: 0;\
    padding: 5px 0 0 0;\
    float: left;\
    margin-right: 10px;\
  }\
  #sortable1 li, #sortable2 li {\
    margin: 0 5px 5px 5px;\
    padding: 5px;\
    font-size: 1.2em;\
    width: 120px;\
  }\
  </style>');
$.getScript("//code.jquery.com/ui/1.11.4/jquery-ui.js", function(){
    $( "ul.sortable" ).sortable({
      connectWith: "ul"
    });
 
 
    $( "#sortable1, #sortable2" ).disableSelection();
  });