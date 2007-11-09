#!/usr/bin/env perl
#
# Rob Mueller's script for benchmarking cache modules
# From http://cpan.robm.fastmail.fm/cacheperl.pl
#

use Time::HiRes qw(gettimeofday tv_interval);
use Storable qw(freeze thaw);
use Data::Dumper;
use strict;
use warnings;

#----- Setup stuff

use vars qw($DBSpec $DBUser $DBPassword $InnoDB);

# Your DBI DB details
#	$DBSpec = 'dbi:mysql:...';
#	$DBUser = '...';
#	$DBPassword = '...';
#	$InnoDB = 0;

srand(1);

# Number of runs to perform
my $Runs = 2;

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
for my $Depth (0 .. 2) {
  my @Structs = map { BuildStruct($Depth, $Depth+5) } 1 .. $MaxVals;
  push @DataComplex,  \@Structs;
  my @Frozen = map { freeze($_) } @Structs;
  push @DataBin, \@Frozen;
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
  CB1_CacheMmap => [ 'bin', num_pages => 11, page_size => 65536 ],
  CB1_CacheMmap => [ 'bin', num_pages => 89, page_size => 8192 ],
  CB2_CacheFastMmap => [ 'bin', num_pages => 11, page_size => 65536 ],
  CB2_CacheFastMmap => [ 'bin', num_pages => 89, page_size => 8192 ],
  CB3_MLDBMSyncSDBM_File => [ 'bin' ],
  CC3_BerkeleyDB => [ 'bin' ],
  CB4_IPCMM => [ 'bin' ],

  CC0_InProcHashStorable => [ 'complex' ],
  CC1_CacheMmapStorable => [ 'complex', num_pages => 89, page_size => 8192 ],
  CC2_CacheFastMmapStorable => [ 'complex', num_pages => 89, page_size => 8192 ],
  CC3_MLDBMSyncSDBM_FileStorable => [ 'complex' ],
  CC3_BerkeleyDBStorable => [ 'complex' ],
  CC4_IPCMMStorable => [ 'complex' ],
  CC5_CacheFileCacheStorable => [ 'complex' ],
#	  CC6_CacheSharedMemoryCacheStorable => [ 'complex' ],
  ($DBSpec ? (
    CC7_DBIStorable => [ 'complex' ],
    CC8_DBIStorableUpdate => [ 'complex' ],
  ) : ()),
);

#----- Now do runs

