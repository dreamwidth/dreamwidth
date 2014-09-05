
package S2::Runtime::OO::Layer;
use strict;

sub new {
    my $self = {
        'info' => {},
        'prop' => {},
        'propset' => {},
        'propgroup' => [],
        'propgroup_members' => {},
        'propgroup_name' => {},
        'prop_use' => [],
        'prop_hide' => {},
        'func' => {},
        'classdoc' => {},
        'globfuncdoc' => {},
        'sourcename' => {},
    };

    return bless $self, shift;
}

sub get_functions {
    return $_[0]->{func};
}

sub get_property_sets {
    return $_[0]->{propset};
}

sub get_property_attributes {
    return $_[0]->{prop};
}

sub get_class_docs {
    return $_[0]->{classdoc};
}

sub get_layer_info {
    my ($self, $key) = @_;
    return $self->{info}{$key} if defined($key);
    return $self->{info};
}

# These methods called by S2 layer code during load. Not public API.

sub set_source_name {
    my ($self, $name) = @_;
    
    $self->{sourcename} = $name;
}

sub set_layer_info {
    my ($self, $key, $value) = @_;
    
    $self->{info}{$key} = $value;
}

sub register_class {
    my ($self, $name, $doc) = @_;
    
    $self->{classdoc}{$name} = $doc;
}

sub register_global_function {
    my ($self, $sig, $rettype, $doc, $attr) = @_;
    
    $self->{globfuncdoc}{$sig} = {
        "return" => $rettype,
        "docstring" => $doc,
        "attr" => { map({ $_ => 1 } split(/,/, $attr)) },
    };
}

sub register_propgroup_name {
    my ($self, $ident, $name) = @_;
    
    $self->{propgroup_name}{$ident} = $name;
}

sub register_propgroup_props {
    my ($self, $groupname, $props) = @_;
    
    $self->{propgroup_members}{$groupname} = $props;
}

sub register_property_use {
    my ($self, $name) = @_;
    
    push @{$self->{prop_use}}, $name;
}

sub register_property_hide {
    my ($self, $name) = @_;
    
    $self->{prop_hide}{$name} = 1;
}

sub register_property {
    my ($self, $name, $attr) = @_;
    
    $self->{prop}{$name} = $attr;
}

sub register_set {
    my ($self, $name, $value) = @_;

    $self->{propset}{$name} = $value;
}

sub register_function {
    my ($self, $sigs, $code) = @_;

    my $impl = $code->();
    
    foreach my $sig (@$sigs) {
        $self->{func}{$sig} = $impl;
    }
}

1;
