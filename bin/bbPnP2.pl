#!/usr/bin/perl
# Gets todays card
# Sleeps 5 minutes then starts again

use strict;
use warnings;
use JSON::RPC::LWP;
use HTTP::Headers;
use Data::Dumper;
use JSON::RPC::Common::Procedure::Return;
use DateTime;
use DateTime::Duration;
use Time::Piece;
use Time::Seconds;
use POSIX qw(strftime);
use WWW::BetfairNG;
use FindBin;
use File::Spec;
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use Time::HiRes qw(time);
use POSIX qw(strftime);
use List::Util qw(min max);
use threads;
use threads::shared;

my $testMode=1;

#use BetBot::DataLogger;
#use BetBot::CacheUpdater;
use BetBot::betCoder;

# Set to 1 to enable debug output
my $debug = 0;
my $marketCountries = ['GB','IE'];

my $pricesFile = "../data/prices." . DateTime->now->strftime('%Y%m%d') . ".csv";
my $staticFile = "../data/static." . DateTime->now->strftime('%Y%m%d') . ".csv";
my $pricesFileLock=0;


my %static : shared;        # Static market data
my %prices : shared;        # Hash of alldata snaps
my %dataKeys : shared;        # Hash of thread and dataset values where each thread has completed with all data <= value
my %orders : shared;        # Hash of orders placed in the market

#print "App key being used: $appsKey\n";
#print "Session token being used: $sessionToken\n";

my $bf = betCoder::bfLogin({'pfile' => '../etc/properties.txt'});
$dataKeys{main}=1;
if ($testMode)
{
  my $pricesFeederThread = threads->new( \&backTestPricefeeder , {'file' => '../data/prices.20210111.csv' } );
  sleep 1 until defined $dataKeys{pricesFeeder};
}
else
{
  my $marketStaticFeederThread = threads->new( \&marketStaticFeeder , $bf  );
  sleep 1 until defined $dataKeys{marketStaticFeeder};

  my $pricesFeederThread = threads->new( \&pricesFeeder , $bf  );
  sleep 1 until defined $dataKeys{pricesFeeder};

  my $recordDataThread = threads->new( \&recordData , {'pricesFile' => $pricesFile, 'staticFile' => $staticFile } );
  sleep 1 until defined $dataKeys{recordData};
}

my $bot107Thread = threads->new( \&run107Bot , {'bf' => $bf, 'testMode' => $testMode }  );
sleep 1 until defined $dataKeys{run107Bot};

my $trackOrdersTest = threads->new( \&trackOrdersTest );
sleep 1 until defined $dataKeys{trackOrdersTest};


while ($dataKeys{main})
{
  #print "main static\n";
  #print Dumper %static;
  #print "main prices\n";
  #print Dumper %prices;
  #print "dataKeys\n";
  #print Dumper %dataKeys;
  #print "Orders\n";
  #print Dumper %orders;
  my %dataKeysTmp=%dataKeys;
  delete $dataKeysTmp{main};
  delete $dataKeysTmp{trackOrdersTest};
  $dataKeys{main}=min values %dataKeysTmp;
  sleep 10;
}


