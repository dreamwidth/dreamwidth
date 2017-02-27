package DW::API::Method;

use strict;
use warnings;
use JSON;

use DW::API::Param;
use Carp;

sub define_method {
    my ($action, $desc, $handler) = @_;

    my %method = (
        name => $action,
        desc => $desc,
        handler => $handler,
        responses => {},
        );

    bless \%method;
    return \%method;
}

sub param {
    my ($self, @args) = @_;

    my $param = DW::API::Param::define_parameter(@args);
    my $name = $param->name;
    $self->{params}{$name} = $param;
}

sub success {
    my ($self, $desc, $schema) = @_;

    $self->{responses}{200} = { desc => $desc, schema => $schema};
}

sub error {
    my ($self, $code, $desc) = @_;

    $self->{responses}{$code} = { desc => $desc };
}

sub validate {
    my $self = $_[0];

    for my $field ('name', 'desc', 'handler', 'responses') {
        die "$self is missing required field $field" unless defined $self->{field};
    }

}

sub TO_JSON {
    my $self = $_[0];

    my $json = qq(
        "$self->{name}" : {
            "description" : "$self->{desc}"
            );
    if (defined $self->{params}) {
        $json .= ', "parameters" : [ ';
        my @params;

        for my $key (keys $self->{params}) {
            push ($self->{params}{$key}->TO_JSON()), @params;
        }
        $json .= join(",", @params);
        $json .= " ]"
    }
    $json .='"responses" : {';
    my @responses;
    for my $key (keys $self->{responses}) {
        my $response = $self->{responses}{$key};
        my $res_json = qq("$key" : { "description" : "$response->{desc}"});
        $res_json .= qq(,"schema" : $response->{schema}) if exists $response->{schema};
        $res_json .= "}";

        push(($res_json), @responses);
    }
    $json .= join(',', @responses);
    $json .= "\n}";
    return $json;
}


1;

__END__
=head1 NAME
Raisin::Routes - A routing class for Raisin.
=head1 SYNOPSIS
    use Raisin::Routes;
    my $r = Raisin::Routes->new;
    my $params = { require => ['name', ], };
    my $code = sub { { name => $params{name} } }
    $r->add('GET', '/user', params => $params, $code);
    my $route = $r->find('GET', '/user');
=head1 DESCRIPTION
The router provides the connection between the HTTP requests and the web
application code.
=over
=item B<Adding routes>
    $r->add('GET', '/user', params => $params, $code);
=cut
=item B<Looking for a route>
    $r->find($method, $path);
=cut
=back
=head1 PLACEHOLDERS
Regexp
    qr#/user/(\d+)#
Required
    /user/:id
Optional
    /user/?id
=head1 METHODS
=head2 add
Adds a new route
=head2 find
Looking for a route
=head1 ACKNOWLEDGEMENTS
This module was inspired by L<Kelp::Routes>.
=head1 AUTHOR
Artur Khabibullin - rtkh E<lt>atE<gt> cpan.org
=head1 LICENSE
This module and all the modules in this package are governed by the same license
as Perl itself.
=cut