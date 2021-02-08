use utf8;
package DW::Schema::Result::Modlog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Modlog

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

=head1 TABLE: C<modlog>

=cut

__PACKAGE__->table("modlog");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 modid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 posterid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 subject

  data_type: 'char'
  is_nullable: 1
  size: 30

=head2 logtime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "modid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "posterid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "subject",
  { data_type => "char", is_nullable => 1, size => 30 },
  "logtime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</modid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "modid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8KiChGOkHcb9dLuIiUlCGQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
