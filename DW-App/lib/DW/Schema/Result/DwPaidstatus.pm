use utf8;
package DW::Schema::Result::DwPaidstatus;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::DwPaidstatus

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

=head1 TABLE: C<dw_paidstatus>

=cut

__PACKAGE__->table("dw_paidstatus");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 typeid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 expiretime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 permanent

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 lastemail

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "typeid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "expiretime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "permanent",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "lastemail",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VBDdhpVr2ZyWckPloVJ7XA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
