use utf8;
package DW::Schema::Result::Faqcat;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Faqcat

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

=head1 TABLE: C<faqcat>

=cut

__PACKAGE__->table("faqcat");

=head1 ACCESSORS

=head2 faqcat

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

=head2 faqcatname

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 catorder

  data_type: 'integer'
  default_value: 50
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "faqcat",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "faqcatname",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "catorder",
  { data_type => "integer", default_value => 50, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</faqcat>

=back

=cut

__PACKAGE__->set_primary_key("faqcat");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0SzQPfgMrcM4+F+PXEAWTA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
