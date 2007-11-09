#!/usr/bin/env perl
#
# Rob Mueller's script for benchmarking cache modules, modified to include CHI
# From http://cpan.robm.fastmail.fm/cacheperl.pl
#
use File::Slurp;
use FindBin::libs;
use Time::HiRes qw(gettimeofday tv_interval);
use Storable qw(freeze thaw);
use Data::Dumper;
use strict;
use warnings;
$| = 1;

#----- Setup stuff

my $pkgspec = $ARGV[0];

use vars qw($DBSpec $DBUser $DBPassword $InnoDB);

# Your DBI DB details
#	$DBSpec = 'dbi:mysql:...';
#	$DBUser = '...';
#	$DBPassword = '...';
#	$InnoDB = 0;

srand(1);

# Number of runs to perform
my $Runs = 1;

# Maximum number of values to generate to store in cache
my $MaxVals = 1000;

# Number of times to get/set in each run
my $NSetItems = 500;
my $NGetItems = 1000;
my $NMixItems = 1000;

# When getting, pick definitely stored keys this often
my $TestHitRate = 0.85;
# If mix mode, make reads this often
my $MixReadRatio = 0.85;

# Build data sets of various complexity
my (@DataComplex, @DataBin);

if (-f "cpdata.dat") {
  my $frozen_data = read_file("cpdata.dat");
  my $data = thaw($frozen_data);
  @DataComplex = @{$data->[0]};
  @DataBin     = @{$data->[1]};
}
else {
  for my $Depth (0 .. 2) {
    my @Structs = map { BuildStruct($Depth, $Depth+5) } 1 .. $MaxVals;
    push @DataComplex,  \@Structs;
    my @Frozen = map { freeze($_) } @Structs;
    push @DataBin, \@Frozen;
  }

  my $frozen_data = freeze([\@DataComplex, \@DataBin]);
  write_file("cpdata.dat", $frozen_data);
}

# Recursive helper call
sub BuildStruct {
  my ($Depth, $NItems) = @_;

  my $Struct = {};

  # Alter slightly from base number of items passed
  $NItems += int(rand(3))-1;

  # Generate given number of items in hash struct
  for (my $i = 0; $i < $NItems; $i++) {
    my $Key = RandVal(1);

    my $Type = int(rand(10));
    if ($Type < 4) {
      $Struct->{$Key} = RandVal();
    } elsif ($Type < 7) {
      $Struct->{$Key} = [ map { RandVal() } 1 .. int(rand($NItems)) ];
    } else {
      $Struct->{$Key} = $Depth ? BuildStruct($Depth-1, $NItems) : RandVal();
    }
  }

  return $Struct;
}

# Generate random perl value (either int, float, string or undef)
sub RandVal {
  my $NotUndef = shift;

  my $Type = int(rand(10));
  if ($Type < 3) {
    return rand(100);
  } elsif ($Type < 6) {
    return int(rand(1000000));
  } elsif ($Type < 9 || $NotUndef) {
    return join '', map { chr(ord('A') + int(rand(26))) } 1 .. int(rand(20));
  } else {
    return undef;
  }
}

sub CheckComplex {
  keys %{$_[0]} == keys %{$_[1]}
    || die "Mismatch for package - " . $_[2];
}

sub CheckBin {
  $_[0] eq $_[1]
    || die "Mismatch for package - " . $_[2];
}

# Packages to run through
my @Packages = (
  CB0_InProcHash => [ 'bin' ],
#  CB1_CacheMmap => [ 'bin', num_pages => 11, page_size => 65536 ],
#  CB1_CacheMmap => [ 'bin', num_pages => 89, page_size => 8192 ],
  CB2_CacheFastMmap => [ 'bin', num_pages => 11, page_size => 65536 ],
  CB2_CacheFastMmap => [ 'bin', num_pages => 89, page_size => 8192 ],
#  CB3_MLDBMSyncSDBM_File => [ 'bin' ],
#  CC3_BerkeleyDB => [ 'bin' ],
#  CB4_IPCMM => [ 'bin' ],
 CB9_CHIFile => [ 'bin' ],

#  CC0_InProcHashStorable => [ 'complex' ],
#  CC1_CacheMmapStorable => [ 'complex', num_pages => 89, page_size => 8192 ],
#  CC2_CacheFastMmapStorable => [ 'complex', num_pages => 89, page_size => 8192 ],
#  CC3_MLDBMSyncSDBM_FileStorable => [ 'complex' ],
#  CC3_BerkeleyDBStorable => [ 'complex' ],
#  CC4_IPCMMStorable => [ 'complex' ],
 CC5_CacheFileCacheStorable => [ 'complex' ],
#	  CC6_CacheSharedMemoryCacheStorable => [ 'complex' ],
#  ($DBSpec ? (
#    CC7_DBIStorable => [ 'complex' ],
#    CC8_DBIStorableUpdate => [ 'complex' ],
#  ) : ()),
 CC9_CHIFileStorable => [ 'complex' ],
);

