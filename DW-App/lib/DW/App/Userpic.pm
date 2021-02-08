package DW::App;
use Dancer2;
use Dancer2::Plugin::DBIC;

get '/userpic/:picid[Int]/:userid[Int]' => sub {
    my $user = schema('global')->resultset('User')->find(param 'userid');

    my $picid = param 'picid';

    return "{$picid} {" . $user->user . "}";

    # Load the user object and pic and make sure the picture is viewable
    # my $u   = LJ::load_userid( $RQ{'pic-userid'} );
    # my $pic = LJ::Userpic->get( $u, $RQ{'picid'}, { no_expunged => 1 } )
    #     or return NOT_FOUND;

    # Must have contents by now, or return 404
    # my $data = $pic->imagedata;
    # return NOT_FOUND unless $data;

    # Everything looks good, send it
    # $apache_r->content_type( $pic->mimetype );
    # $apache_r->headers_out->{"Content-length"} = length $data;
    # $apache_r->headers_out->{"Cache-Control"}  = "no-transform";
    # $apache_r->headers_out->{"Last-Modified"}  = LJ::time_to_http( $pic->pictime );
    # $apache_r->print($data)
    #     unless $apache_r->header_only;
    # return OK;
};

true;
