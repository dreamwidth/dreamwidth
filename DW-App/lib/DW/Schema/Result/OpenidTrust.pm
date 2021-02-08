use utf8;
package DW::Schema::Result::OpenidTrust;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::OpenidTrust

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

=head1 TABLE: C<openid_trust>

=cut

__PACKAGE__->table("openid_trust");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 endpoint_id

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 trust_time

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 duration

  data_type: 'enum'
  default_value: 'always'
  extra: {list => ["always","once"]}
  is_nullable: 0

=head2 last_assert_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 flags

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "endpoint_id",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "trust_time",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "duration",
  {
    data_type => "enum",
    default_value => "always",
    extra => { list => ["always", "once"] },
    is_nullable => 0,
  },
  "last_assert_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "flags",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</endpoint_id>

=back

=cut

__PACKAGE__->set_primary_key("userid", "endpoint_id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4Wgp4UWqk7yGIBg/WdsiSQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
