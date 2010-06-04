package CHI::Driver::File;
use Carp;
use Cwd qw(realpath cwd);
use CHI::Types;
use CHI::Util
  qw(fast_catdir fast_catfile unique_id read_dir read_file write_file);
use Digest::JHash qw(jhash);
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitdir tmpdir);
use Log::Any qw($log);
use Moose;
use strict;
use warnings;

extends 'CHI::Driver';

has 'depth'            => ( is => 'ro', isa => 'Int', default => 2 );
has 'dir_create_mode'  => ( is => 'ro', isa => 'Int', default => oct(775) );
has 'file_create_mode' => ( is => 'ro', isa => 'Int', default => oct(666) );
has 'file_extension'   => ( is => 'ro', isa => 'Str', default => '.dat' );
has '+max_key_length' => ( default => 248 );
has 'root_dir' => (
    is      => 'ro',
    isa     => 'Str',
    default => catdir( tmpdir(), 'chi-driver-file' ),
);
has 'path_to_namespace' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_path_to_namespace',
);

__PACKAGE__->meta->make_immutable();

sub BUILDARGS {
    my ( $class, %params ) = @_;

    # Backward compat
    #
    if ( defined( $params{key_digest} ) ) {
        $params{key_digester}   = $params{key_digest};
        $params{max_key_length} = 0;
    }

    return \%params;
}

sub _build_path_to_namespace {
    my $self = shift;

    my $namespace = $self->escape_for_filename( $self->namespace );
    $namespace = $self->digest_key($namespace)
      if length($namespace) > $self->max_key_length;
    return catdir( $self->root_dir, $namespace );
}

# Escape key to make safe for filesystem; if it then grows larger than
# max_key_length, digest it.
#
sub escape_key {
    my ( $self, $key ) = @_;

    my $new_key = $self->escape_for_filename($key);
    if (   length($new_key) > length($key)
        && length($new_key) > $self->max_key_length() )
    {
        $new_key = $self->digest_key($new_key);
    }
    return $new_key;
}

sub unescape_key {
    my ( $self, $key ) = @_;

    return $self->unescape_for_filename($key);
}

sub fetch {
    my ( $self, $key ) = @_;

    my $file = $self->path_to_key($key);
    if ( defined $file && -f $file ) {
        return read_file($file);
    }
    else {
        return undef;
    }
}

sub store {
    my ( $self, $key, $data ) = @_;

    my $dir;
    my $file = $self->path_to_key( $key, \$dir ) or return undef;

    mkpath( $dir, 0, $self->{dir_create_mode} ) if !-d $dir;

    # Possibly generate a temporary file - if generate_temporary_filename returns undef,
    # store to the destination file directly
    #
    my $temp_file = $self->generate_temporary_filename( $dir, $file );
    my $store_file = defined($temp_file) ? $temp_file : $file;

    write_file( $store_file, $data, $self->{file_create_mode} );

    if ( defined($temp_file) ) {

        # Rename can fail in rare race conditions...try multiple times
        #
        for ( my $try = 0 ; $try < 3 ; $try++ ) {
            last if ( rename( $temp_file, $file ) );
        }
        if ( -f $temp_file ) {
            my $error = $!;
            unlink($temp_file);
            die "could not rename '$temp_file' to '$file': $error";
        }
    }
}

sub remove {
    my ( $self, $key ) = @_;

    my $file = $self->path_to_key($key) or return undef;
    unlink($file);
}

sub clear {
    my ($self) = @_;

    my $namespace_dir = $self->path_to_namespace;
    return if !-d $namespace_dir;
    my $renamed_dir = join( ".", $namespace_dir, unique_id() );
    rename( $namespace_dir, $renamed_dir );
    rmtree($renamed_dir);
    die "could not remove '$renamed_dir'"
      if -d $renamed_dir;
}

sub get_keys {
    my ($self) = @_;

    my @filepaths;
    my $wanted = sub { push( @filepaths, $_ ) if -f && /\.dat$/ };
    my @keys = $self->_collect_keys_via_file_find( \@filepaths, $wanted );
    return @keys;
}

sub _collect_keys_via_file_find {
    my ( $self, $filepaths, $wanted ) = @_;

    my $namespace_dir = $self->path_to_namespace;
    return () if !-d $namespace_dir;

    find( { wanted => $wanted, no_chdir => 1 }, $namespace_dir );

    my @keys;
    my $key_start = length($namespace_dir) + 1 + $self->depth * 2;
    foreach my $filepath (@$filepaths) {
        my $key = substr( $filepath, $key_start, -4 );
        $key = $self->unescape_key( join( "", splitdir($key) ) );
        push( @keys, $key );
    }
    return @keys;
}