sub pricesFeeder
{
  my $bf = shift;
  my $dataCheck = time;
  my $marketCheck=time;
  my $i=0;
  my $debug = 0;

  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  $dataKeys{$sub} = $i;
  print "running " . $sub . "\n";

  while ($dataKeys{main})
  {
    my @marketIds = keys %static;
    if ( scalar @marketIds == 0 )
    {
        print "No Markets so sleeping 15 secs\n" if $debug;
        sleep 15;
    }
    else
    {
        print "time: " . time . "\n" if $debug;
        print "dataCheck " . $dataCheck . "\n Diff:" if $debug;
        print time - $dataCheck  if $debug;
        if (time - $dataCheck >= 0.2)
        {
            $i++;
            print "DateChecked\n" if $debug;
            $dataCheck += 0.2;
            my $parameters = {marketIds       => [@marketIds],
                              priceProjection => {
                                                   priceData => ['EX_BEST_OFFERS','SP_AVAILABLE']
                                                 }
                             };
            my $prices;
            my $t = time;
            my $date = strftime "%Y%m%d %H:%M:%S", localtime $t;
            $date .= sprintf ".%03d", ($t-int($t))*1000; # without rounding

            if ($prices = $bf->listMarketBook($parameters))
            {
                print "listMarketBook was SUCCESSFUL\n" if $debug;
                foreach my $market (@$prices)
                {
                    print "market Loop\n" if $debug;
                    my %marketData : shared;
                    my %marketDataId : shared;
                    my $inplay = 'false';
                    if(JSON::is_bool($market -> {inplay}))
                    {
                      $inplay = ( $market->{inplay} ? "true" : "false" );
                    }
                    $marketData{inplay}=$inplay;
                    $marketData{marketStatus}=$market -> {status} ;
                    $marketData{totalMatched}=$market -> {totalMatched};
                    $marketData{version}=$market -> {version};
                    $marketData{betDelay}=$market -> {betDelay};
                    $marketData{timeStamp} = $date;
                    #print Dumper $prices;
                    my $marketId = $market->{marketId};
                    my %marketDataRunners : shared;
                    foreach my $runner (@{$market -> {runners}})
                        {
                            print "runner loop\n" if $debug;
                            my %marketDataRunner : shared;
                            $marketDataRunner{selectionId}=$runner -> {selectionId};
                            $marketDataRunner{projectedBSP}=$runner -> {sp} -> {nearPrice};
                            $marketDataRunner{actualBSP}=$runner -> {sp} -> {actualSP};
                            $marketDataRunner{lastPriceTraded}=$runner -> {lastPriceTraded};
                            $marketDataRunner{runnerStatus}=$runner -> {status};
                            $marketDataRunner{tradedVol}=$runner -> {totalMatched};
                            $marketDataRunner{backAmount1}=$runner -> {ex} -> {availableToBack}[0] -> {size} ;
                            $marketDataRunner{backAmount2}=$runner -> {ex} -> {availableToBack}[1] -> {size} ;
                            $marketDataRunner{backAmount3}=$runner -> {ex} -> {availableToBack}[2] -> {size} ;
                            $marketDataRunner{layAmount1}=$runner -> {ex} -> {availableToLay}[0] -> {size} ;
                            $marketDataRunner{layAmount2}=$runner -> {ex} -> {availableToLay}[1] -> {size} ;
                            $marketDataRunner{layAmount3}=$runner -> {ex} -> {availableToLay}[2] -> {size} ;
                            $marketDataRunner{backPrice1}=$runner -> {ex} -> {availableToBack}[0] -> {price} ;
                            $marketDataRunner{backPrice2}=$runner -> {ex} -> {availableToBack}[1] -> {price} ;
                            $marketDataRunner{backPrice3}=$runner -> {ex} -> {availableToBack}[2] -> {price} ;
                            $marketDataRunner{layPrice1}=$runner -> {ex} -> {availableToLay}[0] -> {price} ;
                            $marketDataRunner{layPrice2}=$runner -> {ex} -> {availableToLay}[1] -> {price} ;
                            $marketDataRunner{layPrice3}=$runner -> {ex} -> {availableToLay}[2] -> {price} ;
              
                            $marketDataRunners{$runner -> {selectionId}}=\%marketDataRunner;
                        }
                    $marketData{runners}=\%marketDataRunners;
                    $marketDataId{$i}=\%marketData;
                    print "adding marketData\n" if $debug;
                    lock %prices;
                    $prices{$marketId}     = &share( {} ) if not defined $prices{$marketId};
                    $prices{$marketId}{$i} = &share( {} ) if not defined $prices{$marketId}{$i};
                    $prices{$marketId}{$i} = \%marketData;
                    print Dumper %prices if $debug;
                    if ($market -> {status} eq 'CLOSED')
                    {
                      delete $static{$marketId};
                    }
                    #print Dumper $tmpPrices;
                    $dataKeys{$sub}=$i;
                }
        }
            else
            {
              print "listMarketBook FAILED : ${\$bf->error}\n";
            }
        }
    }
  }
}



