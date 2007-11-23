package CHI::Driver::CacheCache;
use strict;
use warnings;
use Cache::Cache;
use Carp;
use CHI::Util;
use Hash::MoreUtils qw(slice_exists);
use base qw(CHI::Driver::Base::CacheContainer);

__PACKAGE__->mk_ro_accessors(qw(cc_class cc_options));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    my $cc_class = $self->{cc_class}
      or croak "missing required parameter 'cc_class'";
    my $cc_options = $self->{cc_options}
      or croak "missing required parameter 'cc_options'";
    my %subparams = slice_exists( $_[0], 'namespace' );

    eval "require $cc_class";
    die $@ if $@;

    $self->{_contained_cache} = $self->{cc_cache} =
      $cc_class->new( { %subparams, %{$cc_options} } );

    return $self;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::CacheCache -- CHI wrapper for Cache::Cache

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver     => 'CacheCache',
        cc_class   => 'Cache::FileCache',
        cc_options => { cache_root => '/path/to/cache/root' },
    );

=head1 DESCRIPTION

This cache driver uses Cache::FastMmap to store data in an mmap'ed file. It is very fast,
and can be used to share data between processes on a single host, though not between hosts.

To support namespaces, this driver takes a directory parameter rather than a file, and
creates one Cache::FastMMap file for each namespace. Because CHI handles serialization
automatically, we pass the C<raw_values> flag.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item root_dir

Path to the directory that will contain the share files, one per namespace. Defaults to a
directory called 'chi-driver-fastmmap' under the OS default temp directory (e.g. '/tmp'
on UNIX).

=item dir_create_mode

Permissions mode to use when creating directories. Defaults to 0775.

=item cache_size
=item page_size
=item num_pages
=item init_file

These options are passed directly to L<Cache::FastMmap>.

=back

=head1 METHODS

=over

=item fm_cache

Returns a handle to the underlying Cache::FastMmap object. You can use this to call
FastMmap-specific methods that are not supported by the general API, e.g.

    $self->fm_cache->get_and_set("key", sub { ... });

=back

=head1 SEE ALSO

Cache::FastMmap
CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
