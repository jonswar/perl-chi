package CHI::Driver::Memory;
use strict;
use warnings;
use base qw(CHI::Driver);

my $Default_Datastore = {};

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{datastore} ||= $Default_Datastore;
    $self->{datastore}->{ $self->namespace } ||= {};
    $self->{datastore_for_namespace} = $self->{datastore}->{ $self->namespace };
    return $self;
}

sub fetch {
    my ( $self, $key ) = @_;

    return $self->{datastore_for_namespace}->{$key};
}

sub store {
    my ( $self, $key, $data ) = @_;

    $self->{datastore_for_namespace}->{$key} = $data;
}

sub remove {
    my ( $self, $key ) = @_;

    delete $self->{datastore_for_namespace}->{$key};
}

sub clear {
    my ($self) = @_;

    $self->{datastore_for_namespace} =
      $self->{datastore}->{ $self->namespace } = {};
}

sub get_keys {
    my ($self) = @_;

    return keys( %{ $self->{datastore_for_namespace} } );
}

sub get_namespaces {
    my ($self) = @_;

    return keys( %{ $self->{datastore} } );
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Memory -- In-process memory based cache.

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(driver => 'Memory');

    my $hash = {};
    my $cache = CHI->new(driver => 'Memory', datastore => $hash);

=head1 DESCRIPTION

This cache driver stores data on a per-process basis.  This is the fastest of the cache
implementations, but data can not be shared between processes.  Data will remain in the
cache until cleared, expired, or the process dies.

To maintain the same semantics as other caches, data structures are deep-copied on set and
get. Thus, modifications to the original data structure will not affect the data structure
stored in the cache, and vica versa.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item datastore

A hash to be used for storage. Within the hash, each namespace is used as a key to a
second-level hash.  This hash may be passed to multiple CHI::Driver::Memory constructors.
By default a single global hash will be used.

For example, it can be useful to create a memory cache that lasts for a single web
request. If you using a web framework with a request object which goes out of scope at the
end of the page request, you can hang a datastore off of that request object.  e.g.

    $r->notes('memory_cache_datastore', {});
    ...
    my $cache = CHI->new(driver => 'Memory', datastore => $r->notes('memory_cache_datastore'));

This eliminates the danger of "forgetting" to clear the cache at the end of the request.

=back

=head1 SEE ALSO

CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
