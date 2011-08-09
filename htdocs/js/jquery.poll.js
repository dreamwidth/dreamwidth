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

            $clicked
            .ajaxtip({namespace: "pollanswer"})
            .ajaxtip("load", {
                endpoint: "poll",
                context: self,
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
                            $clicked.ajaxtip( "cancel" );

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

                    self._trigger( "complete" );
                },
                error: function( jqxhr, status, error ) {
                    $clicked.ajaxtip( "error", "Error contacting server. " + error);
                    self._trigger( "complete" );
                }
            });
        });
    },
    _initForm: function() {
        var self = this;
        var $poll = self.element.children("form.LJ_PollForm");
        if ( $poll.length == 0 ) return;

        $poll.find("input.LJ_PollSubmit").click(function(e){
            e.preventDefault();
            e.stopPropagation();

            var $submit = $(this);
            $submit.ajaxtip({namespace: "pollsubmit"})
                .ajaxtip("load", {
                    endpoint: "pollvote",
                    context: self,
                    data: $poll.serialize(),
                    success: function( data, status, jqxhr ) {
                        if ( data.error ) {
                            $submit.ajaxtip( "error", data.error )
                        } else {
                            $submit.ajaxtip( "cancel" );
                            var resultsEle = $(data.results_html);
                            self.element.empty().append(resultsEle);

                            resultsEle.trigger( "updatedcontent.poll" );
                        }
                        self._trigger( "complete" );
                    }
                });
        });

        $poll.find(".LJ_PollClearLink").click(function(e){
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