#----- Now do runs

# Repeat each package type
while (my ($Package, $PackageOpts) = splice @Packages, 0, 2) {

  next if defined($pkgspec) && $Package !~ /$pkgspec/;

  print "$Package\n";
  
  # Get package options
  my ($DataType, @Params) = @$PackageOpts;
  my ($Check, $Data);

  # Set data and check routine based on data type
  if ($DataType eq 'bin') {
    $Check = \&CheckBin;
    $Data = \@DataBin;
  } else {
    $Check = \&CheckComplex;
    $Data = \@DataComplex;
  }

  my $Name = $Package->name();
  print "Package: $Name\nData type: $DataType\nParams: @Params\n";

  printf(" %5s | %6s | %6s | %6s | %5s | %5s\n", qw(Cmplx Set/S Get/S Mix/S GHitR MHitR));
  printf("-------|--------|--------|--------|-------|------\n");

  # Run for each data set size
  for my $DataSet (@$Data) {

    # Basic data complexity metric
    my $Complexity;
    for (@$DataSet) { 
      if (ref $_) {
        my @Hashes = $_;
        while (my $Hash = shift @Hashes) {
          $Complexity += keys %$Hash;
          push @Hashes, grep { ref($_) eq 'HASH' } values %$Hash;
        }
      } else {
        $Complexity += length($_);
      }
    }
    $Complexity /= scalar(@$DataSet);

    # Store times
    my ($SetTime, $GetTime, $MixTime, $Name);

    # And hit rate
    my (%StoreData, $GetRead, $GetHit, $MixRead, $MixHit);

    # Do runs
    for (my $Run = 0; $Run < $Runs; $Run++) {

      my $c = $Package->new(@Params);

      # Store keys
      my $t0 = [gettimeofday];
      for (my $i = 0; $i < $NSetItems; $i++) {
        my $k = "abc" . ($i * 103) . "defg";
        my $x = $i % $MaxVals;
        $c->set($k, $DataSet->[$x]);
        $StoreData{$k} = $x;
      }
      my $t1 = [gettimeofday];

      my @SetKeys = keys %StoreData;

      # Get keys
      for (my $i = $NGetItems-1; $i >= 0; $i--) {

        my $k;
        if (rand() < $TestHitRate) {
          $k = $SetKeys[rand(@SetKeys)];
          $GetRead++;
        } else {
          $k = "abcd" . ($i * 103) . "efg";
        }
        my $y = $c->get($k);
        if (defined $y) {
          $GetHit++;
        } else {
          my $o = $StoreData{$k};
          defined $o || next;
          $y = $DataSet->[$o];
        }

        # Reality check, not much of a check...
        $Check->($y, $DataSet->[$StoreData{$k}]);
      }
      my $t2 = [gettimeofday];

      # Now do mix
      for (my $i = 0; $i < $NMixItems; $i++) {
        my $k;
        if (rand() < $MixReadRatio) {

          if (rand() < $TestHitRate) {
            $k = $SetKeys[rand(@SetKeys)];
            $MixRead++;
          } else {
            $k = "abcd" . ($i * 103) . "efg";
          }
          my $y = $c->get($k);
          if (defined $y) {
            $MixHit++;
          } else {
            my $o = $StoreData{$k};
            defined $o || next;
            $y = $DataSet->[$o];
          }

          # Reality check, not much of a check...
          $Check->($y, $DataSet->[$StoreData{$k}]);

        } else {
          $k = $SetKeys[rand(@SetKeys)];
          $c->set($k, $DataSet->[$StoreData{$k}]);
        }
      }
      my $t3 = [gettimeofday];

      # Add to run times
      $SetTime += tv_interval($t0, $t1);
      $GetTime += tv_interval($t1, $t2);
      $MixTime += tv_interval($t2, $t3);

    }


    my $SetRate = int ($NSetItems*$Runs / $SetTime);
    my $GetRate = int ($NGetItems*$Runs / $GetTime);
    my $MixRate = int ($NMixItems*$Runs / $MixTime);

    my $GHitRate = $GetHit/$GetRead;
    my $MHitRate = $MixHit/$MixRead;

    printf(" %5d | %6d | %6d | %6d | %5.3f | %5.3f\n",
      $Complexity, $SetRate, $GetRate, $MixRate, $GHitRate, $MHitRate);

  }
  print "\n";

}

exit(0);

package CB0_InProcHash;

sub name { return "In process hash"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {};

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{$_[1]} = $_[2];
}

sub get {
  return $_[0]->{$_[1]};
}
1;
package CC0_InProcHashStorable;
use Storable qw(freeze thaw);

