package LJ::HTML::Template;
use strict;
use HTML::Template;


# Returns a new HTML::Template object
# with some redefined default values.
sub new {
    my $class = shift;
    return 
        HTML::Template->new(
            global_vars => 1, # normally variables declared outside a loop are not available inside
                              # a loop.  This option makes <TMPL_VAR>s like global variables in Perl 
                              # - they have unlimited scope.  
                              # This option also affects <TMPL_IF> and <TMPL_UNLESS>

            die_on_bad_params => 0, # if set to 0 the module will let you call 
                                    # $template->param(param_name => 'value') even 
                                    # if 'param_name' doesn't exist in the template body.
                                    # Defaults to 1.
            @_
        );
}


1;
