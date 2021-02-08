use utf8;
package DW::Schema::Result::Usermsg;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Usermsg

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

=head1 TABLE: C<usermsg>

=cut

__PACKAGE__->table("usermsg");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 msgid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 type

  data_type: 'enum'
  extra: {list => ["in","out"]}
  is_nullable: 0

=head2 parent_msgid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 otherid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 timesent

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 state

  data_type: 'char'
  default_value: 'A'
  is_nullable: 1
  size: 1

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "msgid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "type",
  {
    data_type => "enum",
    extra => { list => ["in", "out"] },
    is_nullable => 0,
  },
  "parent_msgid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "otherid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "timesent",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "state",
  { data_type => "char", default_value => "A", is_nullable => 1, size => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</msgid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "msgid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+SBYqSbamv7/XVTFuc2IVA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
