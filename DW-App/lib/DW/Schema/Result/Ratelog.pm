use utf8;
package DW::Schema::Result::Ratelog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Ratelog

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

=head1 TABLE: C<ratelog>

=cut

__PACKAGE__->table("ratelog");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 rlid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 evttime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ip

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 quantity

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "rlid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "evttime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ip",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "quantity",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wULMJRQ/jmKFHw42H/yeNA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
