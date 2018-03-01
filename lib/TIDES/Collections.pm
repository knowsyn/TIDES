
=head1 NAME

TIDES::Collections - Collections base class.

=head1 SYNOPSIS

    TIDES::Collections provides access to the database collections table.

=head1 ABSTRACT

Provide access to the database collections table.

=cut

package TIDES::Collections;

use warnings;
use strict;

=head1 PUBLIC METHODS

=head2 new

  * Purpose: Access database collections
  * Expected parameters: database handle
  * Function on success: returns Collections object
  * Function on failure: returns undef

=cut

sub new {
    my($type, %params) = @_;
    my $self = {
        dbh => $params{dbh},
        ids_by_name => {},
        names_by_id => {},
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

  * Purpose: Return collection ID for a name. Insert collection if necessary.
  * Expected parameters: collection name
  * Function on success: returns ID for collection name
  * Function on failure: returns undef

=cut

sub get_id {
    my $self  = shift;
    my $name  = shift;
    my $ids   = $self->{ids_by_name};
    my $names = $self->{names_by_id};
    $self->_init unless %$ids;
    my $id = $ids->{$name};
    return $id if $id;

    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare('INSERT INTO collections (name) VALUES (?)');
    $sth->execute($name) or return;
    $id = $dbh->last_insert_id(undef, undef, 'collections', undef);
    $ids->{$name} = $id;
    $names->{$id} = $name;
    return $id;
}

=head2 get_name

  * Purpose: Return collection name for an ID
  * Expected parameters: collection ID
  * Function on success: returns collection name for ID
  * Function on failure: returns undef

=cut

sub get_name {
    my $self = shift;
    my $id = shift;
    $self->_init unless %{$self->{ids_by_name}};
    return $self->{names_by_id}->{$id};
}

=head1 PRIVATE METHODS

=head2 _init

=cut

sub _init {
    my $self = shift;
    my $ids = $self->{ids_by_name};
    my $names = $self->{names_by_id};

    my $r = $self->{dbh}->selectall_arrayref("SELECT * FROM collections");
    for (@$r) {
        my($id, $name) = @$_;
        $ids->{$name} = $id;
        $names->{$id} = $name;
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
