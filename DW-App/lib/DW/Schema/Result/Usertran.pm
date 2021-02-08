use utf8;
package DW::Schema::Result::Usertran;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Usertran

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

=head1 TABLE: C<usertrans>

=cut

__PACKAGE__->table("usertrans");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 time

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 what

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 25

=head2 before

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 25

=head2 after

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 25

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "time",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "what",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 25 },
  "before",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 25 },
  "after",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 25 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:QAMdguthgCiCZKTYvGjP7g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
