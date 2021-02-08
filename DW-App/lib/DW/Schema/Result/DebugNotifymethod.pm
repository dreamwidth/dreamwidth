use utf8;
package DW::Schema::Result::DebugNotifymethod;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::DebugNotifymethod

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

=head1 TABLE: C<debug_notifymethod>

=cut

__PACKAGE__->table("debug_notifymethod");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 subid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 ntfytime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 origntypeid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 etypeid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 ejournalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 earg1

  data_type: 'integer'
  is_nullable: 1

=head2 earg2

  data_type: 'integer'
  is_nullable: 1

=head2 schjobid

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "subid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "ntfytime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "origntypeid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "etypeid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "ejournalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "earg1",
  { data_type => "integer", is_nullable => 1 },
  "earg2",
  { data_type => "integer", is_nullable => 1 },
  "schjobid",
  { data_type => "varchar", is_nullable => 1, size => 50 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:XR53EPxAgRdlNMUuwoYHBg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
