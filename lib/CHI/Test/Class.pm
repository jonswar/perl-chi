package CHI::Test::Class;
use CHI::Util;
use Getopt::Long;
use Module::Find qw(findallmod);
use strict;
use warnings;
use base qw(Test::Class);

sub load_tests {
    my ($class) = @_;

    my $test_class_pattern;
    if ( defined( $test_class_pattern = $ENV{TEST_CLASS} ) ) {
        $test_class_pattern =~ s{/}{::}g;
    }
    my @classes;
    my @candidates = findallmod('CHI::t');

    foreach my $class (@candidates) {
        next
          if defined($test_class_pattern) && $class !~ /$test_class_pattern/o;
        eval "require $class";
        die $@ if $@;
    }
    if ( $ENV{TEST_STACK_TRACE} ) {

        # Show entire stack trace when testing aborts with fatal error
        $SIG{'__DIE__'}  = sub { Carp::confess(@_) };
        $SIG{'__WARN__'} = sub { Carp::confess(@_) };
    }
    return @classes;
}

sub runtests {
    my ($class) = @_;

    # Handle -m flag in case test script is being run directly.
    #
    GetOptions( 'm|method=s' => sub { $ENV{TEST_METHOD} = ".*" . $_[1] . ".*" },
    );

    # Only run tests directly in $class.
    #
    my $test_obj = $class->new();
    Test::Class::runtests($test_obj);
}

1;
