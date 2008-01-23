#!perl -w
use strict;
use warnings;
use lib 't/lib';
use CHI::t::Driver::Memcached;
CHI::t::Driver::Memcached->runtests;
