DirectorySearchResults = new Class(Object, {
    init: function (results, opts) {
        if ( DirectorySearchResults.superClass.init )
            DirectorySearchResults.superClass.init.apply(this, []);

        if (! opts || ! opts.resultsView) {
            var ippu = new LJ_IPPU('Search Results');
            ippu.setFadeIn(true);
            ippu.setFadeOut(true);
            ippu.setFadeSpeed(5);
            ippu.setDimensions("60%", "400px");
            ippu.show();
            this.ippu = ippu;
        }

        this.results = results;
        this.users = results.users ? results.users : [];

        // set up display options
        {
            this.picScale = 1;

            this.resultsDisplay = opts && opts.resultsDisplay ? opts.resultsDisplay :
                DirectorySearchResults.defaults.resultsDisplay;

            this.resultsPerPage = opts && opts.resultsPerPage ? opts.resultsPerPage :
                DirectorySearchResults.defaults.resultsPerPage;
            this.page = opts && opts.page ? opts.page : 0;

            if (opts && opts.resultsView) this.resultsView = opts.resultsView;
        }

        this.render();
    },

    render: function () {
        var content = document.createElement("div");
        DOM.addClassName(content, "ResultsContainer");
        var self = this;

        // display mode toggle
        {
            var displayModeContainer = document.createElement("div");
            DOM.addClassName(displayModeContainer, "DisplayModeContainer");
            displayModeContainer.appendChild(_textSpan("Display: "));

            var userpicsMode = document.createElement("a");
            userpicsMode.innerHTML = "Userpics";
            DOM.addEventListener(userpicsMode, "click", function () {
                self.resultsDisplay = "userpics";
                DirectorySearchResults.defaults.resultsDisplay = self.resultsDisplay;
                self.render();
            });

            var textMode = document.createElement("a");
            textMode.innerHTML = "Text";
            DOM.addEventListener(textMode, "click", function () {
                self.resultsDisplay = "text";
                DirectorySearchResults.defaults.resultsDisplay = self.resultsDisplay;
                self.render();
            });

            var selectedLink = this.resultsDisplay == "userpics" ? userpicsMode : textMode;
            DOM.addClassName(selectedLink, "SelectedDisplayMode");

            displayModeContainer.appendChild(userpicsMode);
            displayModeContainer.appendChild(_textSpan(" | "));
            displayModeContainer.appendChild(textMode);

            content.appendChild(displayModeContainer);
        }

        // result count menu
        {
            var resultCountMenu = document.createElement("select");
            DOM.addClassName(resultCountMenu, "ResultCountMenu");

            // add items to menu
            [10, 25, 50, 100, 150, 200].forEach(function (ct) {
                var opt = document.createElement("option");
                opt.value = ct;
                opt.text = ct + " results";
                if (ct == self.resultsPerPage) {
                    opt.selected = true;
                }

                Try.these(
                          function () { resultCountMenu.add(opt, 0);    }, // IE
                          function () { resultCountMenu.add(opt, null); }  // Firefox
                          );
            });

            content.appendChild(_textSpan("Show "));
            content.appendChild(resultCountMenu);
            content.appendChild(_textSpan(" per page"));

            // add handler for menu
            var handleResultCountChange = function (e) {
                this.resultsPerPage = resultCountMenu.value;
                DirectorySearchResults.defaults.resultsPerPage = self.resultsPerPage;
                this.render();
            };
            DOM.addEventListener(resultCountMenu, "change", handleResultCountChange.bindEventListener(this));
        }

        // do pagination
        var pageCount   = Math.ceil(this.users.length / this.resultsPerPage); // how many pages
        var subsetStart = this.page * this.resultsPerPage; // where is the start index of this page
        var subsetEnd   = Math.min(subsetStart + this.resultsPerPage, this.users.length); // last index of this page

        var trunc = this.results.truncated ? " (truncated)" : "";
        var resultCount = _textDiv(this.users.length + " Results" + trunc);
        DOM.addClassName(resultCount, "ResultCount");
        content.appendChild(resultCount);

        // render the users
        var usersContainer = document.createElement("div");
        DOM.addClassName(usersContainer, "UsersContainer");
        for (var i = subsetStart; i < subsetEnd; i++) {
            var userinfo = this.users[i];
            var userEle = this.renderUser(userinfo);
            if (! userEle) continue;

            DOM.addClassName(userEle, "User");
            usersContainer.appendChild(userEle);
        }
        content.appendChild(usersContainer);

        // print pages
        if (pageCount > 1) {
            var pages = document.createElement("div");
            DOM.addClassName(pages, "PageLinksContainer");

            function pageLinkHandler (pageNum) {
                return function () {
                    self.page = pageNum;
                    self.render();
                };
            };

            for (var p = 0; p < pageCount; p++) {
                var pageLink = document.createElement("a");
                DOM.addClassName(pageLink, "PageLink");
                pageLink.innerHTML = p + 1;

                // install click handler on page #
                var self = this;
                DOM.addEventListener(pageLink, "click", pageLinkHandler(p));

                pages.appendChild(pageLink);
            }

            content.appendChild(pages);
        }

        if (this.ippu) {
            this.ippu.setContentElement(content);
        } else if (this.resultsView) {
            this.resultsView.innerHTML = '';
            this.resultsView.appendChild(content);
        }

        // since a bunch of userpics and ljusers were created
        // we should reload contextualpopup so it can attach to them
        if (eval(defined(ContextualPopup)) && ContextualPopup.setup)
            ContextualPopup.setup();
    },

    renderUser: function (user) {
        var container = document.createElement("span");

        if (this.resultsDisplay == "userpics") {
            var upicContainer = document.createElement("div");
            DOM.addClassName(upicContainer, "UserpicContainer");

            if (user.url_userpic) {
                var upic = document.createElement("img");
                upic.src = user.url_userpic;
                DOM.addClassName(upic, "Userpic");
                upicContainer.appendChild(upic);
            } else {
                upicContainer.innerHTML = "&nbsp;";
            }

            container.appendChild(upicContainer);
        }

        container.appendChild(_textSpan(user.ljuser_tag));
        var lastUpdated = _textDiv("Last updated " + user.lastupdated_string);
        DOM.addClassName(lastUpdated, "LastUpdated");
        container.appendChild(lastUpdated);

        return container;
    }
});

// Default values
DirectorySearchResults.defaults = {
    resultsDisplay: "userpics",
    resultsPerPage: 25
};
