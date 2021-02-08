use utf8;
package DW::Schema::Result::Sub;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Sub

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

=head1 TABLE: C<subs>

=cut

__PACKAGE__->table("subs");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 subid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 is_dirty

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 etypeid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg1

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg2

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ntypeid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 createtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 expiretime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 flags

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "subid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "is_dirty",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 1 },
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "etypeid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg1",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg2",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ntypeid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "createtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "expiretime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "flags",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</subid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "subid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:n2thRhrWva12QDn+3n8jMw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
