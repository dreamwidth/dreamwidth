use utf8;
package DW::Schema::Result::Logslug;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Logslug

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

=head1 TABLE: C<logslugs>

=cut

__PACKAGE__->table("logslugs");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 jitemid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 slug

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "journalid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "jitemid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "slug",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</jitemid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "jitemid");

=head1 UNIQUE CONSTRAINTS

=head2 C<journalid>

=over 4

=item * L</journalid>

=item * L</slug>

=back

=cut

__PACKAGE__->add_unique_constraint("journalid", ["journalid", "slug"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:O7pVUxh58ciQ44mE06BRGQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
