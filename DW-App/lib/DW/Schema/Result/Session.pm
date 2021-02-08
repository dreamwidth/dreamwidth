use utf8;
package DW::Schema::Result::Session;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Session

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

=head1 TABLE: C<sessions>

=cut

__PACKAGE__->table("sessions");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 sessid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 auth

  data_type: 'char'
  is_nullable: 0
  size: 10

=head2 exptype

  data_type: 'enum'
  extra: {list => ["short","long","once"]}
  is_nullable: 0

=head2 timecreate

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 timeexpire

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ipfixed

  data_type: 'char'
  is_nullable: 1
  size: 15

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "sessid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "auth",
  { data_type => "char", is_nullable => 0, size => 10 },
  "exptype",
  {
    data_type => "enum",
    extra => { list => ["short", "long", "once"] },
    is_nullable => 0,
  },
  "timecreate",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "timeexpire",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ipfixed",
  { data_type => "char", is_nullable => 1, size => 15 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</sessid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "sessid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:c95HlwR68n4CCXeyRE49dw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
