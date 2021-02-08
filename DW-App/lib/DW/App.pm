package DW::App;
use Dancer2;

use DW::App::Userpic;

our $VERSION = '0.1';

get '/' => sub {
    template 'index' => { 'title' => 'DW::App' };
};

true;
