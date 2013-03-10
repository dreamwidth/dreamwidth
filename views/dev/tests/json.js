/* defined as
    my $hash = {
        string => "string",
        num    => 42,
        array  => [ "a", "b", 2 ],
        hash   => { a => "apple", b => "bazooka" },
        nil    => undef,
        nilvar => $undef,
        blank  => "",
        zero   => 0,
        symbols => qq{"',;:},
        html    => qq{<a href="#">blah</a>}
    };

    my $array = [ 7, "string", "123", { "foo" => "bar" }, undef, $undef, "", 0, qq{"',;:}, qq{<a href="#">blah</a>} ];
*/

var expected_results = {
    setup: function() {
        this.js_dumper = {
            array: [ 7, "string", 123, "123.", { foo: "bar" }, "", "", "", 0, "\"',;:", "<a href=\"#\">blah</a>", "テスト" ],
            hash: {
                string: "string",
                num   : 42,
                numdot: "42.",
                array : [ "a", "b", 2 ],
                hash  : { a: "apple", b: "bazooka" },
                nil   : "",
                nilvar: "",
                blank : "",
                zero  : 0,
                symbols: "\"',;:",
                html  : "<a href=\"#\">blah</a>",
                utf8  : "テスト"
            }
        };

        this.json = {
            array: [ 7, "string", "123", "123.", { foo: "bar" }, null, null, "", 0, "\"',;:", "<a href=\"#\">blah</a>", "テスト" ],
            hash: {
                string: "string",
                num   : 42,
                numdot: "42.",
                array : [ "a", "b", 2 ],
                hash  : { a: "apple", b: "bazooka" },
                nil   : null,
                nilvar: null,
                blank : "",
                zero  : 0,
                symbols: "\"',;:",
                html  : "<a href=\"#\">blah</a>",
                utf8  : "テスト"
            }
        };
    }
};

module( "old", expected_results );
function old_getjson(url, expected) {
    HTTPReq.getJSON({
        url:    url,
        method: "GET",
        onData: function (data) {
            start();
            deepEqual( data, expected );
        },
        onError: function (msg) {
            start();
            ok( false, "shouldn't error" );
        }
    });
}

asyncTest( "js_dumper - array", 1, function() {
    old_getjson( "/dev/testhelper/jsondump?function=js_dumper&output=array", this.js_dumper.array );
});


asyncTest( "js_dumper - hash", 1, function() {
    old_getjson( "/dev/testhelper/jsondump?function=js_dumper&output=hash", this.js_dumper.hash );
});

asyncTest( "json module - array", 1, function() {
    old_getjson( "/dev/testhelper/jsondump?function=json&output=array", this.json.array );
});

asyncTest( "json module - hash", 1, function() {
    old_getjson( "/dev/testhelper/jsondump?function=json&output=hash", this.json.hash );
});


module( "jquery", expected_results );
function jquery_getjson_ok(url, expected) {
    $.ajax({
        url: url,
        dataType: "json",
        success: function(data) {
            start();
            deepEqual( data, expected );
        },
        error: function(jqxhr, status, error) {
            start();
            ok( false, "error getting " + url + ": " + error );
        }
    });
}

function jquery_getjson_fail( url ) {
    $.ajax({
        url: url,
        dataType: "json",
        success: function(data) {
            start();
            ok( false, "unexpected success. js dumper output not strict JSON, doesn't actually work with jquery" );
        },
        error: function(jqxhr, status, error) {
            start();
            ok( error.name == "SyntaxError", "expected fail. js_dumper output not strict JSON, doesn't actually work with jquery" );
        }
    });
}

asyncTest( "js_dumper - array", 1, function() {
    jquery_getjson_fail("/dev/testhelper/jsondump?function=js_dumper&output=array");
});

asyncTest( "js_dumper - hash", 1, function() {
    jquery_getjson_fail("/dev/testhelper/jsondump?function=js_dumper&output=hash");
});

asyncTest( "json module - array", 1, function() {
    jquery_getjson_ok( "/dev/testhelper/jsondump?function=json&output=array", this.json.array );
});

asyncTest( "json module - hash", 1, function() {
    jquery_getjson_ok( "/dev/testhelper/jsondump?function=json&output=hash", this.json.hash );
});

