package CHI::Driver::FastMmap;
use Cache::FastMmap;
use CHI::Util qw(dp);
use File::Path qw(mkpath);
use File::Slurp qw(read_dir);
use File::Spec::Functions qw(catdir catfile splitdir tmpdir);
use Moose;
use strict;
use warnings;

extends 'CHI::Driver::Base::CacheContainer';

has 'dir_create_mode' => ( is => 'ro', isa => 'Int', default => oct(775) );
has 'fm_cache'        => ( is => 'ro' );
has 'share_file'      => ( is => 'ro' );
has 'root_dir'        => (
    is      => 'ro',
    isa     => 'Str',
    default => catdir( tmpdir(), "chi-driver-fastmmap" )
);
has 'unlink_on_exit' => ( is => 'ro', isa => 'Int', default => 0 );

__PACKAGE__->meta->make_immutable();

sub BUILD {
    my ( $self, $params ) = @_;

    mkpath( $self->{root_dir}, 0, $self->{dir_create_mode} )
      if !-d $self->{root_dir};
    $self->{share_file} =
      catfile( $self->{root_dir},
        $self->escape_for_filename( $self->{namespace} ) );
    my %fm_params = (
        raw_values => 1,
        map { exists( $self->{$_} ) ? ( $_, $self->{$_} ) : () }
          qw(init_file unlink_on_exit share_file cache_size page_size num_pages)
    );
    $self->{_contained_cache} = $self->{fm_cache} =
      Cache::FastMmap->new(%fm_params);
}

sub get_keys {
    my ($self) = @_;

    return $self->{_contained_cache}->get_keys(0);
}

sub get_namespaces {
    my ($self) = @_;

    my @contents = read_dir( $self->root_dir() );
    my @namespaces =
      map { $self->unescape_for_filename($_) }
      grep { -d catdir( $self->root_dir(), $_ ) } @contents;
    return @namespaces;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::FastMmap -- Shared memory interprocess cache via mmap'ed files

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver     => 'FastMmap',
        root_dir   => '/path/to/cache/root',
        cache_size => '1m'
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

=item unlink_on_exit

Indicates whether L<Cache::FastMmap|Cache::FastMmap> should remove the cache when the
object is destroyed. We default this to 0 to conform to the CHI API (unlike Cache::FastMmap, 
which defaults it to 1 if the cache files doesn't already exist).

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

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
