jQuery(function($){
    $("#textcaptcha_container").html(captcha.loadingText)
        .load($.endpoint("captcha") + "/" + captcha.auth);
});
