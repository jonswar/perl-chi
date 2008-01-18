package CHI::Driver::Memcached;
use strict;
use warnings;
use Cache::Memcached;
use Carp;
use base qw(CHI::Driver::Base::CacheContainer);

__PACKAGE__->mk_ro_accessors(
    qw(compress_threshold debug memd no_rehash servers));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    my %mc_params =
      ( map { exists( $self->{$_} ) ? ( $_, $self->{$_} ) : () }
          qw(compress_threshold debug namespace no_rehash servers) );
    $self->{_contained_cache} = $self->{memd} =
      Cache::Memcached->new( \%mc_params );

    return $self;
}

# Memcached supports fast multiple get
#

sub get_multi_hashref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $keyvals = $self->{memd}->get_multi(@$keys);
    foreach my $key ( keys(%$keyvals) ) {
        if ( defined $keyvals->{$key} ) {
            $keyvals->{$key} = $self->get( $key, data => $keyvals->{$key} );
        }
    }
    return $keyvals;
}

sub get_multi_arrayref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $keyvals = $self->get_multi_hashref($keys);
    return [ map { $keyvals->{$_} } @$keys ];
}

# Not supported
#

sub get_keys {
    carp "get_keys not supported for " . __PACKAGE__;
}

sub get_namespaces {
    carp "get_namespaces not supported for " . __PACKAGE__;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Memcached -- Distributed cache via memcached (memory cache daemon)

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver => 'Memcached',
        servers => [ "10.0.0.15:11211", "10.0.0.15:11212", "/var/sock/memcached",
        "10.0.0.17:11211", [ "10.0.0.17:11211", 3 ] ],
        debug => 0,
        compress_threshold => 10_000,
    );

=head1 DESCRIPTION

This cache driver uses Cache::Memcached to store data in the specified memcached server(s).

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item cache_size
=item page_size
=item num_pages
=item init_file

These options are passed directly to L<Cache::Memcached>.

=back

=head1 METHODS

=over

=item memd

Returns a handle to the underlying Cache::Memcached object. You can use this to call memcached-specific methods that
are not supported by the general API, e.g.

    $self->memd->incr("key");
    my $stats = $self->memd->stats();

=back

=head1 SEE ALSO

Cache::Memcached
CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
