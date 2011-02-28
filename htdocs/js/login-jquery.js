(function($) {
    $.fn.hashpassword = function( action ) {
        var submitform = function() {
            var $self = $(this);
            var $chal_field = $self.find(".lj_login_chal");
            var $resp_field = $self.find(".lj_login_response");
            var $pass_field = $self.find(".lj_login_password");

            if ( $chal_field.length < 1 || $resp_field.length < 1
                || $pass_field.length < 1 )
                return true;

            var res = MD5( $chal_field.val() + MD5($pass_field.val()) );
            $resp_field.val(res);
            $pass_field.val("");
        }

        return this.each(function() {
            $(this).submit(submitform);
        })
    };

})(jQuery);

jQuery(function($) {
    $("form.lj_login_form").hashpassword();
});
