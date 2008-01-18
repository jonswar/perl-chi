package CHI::Driver::File;
use strict;
use warnings;
use Carp;
use Cwd qw(realpath cwd);
use CHI::Util
  qw(escape_for_filename fast_catdir fast_catfile unescape_for_filename unique_id);
use Digest::JHash qw(jhash);
use Fcntl qw( :DEFAULT );
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Path qw(mkpath rmtree);
use File::Slurp qw(read_dir);
use File::Spec::Functions qw(catdir catfile splitdir tmpdir);
use base qw(CHI::Driver);

my $Default_Create_Mode = oct(775);
my $Default_Depth       = 2;
my $Default_Root_Dir    = catdir( tmpdir(), "chi-driver-file" );
my $Max_File_Length     = 254;

my $Fetch_Flags = O_RDONLY | O_BINARY;
my $Store_Flags = O_WRONLY | O_CREAT | O_BINARY;

__PACKAGE__->mk_ro_accessors(
    qw(dir_create_mode file_create_mode depth path_to_namespace root_dir));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{dir_create_mode}  ||= $Default_Create_Mode;
    $self->{file_create_mode} ||= $self->{dir_create_mode} & oct(666);
    $self->{depth}            ||= $Default_Depth;
    $self->{root_dir} ||=
      ( delete( $self->{cache_root} ) || $Default_Root_Dir );
    $self->{path_to_namespace} =
      catdir( $self->root_dir, escape_for_filename( $self->{namespace} ) );
    return $self;
}

sub desc {
    my $self = shift;

    return sprintf( "%s (%s)", $self->SUPER::desc(), $self->root_dir );
}

sub fetch {
    my ( $self, $key ) = @_;

    my $file = $self->path_to_key($key) or return undef;
    return unless -f $file;

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

    # Generate a temporary filename using unique_id - faster than tempfile, as long as
    # we don't need automatic removal
    #
    my $temp_file = fast_catfile( $dir, unique_id() );

    # Fast spew, adapted from File::Slurp::write, with unnecessary options removed
    #
    {
        my $write_fh;
        unless (
            sysopen(
                $write_fh,    $temp_file,
                $Store_Flags, $self->{file_create_mode}
            )
          )
        {
            croak "write_file '$temp_file' - sysopen: $!";
        }
        my $size_left = length($data);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
            unless ( defined $write_cnt ) {
                croak "write_file '$temp_file' - syswrite: $!";
            }
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
    }

    # Rename can fail in rare race conditions...try multiple times
    #
    for ( my $try = 0 ; $try < 10 ; $try++ ) {
        last if ( rename( $temp_file, $file ) );
    }
    if ( -f $temp_file ) {
        my $error = $!;
        unlink($temp_file);
        ## no critic (RequireCarping)
        die "could not rename '$temp_file' to '$file': $error";
    }
}

sub remove {
    my ( $self, $key ) = @_;

    my $file = $self->path_to_key($key) or return undef;
    unlink($file);
    ## no critic (RequireCarping)
    die "could not unlink '$file'" if -f $file;
}

sub clear {
    my ($self) = @_;

    my $namespace_dir = $self->{path_to_namespace};
    rmtree($namespace_dir);
    ## no critic (RequireCarping)
    die "could not remove '$namespace_dir'"
      if -d $namespace_dir;
}

sub get_keys {
    my ($self) = @_;

    my @filepaths;
    my $wanted = sub { push( @filepaths, $_ ) if -f && /\.dat$/ };
    return $self->_collect_keys_via_file_find( \@filepaths, $wanted );
}

sub _collect_keys_via_file_find {
    my ( $self, $filepaths, $wanted ) = @_;

    my $namespace_dir = $self->{path_to_namespace};
    return () if !-d $namespace_dir;

    find( { wanted => $wanted, no_chdir => 1 }, $namespace_dir );

    my @keys;
    my $key_start = length($namespace_dir) + 1 + $self->depth * 2;
    foreach my $filepath (@$filepaths) {
        my $key = substr( $filepath, $key_start, -4 );
        $key = unescape_for_filename( join( "", splitdir($key) ) );
        push( @keys, $key );
    }
    return @keys;
}

sub get_namespaces {
    my ($self) = @_;

    my @contents = read_dir( $self->root_dir() );
    my @namespaces =
      map { unescape_for_filename($_) }
      grep { -d fast_catdir( $self->root_dir(), $_ ) } @contents;
    return @namespaces;
}

my %hex_strings = map { ( $_, sprintf( "%x", $_ ) ) } ( 0x0 .. 0xf );

sub path_to_key {
    my ( $self, $key, $dir_ref ) = @_;

    my @paths = ( $self->{path_to_namespace} );

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
    my $filename = escape_for_filename($key) . ".dat";
    if ( length($filename) > $Max_File_Length ) {
        my $log       = CHI->logger();
        my $namespace = $self->{namespace};
        $log->warn(
            "key '$key' in namespace '$namespace' is over $Max_File_Length chars when escaped; cannot cache"
        );
        return undef;
    }

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

    return $filepath;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::File -- File-based cache using one file per entry in a multi-level directory structure

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(driver => 'File', root_dir => '/path/to/cache/root', depth => 3);

=head1 DESCRIPTION

This cache driver stores data on the filesystem, so that it can be shared between
processes on a single machine, or even on multiple machines if using NFS.

Each item is stored in its own file. During a set, a temporary file is created and then
atomically renamed to the proper file. While not the most efficient, it eliminates the
need for locking (with multiple overlapping sets, the last one "wins") and makes this
cache usable in environments like NFS where locking might normally be undesirable.

The base filename is the key itself, with unsafe characters replaced with an escape
sequence similar to URI escaping. The filename length is capped at 255 characters, which
is the maximum for most Unix systems, so gets/sets for keys that escape to longer than 255
characters will fail.

The files are evenly distributed within a multi-level directory structure with a
customizable depth, to minimize the time needed to search for a given entry.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in addition to the
L<CHI|general constructor options/constructor>.
    
=over

=item root_dir

The location in the filesystem that will hold the root of the cache.  Defaults to a
directory called 'chi-driver-file' under the OS default temp directory (e.g. '/tmp'
on UNIX).

For backward compatibility with Cache::FileCache, this can also be specified as C<cache_root>.

=item dir_create_mode

Permissions mode to use when creating directories. Defaults to 0775.

=item file_create_mode

Permissions mode to change cache files to after creation, using chmod, e.g. 0666 or
0664. Default is to not use chmod and just create files with the current umask.

=item depth

The number of subdirectories deep to place cache files. Defaults to 2. This should be
large enough that no leaf directory has more than a few hundred files. At present, each
non-leaf directory contains up to 16 subdirectories, meaning a potential of 256 leaf
directories.

=back
    
=head1 METHODS

=over

=item path_to_key ( $key )

Returns the full path to the cache file representing $key, whether or not that entry
exists. Returns the empty list if a valid path cannot be computed, for example if the key
is too long.

=item path_to_namespace

Returns the full path to the directory representing this cache's namespace, whether or not
it has any entries.

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
