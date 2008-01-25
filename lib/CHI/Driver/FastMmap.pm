package CHI::Driver::FastMmap;
use strict;
use warnings;
use Cache::FastMmap;
use CHI::Util qw(escape_for_filename unescape_for_filename);
use File::Path qw(mkpath);
use File::Slurp qw(read_dir);
use File::Spec::Functions qw(catdir catfile splitdir tmpdir);
use base qw(CHI::Driver::Base::CacheContainer);

my $Default_Root_Dir = catdir( tmpdir(), "chi-driver-fastmmap" );
my $Default_Create_Mode = oct(775);

__PACKAGE__->mk_ro_accessors(qw(dir_create_mode fm_cache share_file root_dir));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->{root_dir}        ||= $Default_Root_Dir;
    $self->{dir_create_mode} ||= $Default_Create_Mode;
    $self->{unlink_on_exit}  ||= 0;
    mkpath( $self->{root_dir}, 0, $self->{dir_create_mode} )
      if !-d $self->{root_dir};
    $self->{share_file} =
      catfile( $self->{root_dir}, escape_for_filename( $self->{namespace} ) );
    my %fm_params = (
        raw_values => 1,
        map { exists( $self->{$_} ) ? ( $_, $self->{$_} ) : () }
          qw(init_file unlink_on_exit share_file cache_size page_size num_pages)
    );
    $self->{_contained_cache} = $self->{fm_cache} =
      Cache::FastMmap->new(%fm_params);

    return $self;
}

sub get_keys {
    my ($self) = @_;

    return $self->{_contained_cache}->get_keys(0);
}

sub get_namespaces {
    my ($self) = @_;

    my @contents = read_dir( $self->root_dir() );
    my @namespaces =
      map { unescape_for_filename($_) }
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
