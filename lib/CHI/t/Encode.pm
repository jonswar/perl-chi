# Test utf8 keys and values - some overlap with Driver.pm, but want to
# confirm our assumptions.
#
package CHI::t::Encode;
use strict;
use warnings;
use Encode qw(encode is_utf8);
use File::Temp qw(tempdir);
use CHI::Test;
use base qw(CHI::Test::Class);

my $root_dir = tempdir( "chi-encode-XXXX", TMPDIR => 1, CLEANUP => 1 );
my $cache = CHI->new( driver => 'File', root_dir => $root_dir );

sub test_encode : Tests(8) {
    my $smiley = "\x{263a}b";
    my $smiley_encoded = encode( utf8 => $smiley );

    # Key maps to same thing whether encoded or non-encoded
    #
    $cache->set( $smiley, $smiley );
    is( $cache->get($smiley), $smiley, "get" );
    is( $cache->get($smiley_encoded),
        $smiley, "encoded and non-encoded map to same value" );

    # Value is maintained as a utf8 or binary string, in scalar or in arrayref
    $cache->set( "utf8", $smiley );
    is( $cache->get("utf8"), $smiley, "utf8 in scalar" );
    $cache->set( "utf8", [$smiley] );
    is( $cache->get("utf8")->[0], $smiley, "utf8 in arrayref" );

    $cache->set( "binary", $smiley_encoded );
    is( $cache->get("binary"), $smiley_encoded, "binary in scalar" );
    $cache->set( "binary", [$smiley_encoded] );
    is( $cache->get("binary")->[0], $smiley_encoded, "binary in arrayref" );
}

1;
