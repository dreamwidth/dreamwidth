# base class for in page popup widgets
package LJ::Widget::IPPU;
use base 'LJ::Widget';

# load all subclasses
LJ::ModuleLoader->autouse_subclasses("LJ::Widget::IPPU");

sub ajax { 1 }

1;
