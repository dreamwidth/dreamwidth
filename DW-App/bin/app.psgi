#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";


# use this block if you don't need middleware, and only have a single target Dancer app to run here
use DW::App;

DW::App->to_app;

=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use DW::App;
use Plack::Builder;

builder {
    enable 'Deflater';
    DW::App->to_app;
}

=end comment

=cut

=begin comment
# use this block if you want to mount several applications on different path

use DW::App;
use DW::App_admin;

use Plack::Builder;

builder {
    mount '/'      => DW::App->to_app;
    mount '/admin'      => DW::App_admin->to_app;
}

=end comment

=cut