sub backTestPricefeeder
{
  my $params = shift;
  my $dataCheck = time;
  my $marketCheck=time;
  my $i=1;
  my $sub = "pricesFeeder";
  my $debug = 0;
  my @fields = qw(dataType totalMatched inplay runners timeStamp marketStatus version betDelay marketId selectionId projectedBSP actualBSP lastPriceTraded runnerStatus tradedVol backAmount1 backAmount2 backAmount3 layAmount1 layAmount2 layAmount3 backPrice1 backPrice2 backPrice3 layPrice1 layPrice2 layPrice3 dataset);

  $dataKeys{$sub} = $i;
  print "running pricesFeederTest\n";
  $sub = "pricesFeeder";
  $dataKeys{$sub} = $i;
  sleep 5 ;
  open(FH1, '<', $params->{file}) or die $!;

  while (my $line = <FH1>)
  { 
    chomp($line);
    if ( not $line =~ /^prices;/ )
    {
      next;
    }  
    my @lineData = split /;/, $line;
    my %marketDataItem;
    @marketDataItem{@fields} = @lineData;
      print Dumper %marketDataItem if $debug;;
      print "market Loop\n" if $debug;
      my %marketData : shared;
      my %marketDataId : shared;
      $marketData{inplay}=$marketDataItem{inplay};
      $marketData{marketStatus}=$marketDataItem{marketStatus} ;
      $marketData{totalMatched}=$marketDataItem{totalMatched};
      $marketData{timeStamp} = $marketDataItem{timeStamp};
      $marketData{version} = $marketDataItem{version};
      $marketData{betDelay} = $marketDataItem{betDelay};
      my $i = $marketDataItem{dataset};
      #print Dumper $prices;
      my $marketId = $marketDataItem{marketId};
      my %marketDataRunners : shared;
      my @selectionIds = split /:/, $marketDataItem{selectionId} ;
      foreach  my $rCnt (0 .. $#selectionIds )
      {
  my $debug = 0;
        print "rCnt: " . $rCnt . "\n" if $debug;;
        print "runner loop\n" if $debug;
  my %marketDataRunner : shared;
        print "test: " . ( split /:/, $marketDataItem{selectionId} )[$rCnt] . "\n" if $debug;
        $marketDataRunner{selectionId}     = (split /:/, $marketDataItem{selectionId})[$rCnt];
        $marketDataRunner{projectedBSP}    = (split /:/, $marketDataItem{projectedBSP})[$rCnt];
        $marketDataRunner{actualBSP}       = (split /:/, $marketDataItem{actualBSP})[$rCnt];
        $marketDataRunner{lastPriceTraded} = (split /:/, $marketDataItem{lastPriceTraded})[$rCnt];
        $marketDataRunner{runnerStatus}    = (split /:/, $marketDataItem{runnerStatus})[$rCnt];
        $marketDataRunner{tradedVol}       = (split /:/, $marketDataItem{tradedVol})[$rCnt];
        $marketDataRunner{backAmount1}     = (split /:/, $marketDataItem{backAmount1})[$rCnt] ;
        $marketDataRunner{backAmount2}     = (split /:/, $marketDataItem{backAmount2})[$rCnt];
        $marketDataRunner{backAmount3}     = (split /:/, $marketDataItem{backAmount3})[$rCnt];
        $marketDataRunner{layAmount1}      = (split /:/, $marketDataItem{layAmount1})[$rCnt] ;
        $marketDataRunner{layAmount2}      = (split /:/, $marketDataItem{layAmount2})[$rCnt] ;
        $marketDataRunner{layAmount3}      = (split /:/, $marketDataItem{layAmount3})[$rCnt] ;
        $marketDataRunner{backPrice1}      = (split /:/, $marketDataItem{backPrice1})[$rCnt] ;
        $marketDataRunner{backPrice2}      = (split /:/, $marketDataItem{backPrice2})[$rCnt] ;
        $marketDataRunner{backPrice3}      = (split /:/, $marketDataItem{backPrice3})[$rCnt] ;
        $marketDataRunner{layPrice1}       = (split /:/, $marketDataItem{layPrice1})[$rCnt] ;
        $marketDataRunner{layPrice2}       = (split /:/, $marketDataItem{layPrice2})[$rCnt] ;
        $marketDataRunner{layPrice3}       = (split /:/, $marketDataItem{layPrice3})[$rCnt] ; 
  $marketDataRunners{$marketDataRunner{selectionId}}=\%marketDataRunner;
      }
      $marketData{runners}=\%marketDataRunners;
      $marketDataId{$i}=\%marketData;
      print "adding marketData\n" if $debug;
      lock %prices;
      $prices{$marketId}     = &share( {} ) if ! defined $prices{$marketId};
      $prices{$marketId}{$i} = &share( {} ) if not defined $prices{$marketId}{$i};
      $prices{$marketId}{$i} = \%marketData;
      print Dumper %prices if $debug;
      if ($marketData{marketStatus} eq 'CLOSED')
        {
          delete $static{$marketId};
        }
     $dataKeys{$sub}=$i;
     }
  print "finished loading cache\n";
}


sub marketStaticFeeder
  {
  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  my $i=1;
  $dataKeys{$sub} = $i;
  print "running " . $sub . "\n";

  my $debug =0;
        my $bf = shift;
        my $marketCountries = ['GB','IE','US'];
  while ($dataKeys{main})
  {
           my $now=DateTime->now; #creates the current date time in UTC
           my $end_time=$now + DateTime::Duration->new( minutes => 20 );

           my $parameters = {filter => {
                                       eventTypeIds    => ['7'],
                                       marketCountries => $marketCountries,
                                       marketTypeCodes => ['WIN'],
                                       marketStartTime => { to => "$end_time" }
                                      },
                             maxResults => 20,
                             marketProjection => ['EVENT', 'MARKET_START_TIME', 'RUNNER_DESCRIPTION']
                             };

           my $bfMarkets;
           if ($bfMarkets = $bf->listMarketCatalogue($parameters))
            {
        print "have markets\n" if $debug;
              foreach my $market (@$bfMarkets)
              {
            print "have a market\n" if $debug;
                  my $marketId = $market->{marketId};
      #my $marketStartTime = Time::Piece->strptime($market->{marketStartTime}, "%Y-%m-%dT%T.000Z");
                  if ( not exists($static{$marketId}))
                  {
          my %staticMarket : shared;
                      $staticMarket{venue} = $market->{event}{venue};
                      $staticMarket{marketStartTime} = $market->{marketStartTime};
                      $staticMarket{marketName} = $market->{marketName};
                      my %staticRunners : shared;
          foreach my $runner (@{$market -> {runners}})
                      {
      my %staticRunner : shared;
                        $staticRunner{runnerName} = $runner->{runnerName};
                        $staticRunner{handicap} = $runner->{handicap};
                        $staticRunner{sortPriority} = $runner->{sortPriority};
      $staticRunners{$runner->{selectionId}} = \%staticRunner;
            $staticMarket{runners} = \%staticRunners;
                      }
          print "adding\n" if $debug;
          print Dumper %staticMarket if $debug;
                      $static{$marketId}=\%staticMarket;
                  }

             }
           }
          else
            { print "listMarketCatalogue FAILED : ${\$bf->error}\n";  }
       }
       sleep(60);
  }

sub recordData
{
  my $debug=0;
  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  $dataKeys{$sub} = 1;
  print "running " . $sub . "\n";
  my $params = shift;
  my $newPricesFile = ( -s $params->{pricesFile} ) ? 0 : 1;
  my $newStaticFile = ( -s $params->{staticFile} ) ? 0 : 1;
  my @marketFields = qw(totalMatched inplay runners timeStamp marketStatus version betDelay);
  my @runnerFields = qw(selectionId projectedBSP actualBSP lastPriceTraded runnerStatus tradedVol backAmount1 backAmount2 backAmount3 layAmount1 layAmount2 layAmount3 backPrice1 backPrice2 backPrice3 layPrice1 layPrice2 layPrice3);
  my @staticDataFields = qw(marketId marketStartTime marketName venue );
  my @staticRunnerFields = qw(runnerName sortPriority );
  my %staticFile;

  while($dataKeys{main})
  {
    open(FH, '>>', $params->{pricesFile}) or die $!;
    #print Dumper %dataKeys;
    my $i=0;
    my @newStatic;
    my $currentI = $dataKeys{pricesFeeder};
    for ($i = $dataKeys{$sub}; $i <= $currentI; $i++ )
    {
       my @marketIds = ( keys %prices );
       foreach my $marketId ( @marketIds )
       {
   if ( exists($prices{$marketId}{$i} ) )
         {
     my %marketVals;   
     my %runnerVals;   
     my $header = 'dataType;';
     my $line = 'prices;';
     foreach my $marketField ( @marketFields )
     {
       $header .= $marketField . ";" if $newPricesFile; 
       $line .= $prices{$marketId}{$i}{$marketField} . ";";
           }
     $header .= "marketId" . ";" if $newPricesFile;
     $line .= $marketId . ';';
           my @runners = (sort keys %{ $prices{$marketId}{$i}{runners} } );
           foreach my $runner (@runners)
     {
       foreach my $runnerField ( @runnerFields )
       {
               no warnings 'uninitialized';
         $runnerVals{$runnerField} .= $prices{$marketId}{$i}{runners}{$runner}{$runnerField} . ":";
         if(  \$runner == \$runners[-1]  ) 
         {
           $header .= $runnerField . ";" if $newPricesFile;    
     $line .= $runnerVals{$runnerField} . ";";
               }
             }
           }
     $header .= "dataset\n";
     $line .= $i;
     print FH $header if $newPricesFile;
     $newPricesFile=0;
     print FH $line . "\n";
   }
   if ( not exists $staticFile{$marketId} )
   {
           push (@newStatic,$marketId);
         }
       }         
       $dataKeys{$sub}=$i;
    }       
    close FH;
    for my $marketId (@newStatic)
    {
       open (sFH, '>>', $params->{staticFile});
       print sFH join (';',@staticDataFields,"selectionId",@staticRunnerFields) . "\n" if $newStaticFile;
       $newStaticFile = 0; 
       my $line;
       foreach my $staticDataField ( @staticDataFields )
       {
   no warnings 'uninitialized';
         $line .= $static{$marketId}{$staticDataField} . ";";
       }
       $line .= $marketId . ';';
       my @runners = (sort keys %{ $static{$marketId}{runners} } );
       my %runnerVals;   
       my $selectionIds = join (":",@runners);
       $line .= $selectionIds . ";";
       foreach my $runner (@runners)
       {
         foreach my $staticRunnerField ( @staticRunnerFields )
         {
           no warnings 'uninitialized';
           $runnerVals{$staticRunnerField} .= $static{$marketId}{runners}{$runner}{$staticRunnerField} . ":";
           if(  \$runner == \$runners[-1]  )
           {
             $line .= $runnerVals{$staticRunnerField} . ";";
           }
         }
       }
       print sFH $line . "\n"; 
       $staticFile{$marketId}=1;
    }
    sleep 15;
  }
}

sub run107Bot {
  my $debug = 0;
  my $params = shift;
  my $bf = $params->{bf};
  my $testMode = $params->{testMode};
  my $i=$dataKeys{pricesFeeder}; 
  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  $dataKeys{$sub} = $i;
  print Dumper %dataKeys if $debug;
  print "Running: " . $sub . " testMode: " . $testMode . "\n";
  # Input Parameters
  my $backPrice = 1.2;
  #my $backStopPrice = "15";
  my @snipers = (10,10,15);
  my $backSecondPlace = "4.0";
  my $backPercentage = 80;
  my $backSize = 2;#sprintf("%.2f",($balance * ($backPercentage / 100 )));
  my $maxOrders = 1;
  my $marketCountries = ["GB","IE"];
  my $strategyRef = "bb107";
  my $orderRef = 1;
  my %strgyData;
  my @eventIds;
  my $pnlLastCheck = DateTime->now;

  while ($dataKeys{main})
  {
    for ($i = $dataKeys{$sub}; $i < $dataKeys{pricesFeeder}; $i++ )
    {
      #print "dataKeys{sub}: " . $dataKeys{$sub} . "\n";
      #print "dataKeys{pricesFeeder}: " . $dataKeys{pricesFeeder} . "\n";
      my @marketIds = (keys %prices);
      foreach my $marketId (@marketIds)
      {
        if ( exists $prices{$marketId}{$i} and $prices{$marketId}{$i}{inplay} eq "true" ) 
        { 
        if ( not exists $strgyData{$marketId} )
        {
          $strgyData{$marketId}{back107}=0;
          $strgyData{$marketId}{betPlaced}=0;
          $strgyData{$marketId}{betPlaced}=0;
        }
          $strgyData{$marketId}{belowBackPrice}=0;
          $strgyData{$marketId}{belowBackStopPrice}=0;
          $strgyData{$marketId}{back1stSelection}=0;
          $strgyData{$marketId}{back2ndSelection}=0;
          $strgyData{$marketId}{back2ndPrice}= 0;
          $strgyData{$marketId}{hasLives}= 0;
          $strgyData{$marketId}{runnerPrice}=1000;
        my @Runners = ( keys %{ $prices{$marketId}{$i}{runners} } );#removed sort
        foreach my $Runner (@Runners)
        {
    if ($prices{$marketId}{$i}{runners}{$Runner}{runnerStatus} eq "ACTIVE")
                {
                        $strgyData{$marketId}{runnerPrice} = 1;
      $strgyData{$marketId}{lives}{$Runner} = 0 if not exists $strgyData{$marketId}{lives}{$Runner};
                                $strgyData{$marketId}{runnerPrice} = $prices{$marketId}{$i}{runners}{$Runner}{backPrice1};
                                my $price1 = 1;
                                my $price2 = 1;
        #print "1p1:" . $price1 . "|bp:" . $backPrice . "|\n";
        #print Dumper $prices{$marketId}{$i}{runners}{$Runner};
        #rint defined $prices{$marketId}{$i}{runners}{$Runner}{backPrice1}; print "< defined\n";
        if ( ( defined $prices{$marketId}{$i}{runners}{$Runner}{backPrice1} ) and $prices{$marketId}{$i}{runners}{$Runner}{backPrice1} ne '') 
        { $price1 = $prices{$marketId}{$i}{runners}{$Runner}{backPrice1}; }
        #print "2p1:" . $price1 . "|bp:" . $backPrice . "|\n";
          
        if ( (defined ($prices{$marketId}{$i}{runners}{$Runner}{backPrice2} ) ) and $prices{$marketId}{$i}{runners}{$Runner}{backPrice2} ne '' )
         { $price2 = $prices{$marketId}{$i}{runners}{$Runner}{backPrice2}; }

                                $strgyData{$marketId}{lives}{$Runner} = 0 if not exists $strgyData{$marketId}{lives}{$Runner};
        #print "3p1:" . $price1 . "|bp:" . $backPrice . "|\n";
                                if ( $price1 <= $backPrice)
                                    {
                                        $strgyData{$marketId}{back1stSelection}=$Runner;
                                        $strgyData{$marketId}{belowBackPrice}++;
                                        $strgyData{$marketId}{backRunnerPrice} = $price1;
                                        $strgyData{$marketId}{lives}{$Runner} = 0;
                                    }
                                if ($prices{$marketId}{$i}{runners}{$Runner} <= $backSecondPlace)
                                      {
                                        $strgyData{$marketId}{belowBack2ndPrice}++;
                                        $strgyData{$marketId}{back2ndSelection}=$Runner if $Runner ne $strgyData{$marketId}{back107} ;
                                        $strgyData{$marketId}{back2ndPrice} = $prices{$marketId}{$i}{runners}{$Runner}{backPrice1};
                                        $strgyData{$marketId}{lives}{$Runner} = 0;
                                      }

                                if  ($price1 <= max @snipers )
                                      {
                                        $strgyData{$marketId}{belowBackStopPrice}++;
                                        $strgyData{$marketId}{lives}{$Runner} = 0;

                                      }

        if  ($price1 > max @snipers and $price2 < max @snipers and ( ($price1 - $price2) >= 5) )
                                      {
                                        $strgyData{$marketId}{lives}{$Runner} = 0;

                                      }
                                my $grepRes = scalar grep { $_ <= $price1 } @snipers;
                                if  ( $grepRes > $strgyData{$marketId}{lives}{$Runner})
                                      {
                                        $strgyData{$marketId}{lives}{$Runner}++;
                                #        print "taking a life\n";
                                      }

                                if  ( $grepRes < $strgyData{$marketId}{lives}{$Runner} )
                                      {
                                        $strgyData{$marketId}{lives}{$Runner} = 0;
                        #               print "taking a life\n";
                                      }



                                if ( $strgyData{$marketId}{lives}{$Runner} < scalar @snipers)
                                {
                                          $strgyData{$marketId}{hasLives}++ ;
                                }

                                if ( $strgyData{$marketId}{back107} ==  $Runner )
                                     {
                                        $strgyData{$marketId}{price107} = $prices{$marketId}{$i}{runners}{$Runner}{backPrice1};
                                     }

                } else {
                        print "Runner is not active, current status is: " . $prices{$marketId}{$i}{runners}{$Runner}{runnerStatus} . "\n" if $debug;
                       }
                       my $lastPriceTraded=$prices{$marketId}{$i}{runners}{$Runner}{lastPriceTraded};
        
         }  

        print "Below backPrice: $strgyData{$marketId}{belowBackPrice} \n" if $debug;
        print "Below $backSecondPlace $strgyData{$marketId}{belowBack2ndPrice} \n" if $debug;
        print "Below $snipers[-1] $strgyData{$marketId}{belowBackStopPrice} \n" if $debug;

        if ( $strgyData{$marketId}{betPlaced} < $maxOrders and $strgyData{$marketId}{hasLives} == 1 and $strgyData{$marketId}{belowBackPrice} == 1)
        #One horse race
        { 
          my $custOrderRef = $sub . "_" . $orderRef++;
          my $orderParams = {marketId    => $marketId,
                              instructions => [{
                                                 selectionId => $strgyData{$marketId}{back1stSelection},
                                                 side => "BACK",
                                                 orderType => "LIMIT",
                                                 limitOrder => {
                                                                 size  => $backSize,
                                                                 price => 1.01,
                                                                 persistenceType => "LAPSE"
                                                               },
                         customerOrderRef => $custOrderRef,
                         marketVersion => $prices{$marketId}{$i}{version},
                                              }],
                  customerStrategyRef => $strategyRef,
            async => 1
           };
           #print "pre\n";print Dumper $strgyData{$marketId};
           placeOrders($bf, $i, $testMode, 0, $orderParams);
           $strgyData{$marketId}{betPlaced}++;
            $strgyData{$marketId}{back107} = $strgyData{$marketId}{back1stSelection};
            print "Placed  " .  $custOrderRef . " " . $marketId . "/" . $strgyData{$marketId}{back1stSelection} . " £" . $backSize . "@" . $strgyData{$marketId}{backRunnerPrice} . "\n" ;
      #print "post\n";print Dumper $strgyData{$marketId};
        }
  #  print Dumper %strgyData;
        select()->flush();

      }
        }
}
    { #lock %dataKeys;
      $dataKeys{$sub}=$i;
    }
  }
}

sub placeOrders{
  my $betId=0;
  my ($bf, $i, $testMode, $priority, $orderParams) = @_;;
        my $orderTime;
  if ( not $testMode )
  {
           my $PlaceExecutionReport  = $bf->placeOrders($orderParams);
     $orderTime = time;
     print Dumper $orderTime;
     print Dumper $PlaceExecutionReport;
        }
  $orderTime = $prices{$orderParams->{marketId}}{$i}{timeStamp} if $testMode;;
  foreach my $instruction (@{$orderParams->{instructions}} ) {
          print  "instruction\n" if $debug;
          print Dumper $instruction if $debug;
          my %order : shared;
    $order{placedDate}=$orderTime;
    $order{marketId}=$orderParams->{marketId};
    $order{betDelay}=$prices{$orderParams->{marketId}}{$i}{betDelay};
    $order{customerStrategyRef}=$orderParams->{customerStrategyRef};

    $order{selectionId}=$instruction->{selectionId};
    $order{side}=$instruction->{side};
    $order{orderType}=$instruction->{orderType};
    $order{customerOrderRef}=$instruction->{customerOrderRef};
    $order{marketVersion}=$instruction->{marketVersion};
    $order{customerOrderRef}=$instruction->{customerOrderRef};
    $order{testMode}=$testMode;
    $order{priority}=$priority; #Strategy waiting for match to place next order
    $order{status}="PENDING";
    if ( exists $instruction->{limitOrder} )
    { 
      $order{size}=$instruction->{limitOrder}{size};
      $order{price}=$instruction->{limitOrder}{price};
      $order{sizeRemaining}=$instruction->{limitOrder}{size};
      $order{sizeMatched}=0;
      $order{averagePriceMatched}=1;
      $order{persistenceType}=$instruction->{limitOrder}{persistenceType};
      $order{timeInForce}=$instruction->{limitOrder}{timeInForce};
      $order{minFillSize}=$instruction->{limitOrder}{minFillSize};
      $order{betTargetType}=$instruction->{limitOrder}{betTargetType};
      $order{betTargetSize}=$instruction->{limitOrder}{betTargetSize};
    }   

    if ( exists $instruction->{limitOnCloseOrder} )
    { 
                  $order{liability}=$instruction->{limitOnCloseOrder}{liability};
                  $order{price}=$instruction->{limitOnCloseOrder}{price};
          }

    if ( exists $instruction->{marketOnCloseOrder} )
    { 
      $order{liability}=$instruction->{marketOnCloseOrder}{liability};
          }   
    print "adding Order to shmem\n" if $debug;
    print Dumper %order  if $debug;
    $orders{$instruction->{customerOrderRef}}=\%order;
  }
    
        return;

}

sub trackOrdersTest{
  my $debug = 0;
  my $params = shift;
  my $bf = $params->{bf};
  my $start = 1;
  my $i = 1;
  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  $dataKeys{$sub} = $i;
  print "Running " . $sub . "\n";
  while ($dataKeys{main})
  {
        $start=$i;  
        my $tmpMain=$dataKeys{main};
	print "looping " . $start . " to " . $tmpMain . "\n" if $debug;;
        for ($i = $start; $i <= $tmpMain; $i++ )
        {
          while(my ($customerOrderRef, $order) = each (%orders))  
          {
            if (exists $prices{$order->{marketId}}{$i} )
            { 
              my $placedDate=$order->{placedDate};
	      my $timeStamp=$prices{$order->{marketId}}{$i}{timeStamp};
	      $placedDate=~s/ //g;
	      $placedDate=~s/://g;
	      $timeStamp=~s/ //g;
	      $timeStamp=~s/://g;
	      print "placedDate: " . $placedDate . "\n" if $debug;
	      print "timeStamp:  " . $timeStamp . "\n" if $debug;
              if ( $order->{marketVersion} != $prices{$order->{marketId}}{$i}{version} and $order->{persistenceType} eq "LAPSE" and $order->{status} ne "EXECUTION_COMPLETE")
	      #Market suspended lapse open orders
              { $order->{status} = "EXECUTION_COMPLETE" ;
	        $order->{sizeLapsed} += $order->{sizeRemaining}	;
	        $order->{sizeRemaining} = 0;
                print "Lapsed   " .  $customerOrderRef . " " . $order->{marketId} . "/" . $order->{selectionId} . " £" . $order->{sizeLapsed} . "@" . $order->{price} . "\n" ;
              }
              elsif ( ( $order->{status} eq "PENDING" or $order->{status} eq "EXECUTABLE" )  and $placedDate+$order->{betDelay} < $timeStamp )
	      #available to match
              {
                 print "Checking for Match\n" if $debug;
	         matchOrder({'customerOrderRef'=>$customerOrderRef, 'i'=>$i});
              }
	    }
	  }
       }
       $dataKeys{$sub} = $i;
       sleep 5;
  }
}

sub matchOrder
{
  my $params = shift;
  my $i = $params->{i};
  my $matchSize=0;
  my $weightedPrice=1;
  my $matched=0;
  my $backAmount1=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backAmount1} ;
  my $backPrice1=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backPrice1} ;
  my $backAmount2=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backAmount2} ;
  my $backPrice2=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backPrice2} ;
  my $backAmount3=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backAmount3} ;
  my $backPrice3=$prices{$orders{$params->{customerOrderRef}}{marketId}}{$i}{runners}{$orders{$params->{customerOrderRef}}{selectionId}}{backPrice3} ;
  if ( $orders{$params->{customerOrderRef}}{side} eq "BACK" and $backAmount1 and $backPrice1 > 1 and $orders{$params->{customerOrderRef}}{price} <= $backAmount1 )
  {
    $matchSize = min($backAmount1, $orders{$params->{customerOrderRef}}{sizeRemaining});
    $weightedPrice=(($orders{$params->{customerOrderRef}}{averagePriceMatched}*$orders{$params->{customerOrderRef}}{sizeMatched})+($matchSize*$backPrice1))/($orders{$params->{customerOrderRef}}{sizeMatched}+$matchSize);
    $orders{$params->{customerOrderRef}}{sizeRemaining} -= $matchSize;
    $orders{$params->{customerOrderRef}}{sizeMatched} += $matchSize; 
    $orders{$params->{customerOrderRef}}{averagePriceMatched} = $weightedPrice;
    $matched++;
  }
  if ( $orders{$params->{customerOrderRef}}{side} eq "BACK" and $backAmount2 and $backPrice2 > 1 and $orders{$params->{customerOrderRef}}{price} <= $backAmount2 )
  {
    $matchSize = min($backAmount2, $orders{$params->{customerOrderRef}}{sizeRemaining});
    $weightedPrice=(($orders{$params->{customerOrderRef}}{averagePriceMatched}*$orders{$params->{customerOrderRef}}{sizeMatched})+($matchSize*$backPrice2))/($orders{$params->{customerOrderRef}}{sizeMatched}+$matchSize);
    $orders{$params->{customerOrderRef}}{sizeRemaining} -= $matchSize;
    $orders{$params->{customerOrderRef}}{sizeMatched} += $matchSize; 
    $orders{$params->{customerOrderRef}}{averagePriceMatched} = $weightedPrice;
    $matched++;
  }
  if ( $orders{$params->{customerOrderRef}}{side} eq "BACK" and $backAmount3 and $backPrice3 > 1 and $orders{$params->{customerOrderRef}}{price} <= $backAmount3 )
  {
    $matchSize = min($backAmount3, $orders{$params->{customerOrderRef}}{sizeRemaining});
    $weightedPrice=(($orders{$params->{customerOrderRef}}{averagePriceMatched}*$orders{$params->{customerOrderRef}}{sizeMatched})+($matchSize*$backPrice3))/($orders{$params->{customerOrderRef}}{sizeMatched}+$matchSize);
    $orders{$params->{customerOrderRef}}{sizeRemaining} -= $matchSize;
    $orders{$params->{customerOrderRef}}{sizeMatched} += $matchSize; 
    $orders{$params->{customerOrderRef}}{averagePriceMatched} = $weightedPrice;
    $matched++;
  }
  $orders{$params->{customerOrderRef}}{status}="EXECUTION_COMPLETE" if $orders{$params->{customerOrderRef}}{sizeRemaining} == 0; ;
  print "Matched " .  $params->{customerOrderRef} . " " . $orders{$params->{customerOrderRef}}{marketId} . "/" . $orders{$params->{customerOrderRef}}{selectionId} . " £" . $orders{$params->{customerOrderRef}}{sizeMatched} . "@" . $orders{$params->{customerOrderRef}}{averagePriceMatched} . "\n" ;
}