sub name { return "Storable freeze/thaw"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {};

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{$_[1]} = freeze($_[2]);
}

sub get {
  return thaw($_[0]->{$_[1]});
}

1;

package CB2_CacheFastMmap;
use Cache::FastMmap;

sub name { return "Cache::FastMmap"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  my $File = ($Args{vol} || (-e '/tmpfs' ? '/tmpfs' : '/tmp')) . "/fcachefile";
  my $Self = {
    Cache => Cache::FastMmap->new(
      share_file => $File,
      init_file => 1,
      ($Args{page_size} ? (page_size => $Args{page_size}) : ()),
      ($Args{num_pages} ? (num_pages => $Args{num_pages}) : ()),
      raw_values => 1
    )
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->set($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->get($_[1]);
}

1;
package CC2_CacheFastMmapStorable;
use Cache::FastMmap;

sub name { return "Cache::FastMmap Storable"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  my $File = ($Args{vol} || (-e '/tmpfs' ? '/tmpfs' : '/tmp')) . "/fcachefile";
  my $Self = {
    Cache => Cache::FastMmap->new(
      share_file => $File,
      init_file => 1,
      ($Args{page_size} ? (page_size => $Args{page_size}) : ()),
      ($Args{num_pages} ? (num_pages => $Args{num_pages}) : ()),
      raw_values => 0
    )
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->set($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->get($_[1]);
}

1;

package CC3_BerkeleyDBStorable;
use Storable qw(freeze thaw);
use BerkeleyDB;
use Fcntl qw(:DEFAULT);

sub name { return "BerkeleyDB Storable"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink glob('/tmpfs/bdbfile*');
  my %Cache;
  my $env = new BerkeleyDB::Env(
      -Home  => '/tmp',
      -Flags => DB_INIT_CDB | DB_CREATE | DB_INIT_MPOOL,
     #-Cachesize => 23152000,
      )
      or die "can't create BerkelyDB::Env: $!";
  my $Obj = tie %Cache, 'BerkeleyDB::Btree',
     -Filename => '/tmpfs/bdbfile',
     -Flags    => DB_CREATE,
     -Mode     => 0640,
     -Env      => $env
     or die ("Can't tie to /tmp/bdbdfile: $!");

  my $Self = {
    Cache => \%Cache,
    Obj => $Obj
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Obj}->db_put( $_[1], freeze($_[2]) );
}

sub get {
  my $value;
  $_[0]->{Obj}->db_get( $_[1], $value );
  return thaw( $value );
}

1;

package CC3_BerkeleyDB;
use BerkeleyDB;
use Fcntl qw(:DEFAULT);

sub name { return "BerkeleyDB"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink glob('/tmpfs/bdbfile*');
  my %Cache;
  my $env = new BerkeleyDB::Env(
      -Home  => '/tmp',
      -Flags => DB_INIT_CDB | DB_CREATE | DB_INIT_MPOOL,
     #-Cachesize => 23152000,
      )
      or die "can't create BerkelyDB::Env: $!";
  my $Obj = tie %Cache, 'BerkeleyDB::Btree',
     -Filename => '/tmpfs/bdbfile',
     -Flags    => DB_CREATE,
     -Mode     => 0640,
     -Env      => $env
     or die ("Can't tie to /tmp/bdbdfile: $!");

  my $Self = {
    Cache => \%Cache,
    Obj => $Obj
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Obj}->db_put( $_[1], $_[2] );
}

sub get {
  my $value;
  $_[0]->{Obj}->db_get( $_[1], $value );
  return $value;
}

1;

package CC5_CacheFileCacheStorable;
use Cache::FileCache;
use File::Temp qw(tempdir);

sub name { return "Cache::FileCache Storable"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {
    Cache => new Cache::FileCache({
      'namespace' => 'testcache',
      cache_depth => 2,
      cache_root => tempdir('cacheperl-XXXX', TMPDIR => 1, CLEANUP => 1)
    })
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->set($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->get($_[1]);
}

package CB9_CHIFile;
use CHI;
use File::Temp qw(tempdir);

sub name { return "CHI::Driver::File"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {
    Cache => CHI->new(
      driver => 'File',
      'namespace' => 'testcache',
      cache_depth => 2,
      root_dir => tempdir('cacheperl-XXXX', TMPDIR => 1, CLEANUP => 1)
    )
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->set($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->get($_[1]);
}

1;

package CC9_CHIFileStorable;
use CHI;
use File::Temp qw(tempdir);

sub name { return "CHI::Driver::File Storable"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {
    Cache => CHI->new(
      driver => 'File',
      'namespace' => 'testcache',
      cache_depth => 2,
      root_dir => tempdir('cacheperl-XXXX', TMPDIR => 1, CLEANUP => 1)
    )
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->set($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->get($_[1]);
}

1;
