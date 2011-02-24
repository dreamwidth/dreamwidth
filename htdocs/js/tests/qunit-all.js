var _r = {
    all_tests: [],
    all_libs: ['old','jquery'],
    next_test_idx: 0,
    next_lib_idx: 0,
    init: function() {
        _r.next_test_idx = 0;
        _r.next_lib_idx = 0;
        _r.test_container = $("#qunit-tests");
        _r.test_results = $("#qunit-testresult");
        _r.test_banner = $("#qunit-banner");

        _r.passed = 0;
        _r.failed = 0;
        _r.total  = 0;
        _r.test_time = 0;

        _r.start_time = new Date().getTime();

        $("#qunit-filter-pass").attr("disabled",true);
        $("#qunit-testresult .line1").text("Pending...");
        _r.update_counts();
    },
    run_next: function() {
        if ( _r.next_lib_idx >= _r.all_libs.length ) {
            _r.next_lib_idx = 0;
            _r.next_test_idx++;
        }
        if ( _r.next_test_idx >= _r.all_tests.length ) {
            _r.done();
            return;
        }
        if ( _r.next_lib_idx < _r.all_libs.length ) {
            _r.run_test( _r.all_tests[_r.next_test_idx], _r.all_libs[_r.next_lib_idx++] );
        }
    },
    skip_test: function() {
        _r._next_lib_idx = 0;
        _r.next_test_idx++;
        _r.run_next();
    },
    update_counts: function() {
        $("#qunit-testresult .passed").text(_r.passed);
        $("#qunit-testresult .failed").text(_r.failed);
        $("#qunit-testresult .total").text(_r.total);
        var banner_class = "qunit-pass";
        if ( _r.failed ) {
            banner_class = "qunit-fail";
        }
        _r.test_banner.attr("class",banner_class);
    },
    run_test: function(test,lib) {
        $("#qunit-testresult .line1").text("Running test: " + test + ", lib: " + lib + "...");
        _r.cur_test = test;
        _r.cur_lib = lib;

        var url = "/dev/tests/"+test+"/"+lib;
        var li = $("<li>");
        li.attr("id","test-"+test+"-"+lib);
        _r.current_li = li;
        _r.test_container.append(li);

        var strong = $("<strong>");
        li.append(strong);

        var module_name = $("<span>");
        module_name.addClass("module-name");
        module_name.text(test + "-" + lib);
        strong.append(module_name);

        strong.append(": ");

        var counts = $("<span>");
        counts.addClass("counts");
        counts.text("Running...");
        strong.append(counts);

        var iframe = $("<iframe>");
        li.append(iframe);
        _r.current_iframe = iframe;

        iframe.hide();
        iframe.attr("src",url);


        iframe.load(function () {
            _r.poll_iframe();
        });
        strong.click(function () {
            iframe.toggle();
        })
    },
    done: function () {
        var end_time = new Date().getTime();
        var ms = Math.round(end_time - _r.start_time);
        $("#qunit-testresult .line1").text("Tests completed in " + ms + " milliseconds (" + _r.test_time + " milliseconds in tests).");
        $("#qunit-filter-pass").removeAttr("disabled");
    },
    poll_iframe: function () {
        var iframe = _r.current_iframe;
        var content = iframe.contents();

        var notests = content.find("#notests");
        if( notests.size() > 0 ) {
            _r.current_li
                .find(".counts").text("No tests defined for " + _r.cur_test).end()
                .find("iframe").remove();
            _r.skip_test();
            return;
        }

        var results = content.find("#qunit-testresult");

        if ( results.size() == 0 ) {
            setTimeout(_r.poll_iframe, 10);
            return;
        }

        var passed_i = results.find(".passed");
        var total_i  = results.find(".total");
        var failed_i = results.find(".failed");

        var tct = passed_i.size() + total_i.size() + failed_i.size();

        if ( tct != 3 ) {
            setTimeout(_r.poll_iframe, 10);
            return;
        }

        _r.passed += parseInt( passed_i.text(), 10 );
        _r.failed += parseInt( failed_i.text(), 10 );
        _r.total  += parseInt( total_i.text(),  10 );
        _r.update_counts();

        var match_result = /in ([0-9]+) millisecond/.exec(results.text());
        _r.test_time += parseInt( match_result[1], 10 );

        var nodes = content.find("#qunit-tests > li");
        nodes.detach();
        _r.test_container.append(nodes);
        nodes.each( function(_,node_d) {
            var node = $(node_d);
            node.addClass("test-"+_r.cur_test);
            node.addClass("lib-"+_r.cur_lib);
            node.addClass("testlib-"+_r.cur_test+"-"+_r.cur_lib);
            node.attr("id",node.attr("id")+"-"+_r.cur_test+"-"+_r.cur_lib)
            var element = node.find(".module-name");
            var lib = $("<span class='lib-type'>");
            lib.text(" (" +_r.cur_test + "/" + _r.cur_lib + ")");
            element.append(lib);
        });
        _r.current_li.remove();
        _r.run_next();
    },
    hide_passed: function (hide) {
        _r.test_container.find("> li").show();
        if ( hide ) {
            _r.test_container.find("> li.pass").hide();
        }
    }
}

function register_all_tests(t) {
    _r.all_tests = _r.all_tests.concat(t);
}

$(function () {
    _r.init();
    $("#qunit-userAgent").text( navigator.userAgent );
    $("#qunit-filter-pass").change( function() { _r.hide_passed( this.checked ) })
    _r.run_next();
});
