use utf8;
package DW::Schema::Result::Rename;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Rename

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

=head1 TABLE: C<renames>

=cut

__PACKAGE__->table("renames");

=head1 ACCESSORS

=head2 renid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 auth

  data_type: 'char'
  is_nullable: 0
  size: 13

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 ownerid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 renuserid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 fromuser

  data_type: 'char'
  is_nullable: 1
  size: 25

=head2 touser

  data_type: 'char'
  is_nullable: 1
  size: 25

=head2 rendate

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 status

  data_type: 'char'
  default_value: 'A'
  is_nullable: 0
  size: 1

=cut

__PACKAGE__->add_columns(
  "renid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "auth",
  { data_type => "char", is_nullable => 0, size => 13 },
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "ownerid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "renuserid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "fromuser",
  { data_type => "char", is_nullable => 1, size => 25 },
  "touser",
  { data_type => "char", is_nullable => 1, size => 25 },
  "rendate",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "status",
  { data_type => "char", default_value => "A", is_nullable => 0, size => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</renid>

=back

=cut

__PACKAGE__->set_primary_key("renid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jjpLfEh0PLLkxpfNwDn7cw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
