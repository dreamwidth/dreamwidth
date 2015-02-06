(function($) {
    function _arrayToVal( array, ele ) {
        var tags_array = [];
        $.each( array, function(key) {
            tags_array.push( key );
        });

        ele.val( tags_array.join(",") );
    }

    // this doesn't act on the autocompletewithunknown widget. Instead, it's called on our input field with autocompletion
    function _handleComplete(e, ui, $oldElement) {
        var self = $(this).data("autocompletewithunknown");
        var ele = self.element;

        var curtagslist = self.cachemap[self.currentCache];

        var items = ui.item.value.toLowerCase();
        $.each( items.split(","), function() {
            var tag = $.trim(this);

            // check if the tag is empty, or if we had previously used it
            if ( tag == "" ) return;

            // TODO: don't put it in if the word exceeds the maximum length of a tag
            if ( ! self.tagslist[tag] ) {
                self.tagslist[tag] = true;


                var tokentype = curtagslist && curtagslist[tag] ? self.options.curTokenClass : self.options.newTokenClass;

                var $text = $("<span></span>")
                    .addClass(self.options.tokenTextClass)
                    .text(tag);
                var $a = $("<button class='fi-icon--with-fallback theme-color-on-hover'></button>").addClass(self.options.tokenRemoveClass).html("<span class='fi-icon fi-x' aria-hidden='true'></span>" +
                    "<span class='fi-icon--fallback'>Remove " + tag + "</span>");

                var $li = $("<li></li>").addClass(self.options.tokenClass + " " + tokentype)
                    .append($text).append($a).append(" ")
                    .attr( "title", tokentype == self.options.curTokenClass ? "tag: " + tag : "new tag: " + tag);
                if ( $oldElement )
                    $oldElement.replaceWith($li);
                else
                    $li.appendTo(self.uiAutocompletelist);
            }
        });

        $("#"+self.options.id+"_count_label").text("characters per tag:");
        $(this).val("");
        if ( self.options.grow ) {
            // shrink
            $(this).height((parseInt($(this).css('lineHeight').replace(/px$/,''), 10)||20) + 'px');
            if ( self.options.maxlength )
                $("#"+self.options.id+"_count").text(self.options.maxlength);
        }

        _arrayToVal(self.tagslist, ele)

        if ( $.browser.opera ) {
            var keyCode = $.ui.keyCode;
            if( e.which == keyCode.ENTER || e.which == keyCode.TAB )
                self.justCompleted = true;
        }

        // this prevents the default behavior of having the
        // form field filled with the autocompleted text.
        // Target the event type, to avoid issues with selecting using TAB
        if ( e.type == "autocompleteselect" ) {
            e.preventDefault();
            return false;
        }
    }

    $.widget("ui.autocompletewithunknown", {
            options: {
                id: null,
                tokenClass: "token",
                tokenTextClass: "token-text",
                tokenRemoveClass: "token-remove",
                newTokenClass: "new",
                curTokenClass: "autocomplete",
                numMatches: 20,
                populateSource: null, // initial location to populate from
                populateId: "",       // initial identifier for the list to be cached
                grow: false           // whether to automatically grow the autocomplete textarea or not
            },

            _filterTags: function( array, term ) {
                var self = this;
                var startsWithTerm = [];

                term = $.trim(term.toLowerCase());
                var matcher = new RegExp( $.ui.autocomplete.escapeRegex(term) );

                var filtered = $.grep( array, function(value) {
                            var val = value.label || value.value || value;
                            if ( !self.tagslist[val] && matcher.test( val ) )  {
                                if ( val.indexOf(term) == 0 ) {
                                    // ugly, but we'd like to handle terms that start with
                                    // in a different manner
                                    startsWithTerm.push({ value: val,
                                        label: val.replace(term, "<strong>"+term+"</strong>")});
                                    return false;
                                }
                                return true;
                            }
                        });

                // second step, because we first need to find out how many
                // total start with the term, and so need to be in the list
                // those that only contain the term fill in any remaining slots
                var responseArray = startsWithTerm.slice(0, self.options.numMatches);
                $.each(filtered, function(index, value) {
                    if ( responseArray.length >= self.options.numMatches )
                        return false;

                    responseArray.push({ value: value,
                        label: value.replace(term, "<strong>"+term+"</strong>")});
                })

                return responseArray;
            },

            _create: function() {
                var self = this;

                if (!self.options.id)
                    self.options.id = "autocomplete_"+self.element.attr("id");

                self.uiAutocomplete = self.element.wrap("<div class='autocomplete-container border'></div>").parent().attr("id", self.options.id).addClass(self.element.attr("class"));

                self.uiAutocompletelist = $("<ul class='autocomplete-list'></ul>").appendTo(self.uiAutocomplete).attr( "aria-live", "assertive" );

                // this is just frontend; will use JS to transfer contents to the original field (now hidden)
                self.uiAutocompleteInput = $("<textarea class='autocomplete-input' rows='1'></textarea>")
                        .appendTo(self.uiAutocomplete)
                        .data("autocompletewithunknown", self)
                        .focus(function(e) {
                            $(this).closest(".autocomplete-container").addClass("focus");
                        })
                        .blur(function(e) {
                            $(this).closest(".autocomplete-container").removeClass("focus");
                        });

                if ( self.options.grow ) {
                    self.uiAutocomplete.closest(".row").parent().find(".tagselector-controls")
                        .append("<div class='autocomplete-count-container right'><span id='"+self.options.id+"_count_label'>characters per tag:</span> <span id='"+self.options.id+"_count' class='autocomplete-count'>50</span></div>");
                    $(self.uiAutocompleteInput).vertigro(self.options.maxlength, self.options.id + "_count");
                }

                self.element.hide();

                self.tagslist = {};
                self.cache = {};
                self.cachemap = {};

                if ( self.options.populateSource )
                    self.populate(self.options.populateSource, self.options.populateId);

                self.uiAutocompleteInput.autocomplete({
                    source: function (request, response) {
                        if ( self.cache[self.currentCache] != null )
                            return response( self._filterTags( self.cache[self.currentCache], request.term ) );
                    },
                    autoFocus: true,
                    select: _handleComplete
                }).bind("keydown.autocompleteselect", function( event ) {
                    var keyCode = $.ui.keyCode;
                    var $input = $(this);

                    $("#"+self.options.id+"_count_label").text("characters left:");

                    switch( event.which ) {
                        case keyCode.ENTER:
                            _handleComplete.apply( $input,
                                    [event, { item: { value: $input.val() } } ]);
                            self.justCompleted = true;
                            $input.autocomplete("close");
                            event.preventDefault();

                            return;
                        case keyCode.TAB:
                            if ($input.val()) {
                                _handleComplete.apply( $input,
                                    [event, { item: { value: $input.val() } } ]);
                                self.justCompleted = true;
                                event.preventDefault();
                            }
                            return;
                        case keyCode.BACKSPACE:
                            if( ! $input.val() ) {
                                $("."+self.options.tokenRemoveClass + ":last", self.uiAutocomplete).focus();
                                event.preventDefault();
                            }
                            return;
                    }
                }).bind("keyup.autocompleteselect", function( event ) {
                    var $input = $(this);
                    if ( $input.val().indexOf(",") > -1 )
                        _handleComplete.apply( $input, [event, { item: { value: $input.val() } } ]);
                }).change(function(event){
                    // if we have the menu open, let that handle the autocomplete
                    var $menu = $(this).data("ui-autocomplete").menu;
                    if ( $menu.element.is(":visible") ) return;

                    _handleComplete.apply( $(this), [event, { item: { value: $(event.currentTarget).val() } } ]);

                    // workaround for autocompleting with TAB in opera
                    if ( $.browser.opera && self.justCompleted ) {
                        $(this).focus();
                        self.justCompleted = false;
                    }
                })
                .data("ui-autocomplete")._renderItem = function( ul, item ) {
                        return $( "<li></li>" )
                            .data( "ui-autocomplete-item", item )
                            .append( "<a>" + item.label + "</a>" )
                            .appendTo( ul );
                };


                // so other things can reinitialize the widget with their own text
                $(self.element).bind("autocomplete_inittext", function( event, new_text ) {
                    self.tagslist = {};
                    self.uiAutocompletelist.empty();
                    _handleComplete.apply( self.uiAutocompleteInput, [ event, { item: { value: new_text } } ] );
                });
                $(self.element).trigger("autocomplete_inittext", self.element.val());

                // replace one text
                $(self.element).bind("autocomplete_edittext", function ( event, $element, new_text ) {
                    _handleComplete.apply( self.uiAutocompleteInput, [ event, { item: { value: new_text } }, $element ] );
                });

                $(".autocomplete-container").click(function() {
                    self.uiAutocompleteInput.focus();
                });

                $("span."+self.options.tokenTextClass, self.uiAutocomplete.get(0))
                .live("click", function(event) {
                    delete self.tagslist[$(this).text()];
                    _arrayToVal(self.tagslist, self.element);
                    var $input = $("<input type='text' />")
                        .addClass(self.options.tokenTextClass)
                        .val($(this).text())
                        .width($(this).width()+5);
                    $(this).replaceWith($input);
                    $input.focus();

                    event.stopPropagation();
                });

                $("input."+self.options.tokenTextClass,self.uiAutocomplete.get(0))
                .live("blur", function(event) {
                    $(self.element).trigger("autocomplete_edittext", [ $(this).closest("li"), $(this).val() ] );
                });

                $("."+self.options.tokenRemoveClass, self.uiAutocomplete.get(0)).live("click", function(e) {
                    var $token = $(this).closest("."+self.options.tokenClass);

                    delete self.tagslist[$token.children("."+self.options.tokenTextClass).text()];
                    _arrayToVal(self.tagslist, self.element);
                    $token.fadeOut(function() {$(this).remove()});

                    e.preventDefault();
                    e.stopPropagation();
                }).live("focus", function(event) {
                    $(this).parent().addClass("focus");
                }).live("blur", function(event) {
                    $(this).parent().removeClass("focus");
                }).live("keydown", function(event) {
                    if ( event.which == $.ui.keyCode.BACKSPACE ) {
                        event.preventDefault();
                        var $prevToken = $(this).closest("."+self.options.tokenClass).prev("."+self.options.tokenClass);
                        $(this).click();

                        if ($prevToken.length == 1)
                            $prevToken.find("."+self.options.tokenRemoveClass).focus();
                        else
                            self.uiAutocompleteInput.focus();
                    } else if (event.which != $.ui.keyCode.TAB) {
                        $(this).siblings("."+self.options.tokenTextClass).click();
                    }
                });

                // workaround for autocompleting with ENTER in opera
                self.justCompleted = false;
                $.browser.opera && $(self.element.get(0).form).bind("submit.autocomplete", function(e) {
                    // this tries to make sure that we don't try to validate crossposting, if we only hit enter
                    // to autocomplete. Workaround for opera.
                    // Sort of like a lock, to mark which handler last prevented the form submission.
                    // TODO: refactor this out into something that we're sure works. We are at the mercy
                    // of the way that Opera and other browsers order the handlers.
                    if ( self.element.data("preventedby") == self.options.id)
                        self.element.data("preventedby", null)

                    if( self.justCompleted ) {
                        if ( ! self.element.data("preventedby") )
                            self.element.data("preventedby", self.options.id);
                        self.justCompleted = false;
                        return false;
                    }
                });
            },

            // store this in an array, and in a hash, so that we can easily look up presence of tags
            _cacheData: function(array, key) {
                this.currentCache=key;

                this.cache[this.currentCache] = array;
                this.cachemap[this.currentCache] = {};
                for( var i in array ) {
                    this.cachemap[this.currentCache][array[i]] = true;
                }
            },

            tagstatus: function(key) {
                var self = this;

                if ( !self.cachemap[key] )
                    return;

                // recheck tags status in case tags list loaded slowly
                // or we switched comms
                $("."+self.options.tokenClass, self.uiAutocomplete).each(function() {
                    var exists = self.cachemap[key][$(this).find("."+self.options.tokenTextClass).text()];
                    $(this).toggleClass(self.options.newTokenClass, !exists).toggleClass(self.options.curTokenClass, exists);
                });
            },

            populate: function(url, id) {
                var self = this;

                $.getJSON(url, function(data) {
                    if ( !data ) return;

                    self._cacheData(data.tags, id);
                    self.tagstatus(id);
                });
            },

            clear: function () {
                var self = this;
                self._cacheData([], "");
                self.tagstatus("");
            }
    });

})(jQuery);
