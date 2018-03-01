
=head1 NAME

TIDES::Properties - Properties base class.

=head1 SYNOPSIS

    TIDES::Properties provides access to the database properties table.

=head1 ABSTRACT

Provide access to the database properties table.

=cut

package TIDES::Properties;

use warnings;
use strict;

=head1 PUBLIC METHODS

=head2 new

  * Purpose: Access database properties
  * Expected parameters: database handle
  * Function on success: returns Properties object
  * Function on failure: returns undef

=cut

sub new {
    my($type, %params) = @_;
    my $self = {
        dbh => $params{dbh},
        names_by_id => {},
        types_by_id => {},
        ids_by_name => {},
    };
    bless $self, $type;
}

=head2 get_names

  * Purpose: Return all names
  * Expected parameters: none
  * Function on success: returns array of names
  * Function on failure: returns undef

=cut

sub get_names {
    my $self = shift;
    $self->_init unless %{$self->{ids_by_name}};
    return keys %{$self->{ids_by_name}};
}

=head2 get_id

  * Purpose: Return property ID for a name
  * Expected parameters: property name
  * Function on success: returns ID for property name
  * Function on failure: returns undef

=cut

sub get_id {
    my $self = shift;
    my $name = shift;
    $self->_init unless %{$self->{ids_by_name}};
    return $self->{ids_by_name}->{$name};
}

=head2 get_name

  * Purpose: Return property name for an ID
  * Expected parameters: property ID
  * Function on success: returns property name for ID
  * Function on failure: returns undef

=cut

sub get_name {
    my $self = shift;
    my $id = shift;
    $self->_init unless %{$self->{ids_by_name}};
    return $self->{names_by_id}->{$id};
}

=head2 get_type

  * Purpose: Return property type for an ID
  * Expected parameters: property ID
  * Function on success: returns property type for ID
  * Function on failure: returns undef

=cut

sub get_type {
    my $self = shift;
    my $id = shift;
    $self->_init unless %{$self->{ids_by_name}};
    return $self->{types_by_id}->{$id};
}

=head1 PRIVATE METHODS

=head2 _init

=cut

sub _init {
    my $self = shift;
    my $ids = $self->{ids_by_name};
    my $names = $self->{names_by_id};
    my $types = $self->{types_by_id};

    my $r = $self->{dbh}->selectall_arrayref("SELECT * FROM properties");
    for (@$r) {
        my($id, $name, $type) = @$_;
        $ids->{$name} = $id;
        $names->{$id} = $name;
        $types->{$id} = $type;
    }
}

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.

=head1 SEE ALSO

L<TIDES>

=head1 AUTHOR

Ken Yamaguchi, C<< <ken at knowledgesynthesis.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Knowledge Synthesis Inc.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.

=cut

1;

__END__
