use utf8;
package DW::Schema::Result::Underage;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Underage

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<underage>

=cut

__PACKAGE__->table("underage");

=head1 ACCESSORS

=head2 uniq

  data_type: 'char'
  is_nullable: 0
  size: 15

=head2 timeof

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "uniq",
  { data_type => "char", is_nullable => 0, size => 15 },
  "timeof",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</uniq>

=back

=cut

__PACKAGE__->set_primary_key("uniq");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:DjKGJjzFWzouauH4wEjA0Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
