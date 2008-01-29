package CHI::Driver::Base::CacheContainer;
use Moose;
use strict;
use warnings;

extends 'CHI::Driver';

sub fetch {
    my ( $self, $key ) = @_;

    return $self->{_contained_cache}->get($key);
}

sub store {
    my ( $self, $key, $data ) = @_;

    $self->{_contained_cache}->set( $key, $data );
}

sub remove {
    my ( $self, $key ) = @_;

    $self->{_contained_cache}->remove($key);
}

sub clear {
    my ($self) = @_;

    $self->{_contained_cache}->clear();
}

sub get_keys {
    my ($self) = @_;

    return $self->{_contained_cache}->get_keys();
}

sub get_namespaces {
    my ($self) = @_;

    return $self->{_contained_cache}->get_namespaces();
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Base::CacheContainer

=head1 DESCRIPTION

Base class for CHI drivers with an internal '_contained_cache' slot that itself adheres to
the Cache::Cache API, partially or completely.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
