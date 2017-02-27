package DW::API::Param;

use strict;
use warnings;
use JSON;
use Exporter 'import'; # gives you Exporter's import() method directly
our @EXPORT_OK = qw(define_parameter);  # symbols to export on request

use Carp qw(croak);

my @ATTRIBUTES = qw(name type in desc);
my @LOCATIONS = qw(path formData body header query);

sub define_parameter {
    my $args = $_[0];
    my %parameter = (
        name => $args->{name},
        desc => $args->{desc},
        in => $args->{in},
        type => $args->{type},
        required => $args->{required}
    );
    bless \%parameter;
    return \%parameter;
}

sub validate {
    my $self = $_[0];
    for my $field (@ATTRIBUTES) {
        die "$self is missing required field $field" unless defined $self->{field};
    }
    my $location = $self->{in};
    die "$location isn't a valid parameter location" unless grep($location, @LOCATIONS);
}

sub TO_JSON {
    my $self = $_[0];

    my $json = qq(
        "$self->{name}" : {
            "name" : "$self->{name}",
            "description" : "$self->{desc}",
            "type" : "$self->{type}",
            "in" : "$self->{in}"
            );
    $json .= qq(,"required" : true) if defined $self->{required} && $self->{required};
    $json .= "\n}";
    return $json;

}

1;

__END__
=head1 NAME
Raisin::Param - Parameter class for Raisin.
=head1 DESCRIPTION
Parameter class for L<Raisin>. Validates request paramters.
=head3 default
Returns default value if exists or C<undef>.
=head3 desc
Returns parameter description.
=head3 name
Returns parameter name.
=head3 display_name
An alias to L<Raisin::Param/name>.
=head3 named
Returns C<true> if it's path parameter.
=head3 regex
Return paramter regex if exists or C<undef>.
=head3 required { shift->{required} }
Returns C<true> if it's required parameter.
=head3 type
Returns parameter type object.
=head3 in
Returns the location of the parameter: B<query, header, path, formData, body>.
=head3 validate
Process and validate parameter. Takes B<reference> as the input paramter.
    $p->validate(\$value);
=head1 AUTHOR
Artur Khabibullin - rtkh E<lt>atE<gt> cpan.org
=head1 LICENSE
This module and all the modules in this package are governed by the same license
as Perl itself.
=cut