use utf8;
package DW::Schema::Result::CcTran;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::CcTran

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

=head1 TABLE: C<cc_trans>

=cut

__PACKAGE__->table("cc_trans");

=head1 ACCESSORS

=head2 cctransid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 gctaskref

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 dispatchtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 jobstate

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 joberr

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 response

  data_type: 'char'
  is_nullable: 1
  size: 1

=head2 responsetext

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 authcode

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 transactionid

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 avsresponse

  data_type: 'char'
  is_nullable: 1
  size: 1

=head2 cvvresponse

  data_type: 'char'
  is_nullable: 1
  size: 1

=head2 responsecode

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 ccnumhash

  data_type: 'varchar'
  is_nullable: 0
  size: 32

=head2 expmon

  data_type: 'tinyint'
  is_nullable: 0

=head2 expyear

  data_type: 'smallint'
  is_nullable: 0

=head2 firstname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 lastname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 street1

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 street2

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 city

  data_type: 'varchar'
  is_nullable: 0
  size: 40

=head2 state

  data_type: 'varchar'
  is_nullable: 0
  size: 40

=head2 country

  data_type: 'char'
  is_nullable: 0
  size: 2

=head2 zip

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 phone

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 ipaddr

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=cut

__PACKAGE__->add_columns(
  "cctransid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "gctaskref",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "dispatchtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "jobstate",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "joberr",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "response",
  { data_type => "char", is_nullable => 1, size => 1 },
  "responsetext",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "authcode",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "transactionid",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "avsresponse",
  { data_type => "char", is_nullable => 1, size => 1 },
  "cvvresponse",
  { data_type => "char", is_nullable => 1, size => 1 },
  "responsecode",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 1 },
  "ccnumhash",
  { data_type => "varchar", is_nullable => 0, size => 32 },
  "expmon",
  { data_type => "tinyint", is_nullable => 0 },
  "expyear",
  { data_type => "smallint", is_nullable => 0 },
  "firstname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "lastname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "street1",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "street2",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "city",
  { data_type => "varchar", is_nullable => 0, size => 40 },
  "state",
  { data_type => "varchar", is_nullable => 0, size => 40 },
  "country",
  { data_type => "char", is_nullable => 0, size => 2 },
  "zip",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "phone",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "ipaddr",
  { data_type => "varchar", is_nullable => 0, size => 15 },
);

=head1 PRIMARY KEY

=over 4

=item * L</cctransid>

=back

=cut

__PACKAGE__->set_primary_key("cctransid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:PZO4/1mIqrypOjh8a0gjPw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
