use utf8;
package DW::Schema::Result::Loginstall;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Loginstall

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

=head1 TABLE: C<loginstall>

=cut

__PACKAGE__->table("loginstall");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ip

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ip",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 UNIQUE CONSTRAINTS

=head2 C<userid>

=over 4

=item * L</userid>

=item * L</ip>

=back

=cut

__PACKAGE__->add_unique_constraint("userid", ["userid", "ip"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sOUc/T96KwWcivt/kMagvA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
