/* INCLUDE:
js/sample.js
stc/sample.css
*/

/*==============================================================================

    File which demonstrates how to write JavaScript unit tests. See
    http://docs.jquery.com/Qunit for more information about the testing framework.


    The tests defined here can be viewed by going to:

            /dev/tests/sample   (no extension)


    Libraries may be included by adding the library name to the path, as:

            /dev/tests/sample/jquery
            /dev/tests/sample/old

    Include any additional JS files to be tested using a comment in exactly the
    same comment as the comment at the top of this file, with each resource on
    a separate line.


    Each test suite can be separated into modules, and you can filter to
    specific modules by appending ?modulename1&modulename2 to the path. You can
    also filter to specific matching test names in the same way.

 =============================================================================*/
module( "jquery" );
test( "checking included html (sample.html). To see only this module, call as '/dev/tests/sample/jquery?jquery'", function() {
    expect(2);

    ok( $("#samplediv").length, "#sample div exists" );
    ok( ! $("#nonexistentdiv").length, "#nonexistentdiv doesn't exist" );
});

module( "old" );
test( "checking included html (sample.html). Call as '/dev/tests/sample/old?old'", function() {
    expect(2);

    ok( $("samplediv"), "#sample div exists" );
    ok( ! $("nonexistentdiv"), "#nonexistentdiv doesn't exist" );
});


module( "foo" );
test( "example test foo", function() {
    expect(1);

    ok( true, "passed" );
});

test( "example test again", function() {
    expect(1);

    ok( true, "passed again" );
});

