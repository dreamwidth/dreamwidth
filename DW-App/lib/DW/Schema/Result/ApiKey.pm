use utf8;
package DW::Schema::Result::ApiKey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ApiKey

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

=head1 TABLE: C<api_key>

=cut

__PACKAGE__->table("api_key");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 keyid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 hash

  data_type: 'char'
  is_nullable: 0
  size: 32

=head2 state

  data_type: 'char'
  default_value: 'A'
  is_nullable: 0
  size: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "keyid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "hash",
  { data_type => "char", is_nullable => 0, size => 32 },
  "state",
  { data_type => "char", default_value => "A", is_nullable => 0, size => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</keyid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "keyid");

=head1 UNIQUE CONSTRAINTS

=head2 C<hash>

=over 4

=item * L</hash>

=back

=cut

__PACKAGE__->add_unique_constraint("hash", ["hash"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:21OL+vwfZmwJNb2VcQP0Hw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
