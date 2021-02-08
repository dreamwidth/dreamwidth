use utf8;
package DW::Schema::Result::CcLog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::CcLog

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

=head1 TABLE: C<cc_log>

=cut

__PACKAGE__->table("cc_log");

=head1 ACCESSORS

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ip

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 transtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 req_content

  data_type: 'text'
  is_nullable: 0

=head2 res_content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ip",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "transtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "req_content",
  { data_type => "text", is_nullable => 0 },
  "res_content",
  { data_type => "text", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VVVj5knwAxynoVAkTkTrMA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
