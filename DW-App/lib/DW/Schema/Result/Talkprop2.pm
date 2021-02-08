use utf8;
package DW::Schema::Result::Talkprop2;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Talkprop2

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

=head1 TABLE: C<talkprop2>

=cut

__PACKAGE__->table("talkprop2");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 jtalkid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 tpropid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "jtalkid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "tpropid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "value",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</jtalkid>

=item * L</tpropid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "jtalkid", "tpropid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oq5FyC8yoAgi/6DjQWjdFQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
