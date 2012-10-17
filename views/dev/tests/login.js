/* INCLUDE:
js/md5.js
old: js/login.js
jquery: js/login-jquery.js
*/

var check_results =  function() {
    expect(6);

    var response_field = document.getElementById( "login_response" );
    var password_field = document.getElementById( "xc_password" );
    var challenge_field = document.getElementById( "login_chal" );

    ok( response_field, "response field exists" );
    ok( password_field, "password field exists" );
    ok( challenge_field, "challenge field exists" );

    equal( challenge_field.value, "challenge" );
    equal( password_field.value, "", "no cleartext password" );
    equal( response_field.value, "6d7d8d39264a6416f8d27965cc1fe8e2", "expected hashed challenge and password" );
};

module( "old" );
test( "hash password when logging in", function() {
    LiveJournal.loginFormSubmitted({ target: document.getElementById("login") });
    check_results();
} );

module( "jquery" );
test( "hash password when logging in", function() {
    $("#login").triggerHandler("submit");
    check_results();
} );


