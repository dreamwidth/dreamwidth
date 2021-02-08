use utf8;
package DW::Schema::Result::HasSub;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::HasSub

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

=head1 TABLE: C<has_subs>

=cut

__PACKAGE__->table("has_subs");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 etypeid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg1

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg2

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 verifytime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "etypeid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg1",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg2",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "verifytime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</etypeid>

=item * L</arg1>

=item * L</arg2>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "etypeid", "arg1", "arg2");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:D5umsNeEMYaLjhTTw081/Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
