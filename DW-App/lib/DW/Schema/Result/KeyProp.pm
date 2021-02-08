use utf8;
package DW::Schema::Result::KeyProp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::KeyProp

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

=head1 TABLE: C<key_props>

=cut

__PACKAGE__->table("key_props");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 keyid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 propid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'mediumblob'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "keyid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "propid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "value",
  { data_type => "mediumblob", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</keyid>

=item * L</propid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "keyid", "propid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:uKgPJoQc35q5xV6LI955rQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
