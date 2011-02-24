/* this test serves two functions:

    * example of how to create a mock request response with both jQuery
      and the old library

    * proves that the qunit (test framework) + sinon (mock request) + our libs
      all work together
*/
var lifecycle = {
    setup: function() {
        this.server = sinon.sandbox.useFakeServer();
    },

    teardown: function() {
        this.server.restore();
    }
};

module( "old", lifecycle );
test( "get fake success", 1, function() {
    this.server.respondWith( /^\/somefakeurl/, [
        200,
        {},
        "{ fakedata: \"isfake\" }"
    ] );

    HTTPReq.getJSON({
        url:    "/somefakeurl",
        method: "GET",
        onData: function (data) {
            deepEqual( data, { fakedata: "isfake" }, "got back expected fake data" );
        },
        onError: function (msg) {
            ok( false, "shouldn't error" );
        }
    });

    this.server.respond();
} );

test( "get fake failure", 1, function() {
    this.server.respondWith( /^\/somefakeurl/, [
        404,
        {},
        "{ fakedata: \"isfake\" }"
    ] );

    HTTPReq.getJSON({
        url:    "/somefakeurl",
        method: "GET",
        onData: function (data) {
            ok( false, "shouldn't get the data" );
        },
        onError: function (msg) {
            ok( true, "expected error" );
        }
    });

    this.server.respond();
} );

module( "jquery", lifecycle  );
test( "get fake success", 1, function() {
    this.server.respondWith( /^\/somefakeurl/, [
        200,
        {},
        "{ \"fakedata\": \"isfake\" }"
    ] );

    jQuery.ajax({
        url:      "/somefakeurl",
        type:     "GET",
        dataType: "json",
        success:   function( data, status, jqxhr ) {
            deepEqual( data, { fakedata: "isfake" }, "got back expected fake data" );
        },
        error: function( jqxhr, status, error ) {
            ok( false, "shouldn't error" );
        }
    });

    this.server.respond();
} );

test( "get fake error", 2, function() {
    this.server.respondWith( /^\/somefakeurl/, [
        404,
        {},
        "{ \"fakedata\": \"isfake\" }"
    ] );

    jQuery.ajax({
        url:      "/somefakeurl",
        type:     "GET",
        dataType: "json",
        success:   function( data, status, jqxhr ) {
            ok( false, "shouldn't get the data" );
        },
        error: function( jqxhr, status, error ) {
            ok( status, "error" );
            ok( error, "Not Found" );
        }
    });

    this.server.respond();
} );