sub generate_temporary_filename {
    my ( $self, $dir, $file ) = @_;

    # Generate a temporary filename using unique_id - faster than tempfile, as long as
    # we don't need automatic removal.
    # Note: $file not used here, but might be used in an override.
    #
    return fast_catfile( $dir, unique_id() );
}

sub get_namespaces {
    my ($self) = @_;

    my $root_dir = $self->root_dir();
    return () if !-d $root_dir;
    my @contents = read_dir($root_dir);
    my @namespaces =
      map  { $self->unescape_for_filename($_) }
      grep { $self->is_escaped_for_filename($_) }
      grep { -d fast_catdir( $root_dir, $_ ) } @contents;
    return @namespaces;
}

my %hex_strings = map { ( $_, sprintf( "%x", $_ ) ) } ( 0x0 .. 0xf );

sub path_to_key {
    my ( $self, $key, $dir_ref ) = @_;

    my @paths = ( $self->path_to_namespace );

    my $orig_key = $key;
    $key = $self->escape_key($key);

    # Hack: If key is exactly 32 hex chars, assume it's an md5 digest and
    # take a prefix of it for bucket. Digesting will usually happen in
    # transform_key and there's no good way for us to know it occurred.
    #
    if ( $key =~ /^[0-9a-f]{32}$/ ) {
        push( @paths,
            map { substr( $key, $_, 1 ) } ( 0 .. $self->{depth} - 1 ) );
    }
    else {

        # Hash key to a 32-bit integer (using non-escaped key for back compat)
        #
        my $bucket = jhash($orig_key);

        # Create $self->{depth} subdirectories, containing a maximum of 64
        # subdirectories each, by successively shifting 4 bits off the
        # bucket and converting to hex.
        #
        for ( my $d = $self->{depth} ; $d > 0 ; $d-- ) {
            push( @paths, $hex_strings{ $bucket & 0xf } );
            $bucket >>= 4;
        }
    }

    # Join paths together, computing dir separately if $dir_ref was passed.
    #
    my $filename = $key . $self->file_extension;
    my $filepath;
    if ( defined $dir_ref && ref($dir_ref) ) {
        my $dir = fast_catdir(@paths);
        $filepath = fast_catfile( $dir, $filename );
        $$dir_ref = $dir;
    }
    else {
        $filepath = fast_catfile( @paths, $filename );
    }

    return $filepath;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::File -- File-based cache using one file per entry in a multi-level
directory structure

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(
        driver         => 'File',
        root_dir       => '/path/to/cache/root',
        depth          => 3,
        max_key_length => 64
    );

=head1 DESCRIPTION

This cache driver stores data on the filesystem, so that it can be shared
between processes on a single machine, or even on multiple machines if using
NFS.

Each item is stored in its own file. By default, during a set, a temporary file
is created and then atomically renamed to the proper file. While not the most
efficient, it eliminates the need for locking (with multiple overlapping sets,
the last one "wins") and makes this cache usable in environments like NFS where
locking might normally be undesirable.

By default, the base filename is the key itself, with unsafe characters escaped
similar to URL escaping. If the escaped key is larger than L</max_key_length>
(default 248 characters), it will be L<digested|CHI/key_digester>. You may want
to lower L</max_key_length> if you are storing a lot of items as long filenames
can be more expensive to work with.

The files are evenly distributed within a multi-level directory structure with
a customizable L</depth>, to minimize the time needed to search for a given
entry.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in
addition to the L<CHI|general constructor options/constructor>.

=over

=item root_dir

The location in the filesystem that will hold the root of the cache.  Defaults
to a directory called 'chi-driver-file' under the OS default temp directory
(e.g. '/tmp' on UNIX). This directory will be created as needed on the first
cache set.

=item depth

The number of subdirectories deep to place cache files. Defaults to 2. This
should be large enough that no leaf directory has more than a few hundred
files. Each non-leaf directory contains up to 16 subdirectories (0-9, A-F).

=item dir_create_mode

Permissions mode to use when creating directories. Defaults to 0775.

=item file_create_mode

Permissions mode to use when creating files, modified by the current umask.
Defaults to 0666.

=item file_extension

Extension to append to filename. Default is ".dat".

=back
    
=head1 METHODS

=over

=item path_to_key ( $key )

Returns the full path to the cache file representing $key, whether or not that
entry exists. Returns the empty list if a valid path cannot be computed, for
example if the key is too long.

=item path_to_namespace

Returns the full path to the directory representing this cache's namespace,
whether or not it has any entries.

=back

=head1 TEMPORARY FILE RENAME

By default, during a set, a temporary file is created and then atomically
renamed to the proper file.  This eliminates the need for locking. You can
subclass and override method I<generate_temporary_filename> to either change
the path of the temporary filename, or skip the temporary file and rename
altogether by having it return undef.

=head1 SEE ALSO

L<CHI|CHI>

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
