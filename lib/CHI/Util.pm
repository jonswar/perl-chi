package CHI::Util;

use Carp qw( croak longmess );
use Module::Runtime qw(require_module);
use Data::Dumper;
use Data::UUID;
use Fcntl qw( :DEFAULT );
use File::Spec::Functions qw(catdir catfile);
use JSON;
use Time::Duration::Parse;
use Try::Tiny;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
  can_load
  dump_one_line
  fast_catdir
  fast_catfile
  has_moose_class
  json_decode
  json_encode
  parse_duration
  parse_memory_size
  read_file
  read_dir
  unique_id
  write_file
);

my $Fetch_Flags = O_RDONLY | O_BINARY;
my $Store_Flags = O_WRONLY | O_CREAT | O_BINARY;

# Map null, true and false to real Perl values
if ( JSON->VERSION < 2 ) {
    $JSON::UnMapping = 1;
}

sub can_load {

    # Load $class_name if possible. Return 1 if successful, 0 if it could not be
    # found, and rethrow load error (other than not found).
    #
    my ($class_name) = @_;

    my $result;
    try {
        require_module($class_name);
        $result = 1;
    }
    catch {
        if ( /Can\'t locate .* in \@INC/ && !/Compilation failed/ ) {
            $result = 0;
        }
        else {
            die $_;
        }
    };
    return $result;
}

sub dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
}

# Simplified read_dir cribbed from File::Slurp
sub read_dir {
    my ($dir) = @_;

    ## no critic (RequireInitializationForLocalVars)
    local *DIRH;
    opendir( DIRH, $dir ) or croak "cannot open '$dir': $!";
    return grep { $_ ne "." && $_ ne ".." } readdir(DIRH);
}

sub read_file {
    my ($file) = @_;

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

sub write_file {
    my ( $file, $data, $file_create_mode ) = @_;
    $file_create_mode = oct(666) if !defined($file_create_mode);

    # Fast spew, adapted from File::Slurp::write, with unnecessary options removed
    #
    {
        my $write_fh;
        unless ( sysopen( $write_fh, $file, $Store_Flags, $file_create_mode ) )
        {
            croak "write_file '$file' - sysopen: $!";
        }
        my $size_left = length($data);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
            unless ( defined $write_cnt ) {
                croak "write_file '$file' - syswrite: $!";
            }
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
    }
}

{

    # For efficiency, use Data::UUID to generate an initial unique id, then suffix it to
    # generate a series of 0x10000 unique ids. Not to be used for hard-to-guess ids, obviously.

    my $uuid;
    my $suffix = 0;

    sub unique_id {
        if ( !$suffix || !defined($uuid) ) {
            my $ug = Data::UUID->new();
            $uuid = $ug->create_hex();
        }
        my $hex = sprintf( '%s%04x', $uuid, $suffix );
        $suffix = ( $suffix + 1 ) & 0xffff;
        return $hex;
    }
}

use constant _FILE_SPEC_USING_UNIX => ($File::Spec::ISA[0] eq 'File::Spec::Unix');

sub fast_catdir {
    if (_FILE_SPEC_USING_UNIX) {
        return join '/', @_;
    }
    else {
        return catdir(@_);
    }
}

sub fast_catfile {
    if (_FILE_SPEC_USING_UNIX) {
        return join '/', @_;
    }
    else {
        return catfile(@_);
    }
}

my %memory_size_units = ( 'k' => 1024, 'm' => 1024 * 1024 );

sub parse_memory_size {
    my $size = shift;
    if ( $size =~ /^\d+b?$/ ) {
        return $size;
    }
    elsif ( my ( $quantity, $unit ) = ( $size =~ /^(\d+)\s*([km])b?$/i ) ) {
        return $quantity * $memory_size_units{ lc($unit) };
    }
    else {
        croak "cannot parse memory size '$size'";
    }
}

# Maintain compatibility with both JSON 1 and 2. Borrowed from Data::Serializer::JSON.
#
use constant _OLD_JSON => JSON->VERSION < 2;
my $json = _OLD_JSON ? JSON->new : JSON->new->utf8->canonical;

sub json_decode {
    return _OLD_JSON
      ? $json->jsonToObj( $_[0] )
      : $json->decode( $_[0] );
}

sub json_encode {
    return _OLD_JSON
      ? $json->objToJson( $_[0] )
      : $json->encode( $_[0] );
}

1;

__END__
