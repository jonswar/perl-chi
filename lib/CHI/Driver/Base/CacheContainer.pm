package CHI::Driver::Base::CacheContainer;
use Moose;
use Moose::Util::TypeConstraints;
use List::MoreUtils qw( all );
use strict;
use warnings;

extends 'CHI::Driver';

has '_contained_cache' => ( is => 'ro' );

__PACKAGE__->meta->make_immutable();

sub fetch {
    my ( $self, $key ) = @_;

    return scalar( $self->_contained_cache->get($key) );
}

sub store {
    my $self = shift;

    return $self->_contained_cache->set(@_);
}

sub remove {
    my ( $self, $key ) = @_;

    $self->_contained_cache->remove($key);
}

sub clear {
    my $self = shift;

    return $self->_contained_cache->clear(@_);
}

sub get_keys {
    my $self = shift;

    return $self->_contained_cache->get_keys(@_);
}

sub get_namespaces {
    my $self = shift;

    return $self->_contained_cache->get_namespaces(@_);
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Role::CacheContainer

=head1 DESCRIPTION

Role for CHI drivers with an internal '_contained_cache' slot that itself
adheres to the Cache::Cache API, partially or completely.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
