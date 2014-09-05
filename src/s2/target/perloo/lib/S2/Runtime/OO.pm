
=head1 NAME

S2::Runtime::OO - Object-oriented S2 runtime

=head1 SYNOPSIS

    use S2::Runtime::OO;
    
    my $s2 = new S2::Runtime::OO;
    
    my $core = $s2->layer_from_file('core.pl');
    my $layout = $s2->layer_from_file('layout.pl');
    
    my $ctx = $s2->make_context($core, $layout);
    $ctx->set_print(sub { print $_[1]; });

    my $page = {
        '_type' => 'Page',
        # ...
    };

    $ctx->run_function("Page::print()", $page);

=cut

package S2::Runtime::OO;

use S2::Runtime::OO::Context;
use S2::Runtime::OO::Layer;
use strict;

sub new {
    my ($class) = @_;
    return bless \$class, $class;
}

sub layer_from_string {
    my $lay = eval(${$_[1]});
    die $@ if ($@);
    return $lay;
}

sub layer_from_file {
    return do($_[1]);
}

sub make_context {
    my ($self, @layers) = @_;
    
    @layers = @{$layers[0]} if (ref $layers[0] eq 'ARRAY');

    return new S2::Runtime::OO::Context(@layers);
}

### Called from layer code; not public API.

# Called from NodeForEachStmt to get string split into characters
sub _get_characters {
    my $string = shift;
    use utf8;
    return split(//,$string);
}

# Called from the boolification code in Node to see if an array or hash is true or false
sub _check_elements {
    my $obj = shift;
    if (ref $obj eq "ARRAY") {
        return @$obj ? 1 : 0;
    } elsif (ref $obj eq "HASH") {
        return %$obj ? 1 : 0;
    }
    return 0;
}

# Called from AssignExpr and ReturnStmt when "notags" is in effect.
sub _no_tags {
    my $a = shift;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

1;
