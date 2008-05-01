package CHI::Driver::Memory;
use Moose;
use MooseX::AttributeHelpers;
use strict;
use warnings;

extends 'CHI::Driver';

my $Default_Datastore = {};

has 'datastore' => (
    metaclass => 'Collection::Hash',
    is        => 'ro',
    isa       => 'HashRef',
    default   => sub { $Default_Datastore },
    provides  => { keys => 'get_namespaces' },
);

has 'datastore_for_namespace' => (
    metaclass => 'Collection::Hash',
    is        => 'ro',
    isa       => 'HashRef',
    lazy      => 1,
    builder   => '_build_datastore_for_namespace',
    provides  => {
        get    => 'fetch',
        set    => 'store',
        delete => 'remove',
        clear  => 'clear',
        keys   => 'get_keys',
    },
);

__PACKAGE__->meta->make_immutable();

sub _build_datastore_for_namespace {
    my ($self) = @_;

    return $self->datastore->{ $self->namespace } ||= {};
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
