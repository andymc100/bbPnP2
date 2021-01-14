#!/usr/bin/perl
#
# Gets todays card
# Sleeps 5 minutes then starts again
package CacheUpdater;

use strict;
use warnings;
use WWW::BetfairNG;
use Data::Dumper;
use Time::Piece;
use Time::HiRes qw(time);
use DateTime;
use POSIX;



sub pricesFeeder
{
  use DateTime;
  use DateTime::Duration;
  use POSIX;
  use Time::Piece;
  use Time::HiRes qw(time sleep);

  my $pid = fork;      
  my $bf = shift;
  return $pid if $pid;     # in the parent process
my $debug = 0;

  my %options = (
    create    => 0,
    exclusive => 0,
    mode      => 0644,
    destroy   => 0,
  );
  my %prices;
  my $glue = 'prcs';
  tie %prices, 'IPC::Shareable', $glue, { %options } or
     die "Failed to attach to prices cache\n";

  my %static;        # List of markets to collect data
  $glue = 'sta1';
  tie %static, 'IPC::Shareable', $glue, { %options } or
    die "server: tie failed\n";
 
  print "Running runPriceFeeder Process PID: " . $pid . "\n";

  my $dataCheck = time;
  my $marketCheck=time;
  my $i=0;
  my %iTmp;
  
  while (1)
  {
    $i++;
    my @marketIds = keys %static;
    if ( scalar @marketIds == 0 )
    {
     print "No Markets so sleeping 15 secs\n" if $debug;
        sleep 15;
    }
    else
    {   
	    print "time: " . time . "\n";
	    print "dataCheck " . $dataCheck . "\n";
	    #print "diff: " . time - $dataCheck . "\n";    
        if (time - $dataCheck >= 0.2) 
        { 
            print "DateChecked\n";
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
            }
            else 
            {
                  print "listMarketBook FAILED : ${\$bf->error}\n";
            }
  
            foreach my $market (@$prices) 
            {  
print "market Loop\n";
              my %marketData;
              $marketData{inPlay}=$market -> {inplay};
              $marketData{marketStatus}=$market -> {status} ;
              $marketData{totalMatched}=$market -> {totalMatched}; 
              $marketData{timeStamp} = $date;
	      #print Dumper $prices;
	      my $marketId = $market->{marketId};
              foreach my $runner (@{$market -> {runners}})
                   { 
			   print "runner loop\n";
                      $marketData{$runner -> {selectionId}}{selectionId}=$runner -> {selectionId};
                      $marketData{$runner -> {selectionId}}{projectedBSP}=$runner -> {sp} -> {nearPrice};
                      $marketData{$runner -> {selectionId}}{actualBSP}=$runner->{sp} -> {actualSp};
                      $marketData{$runner -> {selectionId}}{lastPriceTraded}=$runner -> {lastPriceTraded};     
                      $marketData{$runner -> {selectionId}}{runnerStatus}=$runner -> {status};
                      $marketData{$runner -> {selectionId}}{tradedVol}=$runner -> {totalMatched};
                      $marketData{$runner -> {selectionId}}{backAmount1}=$runner -> {ex} -> {availableToBack}[0] -> {size} ;
                      $marketData{$runner -> {selectionId}}{backAmount2}=$runner -> {ex} -> {availableToBack}[1] -> {size} ;
                      $marketData{$runner -> {selectionId}}{backAmount3}=$runner -> {ex} -> {availableToBack}[2] -> {size} ;
                      $marketData{$runner -> {selectionId}}{layAmount1}=$runner -> {ex} -> {availableToLay}[0] -> {size} ;
                      $marketData{$runner -> {selectionId}}{layAmount2}=$runner -> {ex} -> {availableToLay}[1] -> {size} ;
                      $marketData{$runner -> {selectionId}}{layAmount3}=$runner -> {ex} -> {availableToLay}[2] -> {size} ;
                      $marketData{$runner -> {selectionId}}{backPrice1}=$runner -> {ex} -> {availableToBack}[0] -> {price} ;
                      $marketData{$runner -> {selectionId}}{backPrice2}=$runner -> {ex} -> {availableToBack}[1] -> {price} ;
                      $marketData{$runner -> {selectionId}}{backPrice3}=$runner -> {ex} -> {availableToBack}[2] -> {price} ;
                      $marketData{$runner -> {selectionId}}{layPrice1}=$runner -> {ex} -> {availableToLay}[0] -> {price} ;
                      $marketData{$runner -> {selectionId}}{layPrice2}=$runner -> {ex} -> {availableToLay}[1] -> {price} ;
                      $marketData{$runner -> {selectionId}}{layPrice3}=$runner -> {ex} -> {availableToLay}[2] -> {price} ;
  
                   }   
		   print "made it\n";
		   my %tmpPrices;
		   my $tmpPrices;
		   $tmpPrices{$marketId} = $prices{$marketId};
		   $tmpPrices->{$marketId}{$i}=\%marketData;
		   #print Dumper $tmpPrices;
		   $prices{$marketId}->{$i}=\%tmpPrices;
		   #print Dumper %prices;
                   if ($market -> {status} eq 'CLOSED')
                   {
                     delete $static{$marketId};
                   }
		   #print Dumper $tmpPrices;
           }
              
           
        }   
      }
  }   
} 
  
  sub marketStaticFeeder
  {   
  use POSIX;
  use Time::Piece;
  use Time::HiRes;
  use DateTime;
  use DateTime::Duration;

        my $bf = shift;
        my $pid = fork;      
        return $pid if $pid;     # in the parent process    

        my $marketCountries = ['GB','IE'];
   while (1)
   {
           my $now=DateTime->now; #creates the current date time in UTC
           my $end_time=$now + DateTime::Duration->new( hours => 18 );
            
           my $parameters = {filter => {
                                       eventTypeIds    => ['7'],
                                       marketCountries => $marketCountries,
                                       marketTypeCodes => ['WIN'],                      
                                       marketStartTime => { to => "$end_time" }
                                      },
                             maxResults => 20,
                            marketProjection => ['EVENT', 'MARKET_START_TIME']
                            };
         
        my $bfMarkets;
           if ($bfMarkets = $bf->listMarketCatalogue($parameters)) 
            {  
                  foreach my $market (@$bfMarkets) 
              {
                  my $marketId = $market->{marketId};
                  my $marketStartTime = Time::Piece->strptime($market->{marketStartTime}, "%Y-%m-%dT%T.000Z");
                  if ( not exists($static{$marketId}))
                  {             
	              my %staticMarket : shared;
                      $staticMarket{venue} = $market->{event}{venue};
                      $staticMarket{marketStartTime} = $marketStartTime;
                      $staticMarketId{marketName} = $market->{marketName};
		      { lock %markets;
			$static{$marketId}=\%staticMarket;
		      }
                  }

              }
            }
            else 
             { print "listMarketCatalogue FAILED : ${\$bf->error}\n";  }      
	     sleep(60);
      } 
      exit;
  }

1;