# Repeat each package type
while (my ($Package, $PackageOpts) = splice @Packages, 0, 2) {

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

package CB1_CacheMmap;
use Cache::Mmap;

sub name { return "Cache::Mmap"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  my $File = ($Args{vol} || (-e '/tmpfs' ? '/tmpfs' : '/tmp')) . "/cachefile";
  unlink($File);
  my $Self = {
    Cache => Cache::Mmap->new(
      $File,
      {
        ($Args{page_size} ? (bucketsize => $Args{page_size}) : ()),
        ($Args{num_pages} ? (buckets => $Args{num_pages}) : ()),
        strings => 1
      })
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->write($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->read($_[1]);
}

1;
package CC1_CacheMmapStorable;
use Cache::Mmap;

sub name { return "Cache::Mmap Storable"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  my $File = ($Args{vol} || (-e '/tmpfs' ? '/tmpfs' : '/tmp')) . "/cachefile";
  unlink($File);
  my $Self = {
    Cache => Cache::Mmap->new(
      $File,
      {
        ($Args{page_size} ? (bucketsize => $Args{page_size}) : ()),
        ($Args{num_pages} ? (buckets => $Args{num_pages}) : ()),
        strings => 0
      })
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->write($_[1], $_[2]);
}

sub get {
  return $_[0]->{Cache}->read($_[1]);
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

package CB3_MLDBMSyncSDBM_File;
use MLDBM::Sync qw(MLDBM::Sync::SDBM_File);
use Fcntl qw(:DEFAULT);

sub name { return "MLDBM::Sync::SDBM_File"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink glob('/tmp/sdbmfile*');
  my %Cache;
  my $Obj = tie %Cache, 'MLDBM::Sync::SDBM_File', '/tmp/sdbmfile', O_CREAT|O_RDWR, 0640;
  my $Self = {
    Cache => \%Cache,
    Obj => $Obj
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->{$_[1]} = $_[2];
}

sub get {
  return $_[0]->{Cache}->{$_[1]};
}

1;
package CC3_MLDBMSyncSDBM_FileStorable;
use Storable qw(freeze thaw);
use MLDBM::Sync qw(MLDBM::Sync::SDBM_File);
use Fcntl qw(:DEFAULT);

sub name { return "MLDBM::Sync::SDBM_File Storable"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink glob('/tmp/sdbmfile*');
  my %Cache;
  my $Obj = tie %Cache, 'MLDBM::Sync::SDBM_File', '/tmp/sdbmfile', O_CREAT|O_RDWR, 0640;
  my $Self = {
    Cache => \%Cache,
    Obj => $Obj
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Cache}->{$_[1]} = freeze($_[2]);
}

sub get {
  return thaw($_[0]->{Cache}->{$_[1]});
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

package CB4_IPCMM;
use IPC::MM qw(mm_create mm_make_hash mm_free_hash mm_destroy);

sub name { return "IPC::MM"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink('/tmp/mmlockfile');
  my $mm = mm_create(256*1024, '/tmp/mmlockfile');
  my $mmhash = mm_make_hash($mm);

  my %hash;
  my $obj = tie %hash, 'IPC::MM::Hash', $mmhash;

  my $Self = {
    MM => $mm,
    MMHash => $mmhash,
    Hash => \%hash,
    Obj => $obj,
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  eval { $_[0]->{Obj}->STORE($_[1], $_[2]); }
}

sub get {
  return $_[0]->{Obj}->FETCH($_[1]);
}

sub DESTROY {
  undef $_[0]->{Obj};
  untie %{$_[0]->{Hash}};
  mm_free_hash($_[0]->{MMHash});
  mm_destroy($_[0]->{MM});
}

1;
package CC4_IPCMMStorable;
use IPC::MM qw(mm_create mm_make_hash mm_free_hash mm_destroy);
use Storable qw(freeze thaw);

sub name { return "IPC::MM Storable"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  unlink('/tmp/mmlockfile');
  my $mm = mm_create(256*1024, '/tmp/mmlockfile');
  my $mmhash = mm_make_hash($mm);

  my %hash;
  my $obj = tie %hash, 'IPC::MM::Hash', $mmhash;

  my $Self = {
    MM => $mm,
    MMHash => $mmhash,
    Hash => \%hash,
    Obj => $obj,
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  eval { $_[0]->{Obj}->STORE($_[1], freeze($_[2])); }
}

sub get {
  return thaw($_[0]->{Obj}->FETCH($_[1]));
}

sub DESTROY {
  undef $_[0]->{Obj};
  untie %{$_[0]->{Hash}};
  mm_free_hash($_[0]->{MMHash});
  mm_destroy($_[0]->{MM});
}

1;

package CC5_CacheFileCacheStorable;
use Cache::FileCache;

sub name { return "Cache::FileCache Storable"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {
    Cache => new Cache::FileCache({
      'namespace' => 'testcache',
      cache_depth => 2
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

1;

package CC6_CacheSharedMemoryCacheStorable;
use Cache::SharedMemoryCache;

sub name { return "Cache::SharedMemoryCache Storable"; }
sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $Self = {
    Cache => new Cache::SharedMemoryCache({
      'namespace' => 'testcache'
    })
  };
  $Self->{Cache}->Clear();

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

package CC7_DBIStorable;
use DBI;
use Storable qw(freeze thaw);

sub name { return "DBI with freeze/thaw"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $DB = DBI->connect($::DBSpec, $::DBUser, $::DBPassword);
  $DB->do('drop table CacheTest');
  my $CT = 'create table CacheTest (CKey varchar(40) PRIMARY KEY, CValue blob)';
  $CT .= ' Type=InnoDB' if $::InnoDB;
  $DB->do($CT);

  my $Del = $DB->prepare('delete from CacheTest where CKey=?');
  my $Add = $DB->prepare('insert into CacheTest (CKey, CValue) values (?,?)');
  my $Get = $DB->prepare('select CValue from CacheTest where CKey=?');

  my $Self = {
    DB => $DB,
    Del => $Del,
    Add => $Add,
    Get => $Get
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  $_[0]->{Del}->execute($_[1]);
  $_[0]->{Add}->execute($_[1], freeze($_[2]));
}

sub get {
  my $Get = $_[0]->{Get};
  $Get->execute($_[1]);
  my $Data = $Get->fetchrow_arrayref()->[0];
  return thaw($Data);
}

1;

package CC8_DBIStorableUpdate;
use DBI;
use Storable qw(freeze thaw);

sub name { return "DBI (use updates with dup) with freeze/thaw"; }

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;

  my $DB = DBI->connect($::DBSpec, $::DBUser, $::DBPassword);
  $DB->do('drop table CacheTest');
  my $CT = 'create table CacheTest (CKey varchar(40) PRIMARY KEY, CValue blob)';
  $CT .= ' Type=InnoDB' if $::InnoDB;
  $DB->do($CT);

  my $Add = $DB->prepare('insert into CacheTest (CKey, CValue) values (?,?)');
  my $Upd = $DB->prepare('update CacheTest set CValue=? where CKey=?');
  my $Cnt = $DB->prepare('select count(*) from CacheTest where CKey=?');
  my $Get = $DB->prepare('select CValue from CacheTest where CKey=?');

  my $Self = {
    DB => $DB,
    Add => $Add,
    Upd => $Upd,
    Cnt => $Cnt,
    Get => $Get
  };

  bless ($Self, $Class);
  return $Self;
}

sub set {
  my $Cnt = $_[0]->{Cnt};
  $Cnt->execute($_[1]);
  my $Data = freeze($_[2]);
  if ($Cnt->fetchrow_arrayref()->[0]) {
    $_[0]->{Upd}->execute($Data, $_[1]);
  } else {
    $_[0]->{Add}->execute($_[1], $Data);
  }
}

sub get {
  my $Get = $_[0]->{Get};
  $Get->execute($_[1]);
  my $Data = $Get->fetchrow_arrayref()->[0];
  return thaw($Data);
}

