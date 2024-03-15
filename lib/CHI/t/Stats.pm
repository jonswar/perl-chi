package CHI::t::Stats;

use strict;
use warnings;

use Log::Any::Test;
use Log::Any qw($log);
use IO::Scalar;
use CHI::Test;
use base qw(CHI::Test::Class);

sub test_stats : Tests {

    # use Log::Any::Test to avoid temporary files for stats
    ok( CHI->stats->enable(), 'enable stats' );
    my $cache = CHI->new( driver => 'Memory', global => 1, namespace => __PACKAGE__ );
    isa_ok( $cache, 'CHI::Driver' );
    $cache->set( 'a', 1 );
    ok( CHI->stats->flush(), 'flush stats' );
    CHI->stats->disable();

    # direct call for coverage, no other references
    CHI->stats->format_time( time() );

    # process collected stats
    my $msgs = $log->msgs;
    note( explain( $msgs ) );
    my $buffer = '';
    my $fh = IO::Scalar->new( \$buffer );
    foreach my $msg (@{$msgs}) {
	$fh->print( $msg->{'message'} . "\n" );
    }
    $fh->setpos( 0 );
    my $results = CHI->stats->parse_stats_logs( $fh );
    note( explain( $results ) );

    return;

}

1;
