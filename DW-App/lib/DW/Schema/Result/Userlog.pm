use utf8;
package DW::Schema::Result::Userlog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Userlog

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

=head1 TABLE: C<userlog>

=cut

__PACKAGE__->table("userlog");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 logtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 action

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 actiontarget

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 remoteid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 ip

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 uniq

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 extra

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "logtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "action",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "actiontarget",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "remoteid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "ip",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "uniq",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "extra",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0v+7lu3D7tfLsE9jffoNxw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
