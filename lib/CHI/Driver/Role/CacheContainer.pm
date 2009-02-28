package CHI::Driver::Role::CacheContainer;
use List::MoreUtils qw( all );
use Mouse::Role;
use Mouse::Util::TypeConstraints;
use strict;
use warnings;

subtype 'CacheObject' => as 'Object' => where {
    my $o = $_;
    all { $o->can($_) } qw( get set remove );
};

requires '_build_contained_cache';

has '_contained_cache' => (
    is      => 'ro',
    isa     => 'CacheObject',
    lazy    => 1,
    builder => '_build_contained_cache',
    handles => {
        fetch  => 'get',
        remove => 'remove',
    },
);

# These are implemented as separate subs so they can be excluded by
# consumers of the role.
sub store {
    my $self = shift;

    return $self->_contained_cache->set(@_);
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

no Mouse::Role;
no Mouse::Util::TypeConstraints;

1;

__END__

=pod

=head1 NAME

CHI::Driver::Role::CacheContainer

=head1 DESCRIPTION

Role for CHI drivers with an internal '_contained_cache' slot that itself adheres to
the Cache::Cache API, partially or completely.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
