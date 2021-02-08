use utf8;
package DW::Schema::Result::Usermsgprop;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Usermsgprop

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

=head1 TABLE: C<usermsgprop>

=cut

__PACKAGE__->table("usermsgprop");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 msgid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 propid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 propval

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "msgid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "propid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "propval",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</msgid>

=item * L</propid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "msgid", "propid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MJ/vr5Guc0M9lVgIluR8gA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
