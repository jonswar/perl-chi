package CHI::Driver::File;
use Carp;
use Cwd qw(realpath cwd);
use CHI::Types;
use CHI::Util qw(fast_catdir fast_catfile unique_id read_dir);
use Digest::JHash qw(jhash);
use Fcntl qw( :DEFAULT );
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
has 'key_digest' => ( is => 'ro', isa => 'CHI::Types::Digester', coerce => 1 );
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

my $Max_File_Length = 254;
my $Max_Path_Length = ( $^O eq 'MSWin32' ? 254 : 1023 );
my $Fetch_Flags     = O_RDONLY | O_BINARY;
my $Store_Flags     = O_WRONLY | O_CREAT | O_BINARY;

sub _build_path_to_namespace {
    my $self = shift;

    return catdir( $self->root_dir,
        $self->escape_for_filename( $self->namespace ) );
}

sub fetch {
    my ( $self, $key ) = @_;

    my $file = $self->path_to_key($key);
    return undef unless defined $file && -f $file;

    # Fast slurp, adapted from File::Slurp::read, with unnecessary options removed
    #
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, $Fetch_Flags ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s $read_fh;
    while (1) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );
        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }

    return $buf;
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

    # Fast spew, adapted from File::Slurp::write, with unnecessary options removed
    #
    {
        my $write_fh;
        unless (
            sysopen(
                $write_fh,    $store_file,
                $Store_Flags, $self->{file_create_mode}
            )
          )
        {
            croak "write_file '$store_file' - sysopen: $!";
        }
        my $size_left = length($data);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
            unless ( defined $write_cnt ) {
                croak "write_file '$store_file' - syswrite: $!";
            }
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
    }

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
    die "could not unlink '$file'" if -f $file;
}

sub clear {
    my ($self) = @_;

    my $namespace_dir = $self->path_to_namespace;
    rmtree($namespace_dir);
    die "could not remove '$namespace_dir'"
      if -d $namespace_dir;
}

sub get_keys {
    my ($self) = @_;

    die "get_keys not supported when key_digest is set"
      if $self->key_digest;

    my @filepaths;
    my $wanted = sub { push( @filepaths, $_ ) if -f && /\.dat$/ };
    my @keys = $self->_collect_keys_via_file_find( \@filepaths, $wanted );
    return @keys;
}

sub _collect_keys_via_file_find {
    my ( $self, $filepaths, $wanted ) = @_;

    die "cannot retrieve keys from filenames when key_digest is set"
      if $self->key_digest;

    my $namespace_dir = $self->path_to_namespace;
    return () if !-d $namespace_dir;

    find( { wanted => $wanted, no_chdir => 1 }, $namespace_dir );

    my @keys;
    my $key_start = length($namespace_dir) + 1 + $self->depth * 2;
    foreach my $filepath (@$filepaths) {
        my $key = substr( $filepath, $key_start, -4 );
        $key = $self->unescape_for_filename( join( "", splitdir($key) ) );
        push( @keys, $key );
    }
    return @keys;
}

sub generate_temporary_filename {
    my ( $self, $dir, $file ) = @_;

    # Generate a temporary filename using unique_id - faster than tempfile, as long as
    # we don't need automatic removal
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
    my $filename;
    if ( my $digester = $self->key_digest ) {
        $filename = $digester->add($key)->hexdigest;
        push( @paths,
            map { substr( $filename, $_, 1 ) } ( 0 .. $self->{depth} - 1 ) );
    }
    else {

        # Hash key to a 32-bit integer
        #
        my $bucket = jhash($key);

        # Create $self->{depth} subdirectories, containing a maximum of 64 subdirectories each,
        # by successively shifting 4 bits off the bucket and converting to hex.
        #
        for ( my $d = $self->{depth} ; $d > 0 ; $d-- ) {
            push( @paths, $hex_strings{ $bucket & 0xf } );
            $bucket >>= 4;
        }

        # Escape key to make safe for filesystem
        #
        $filename = $self->escape_for_filename($key);
        if ( length($filename) > $Max_File_Length ) {
            my $namespace = $self->{namespace};
            $log->warn(
                "escaped key '$key' in namespace '$namespace' is over $Max_File_Length chars; cannot cache"
            );
            return undef;
        }
    }
    $filename .= $self->file_extension;

    # Join paths together, computing dir separately if $dir_ref was passed.
    #
    my $filepath;
    if ( defined $dir_ref && ref($dir_ref) ) {
        my $dir = fast_catdir(@paths);
        $filepath = fast_catfile( $dir, $filename );
        $$dir_ref = $dir;
    }
    else {
        $filepath = fast_catfile( @paths, $filename );
    }

    if ( length($filepath) > $Max_Path_Length ) {
        my $namespace = $self->{namespace};
        $log->warn(
            "full escaped path for key '$key' in namespace '$namespace' is over $Max_Path_Length chars; cannot cache"
        );
        return undef;
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

    my $cache = CHI->new(driver => 'File', root_dir => '/path/to/cache/root', depth => 3);

=head1 DESCRIPTION

This cache driver stores data on the filesystem, so that it can be shared
between processes on a single machine, or even on multiple machines if using
NFS.

Each item is stored in its own file. By default, during a set, a temporary file
is created and then atomically renamed to the proper file. While not the most
efficient, it eliminates the need for locking (with multiple overlapping sets,
the last one "wins") and makes this cache usable in environments like NFS where
locking might normally be undesirable.

By default, the base filename is the key itself, with unsafe characters
replaced with an escape sequence similar to URI escaping. The filename length
is capped at 255 characters, which is the maximum for most Unix systems, so
gets/sets for keys that escape to longer than 255 characters will fail. You can
also use a digest of the key (e.g. MD5, SHA) for the base filename by
specifying L</key_digest>.

The files are evenly distributed within a multi-level directory structure with
a customizable depth, to minimize the time needed to search for a given entry.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in
addition to the L<CHI|general constructor options/constructor>.

=over

=item root_dir

The location in the filesystem that will hold the root of the cache.  Defaults
to a directory called 'chi-driver-file' under the OS default temp directory
(e.g. '/tmp' on UNIX). This directory will be created as needed on the first
cache set.

=item dir_create_mode

Permissions mode to use when creating directories. Defaults to 0775.

=item file_create_mode

Permissions mode to use when creating files, modified by the current umask.
Defaults to 0666.

=item file_extension

Extension to append to filename. Default is ".dat".

=item depth

The number of subdirectories deep to place cache files. Defaults to 2. This
should be large enough that no leaf directory has more than a few hundred
files. Each non-leaf directory contains up to 16 subdirectories (0-9, A-F).

=item key_digest [STRING|HASHREF|OBJECT]

Digest algorithm to use on the key before storing - e.g. "MD5", "SHA-1", or
"SHA-256".

Can be a L<Digest|Digest> object, or a string or hashref which will passed to
Digest->new(). You will need to ensure Digest is installed to use these
options. Also, L<CHI/get_keys> is currently not supported when a digest is
used, this will hopefully be fixed at a later date.

By default, no digest is performed and the entire key is used in the filename,
after escaping unsafe characters.

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
