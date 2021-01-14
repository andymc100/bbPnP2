#!/usr/bin/perl
#
# Gets todays card
# Checks every 60 seconds if there is an active race
# Once active checks if a horse matches the input paramters, keeps checking every 0.2 seconds until one does
# Sleeps 5 minutes then starts again
package Bot107;

use JSON::RPC::LWP;
use HTTP::Headers;
use Data::Dumper;
use JSON::RPC::Common::Procedure::Return;
use DateTime;
use Time::Piece;
use List::Util qw(min max);
use LWP::UserAgent;
use Mozilla::CA;
use HTTP::Tiny;
use WWW::BetfairNG;
use DateTime::Format::Strptime;
use File::Basename;
use File::Path qw( make_path );

sub run107Bot {
  my $i=$dataKeys{pricesFeeder};# : shared =0;
  my $debug = 1;

  my $sub = (caller(0))[3];
  $sub =~ s/.*:://;
  $dataKeys{$sub} = $i;


  # Input Parameters
  my $backPrice = 1.15;
  #my $backStopPrice = "15";
  my @snipers = (15,15,15,15);
  my $backSecondPlace = "4.0";
  my $backPercentage = 80;
  my $backSize = 2;#sprintf("%.2f",($balance * ($backPercentage / 100 )));
  my $maxOrders = 1;
  my $marketCountries = ["GB","IE"];
  my $strategyRef = "bb107";
  my %strgyData;

  my @eventIds;
  my $pnlLastCheck = DateTime->now;


  while (1)
  {
    for ($i = $dataKeys{$sub}; $i <= $dataKeys{pricesFeeder}; $i++ )
    {
      foreach my $marketId (keys %prices)
      {
        next if ( $prices{$marketId}{$i}{inplay} eq "false" );

        print "check Runners\n" if $debug;
        my @Runners = @{$MarketBook -> {runners}};
        print "Runner Dump: " .  Dumper(@Runners) if $debug ;
        if ( not exists $strgyData{$marketId} )
        {
          $strgyData{belowBackPrice}=0;
          $strgyData{backRunnerPrice};
          $strgyData{belowBack2ndPrice};
          $strgyData{belowBackStopPrice}=0;
          $strgyData{back1stSelection}=0;
          $strgyData{back2ndSelection}=0;
          $strgyData{back2ndPrice}= 0;
          $strgyData{hasLives}= 0;
          $strgyData{runnerPrice}=1000;
          $strgyData{back107}=0;
          %strgyData{lives};
        }
        my @Runners = (sort keys %{ $prices{$marketId}{$i}{runners} } );
        foreach my $Runner (@Runners)
        {
                if ($Runner{runnerStatus} eq "ACTIVE")
                {
                        $strgyData{runnerPrice} = 1;
                        foreach my $RunnerPrices ($Runner{runners})
                          {
                                $strgyData{runnerPrice} = $RunnerPrices{backPrice1};
                                my $price1 = $RunnerPrices{backPrice1};
                                $price2 = $RunnerPrices{backPrice2} if defined($RunnerPrices{backPrice2});

                                $lives{$Runner{selectionId}} = 0 if not exists $lives{$Runner{selectionId}};
                                if ($price1 <= $backPrice)
                                    {
                                        $strgyData{back1stSelection}=$Runner{selectionId};
                                        $strgyData{belowBackPrice}++;
                                        $strgyData{backRunnerPrice} = max(1, $price1);
                                        $strgyData{lives}{$Runner{selectionId}} = 0;
                                    }
                                if ($RunnerPrices{backPrice1} <= $backSecondPlace)
                                      {
                                        $strgyData{belowBack2ndPrice}++;
                                        $strgyData{back2ndSelection}=$Runner{selectionId} if $Runner{selectionId} ne $strgyData{back107} ;
                                        $strgyData{back2ndPrice} = $RunnerPrices{backPrice1};
                                        $lives{$Runner{selectionId}} = 0;
                                      }

                                if  ($price1 <= max @snipers )
                                      {
                                        $strgyData{belowBackStopPrice}++;
                                        $strgyData{lives}{$Runner{selectionId}} = 0;

                                      }

                                if  ($price1 > max @snipers and $price2 < max @snipers and  $price1 - $price2 => 5 )
                                      {
                                        $strgyData{lives}{$Runner{selectionId}} = 0;

                                      }
                                my $grepRes = scalar grep { $_ <= $price1 } @snipers;
                                if  ( $grepRes > $strgyData{lives}{$Runner -> {selectionId}})
                                      {
                                        $strgyData{lives}{$Runner{selectionId}}++;
                                #        print "taking a life\n";
                                      }

                                if  ( $grepRes < $strgyData{lives}{$Runner{selectionId}} )
                                      {
                                        $strgyData{lives}{$Runner{selectionId}} = 0;
                        #               print "taking a life\n";
                                      }



                                if ( $strgyData{lives}{$Runner{selectionId}} < scalar @snipers)
                                {
                                          $strgyData{hasLives}++ ;
                                }

                                if ( $strgyData{back107} ==  $Runner{selectionId} )
                                     {
                                        $price107 = $RunnerPrices{backPrice1};
                                     }

                        }
                } else {
                        print "Runner is not active, current status is: " . Runner{runnerStatus} . "\n" if $debug;
                       }
                       my $lastPriceTraded=$Runner{lastPriceTraded};
        }

        print "Below $backPrice: $strgyData{belowBackPrice} \n" if $debug;
        print "Below $backSecondPlace $strgyData{belowBack2ndPrice} \n" if $debug;
        print "Below $snipers[-1] $strgyData{belowBackStopPrice} \n" if $debug;

        if ($price107 > $backPrice and $check107 )
        {
                cancelOrders($marketId);
                print "Cancelling Orders\n";
        }
        $check107-- if $check107;

        if ( $betPlaced < $maxOrders and $strgyData{hasLives} == 1 and $strgyData{belowBackPrice} == 1)
        #One horse race
        {
            placeBet($marketId, $strgyData{back1stSelection}, $backSize);
            $betPlaced++;
            $strgyData{back107} = $strgyData{back1stSelection};
            $check107 = 3;
            print "Backed : " . $strgyData{back1stSelection} . " at " . $strgyData{backRunnerPrice} . "\n" ;
        }
        elsif ($strgyData{belowBack2ndPrice} == 2 and $strgyData{back107} != 0 and $betPlaced > 0 and $strgyData{hasLives} == 2 and $price107 < $snipers[-1] and $strgyData{back107} != $strgyData{back2ndSelection} )
        # horse2 got his legs back but not out of the running altogether
        {
                my $hedgeSize = sprintf("%.2f",($betPlaced * $backSize) / 3);
                  print "Seconds closing in\n";
                #placeLayBet($marketId, $strgyData{back107}, $backSize);
                print "Placed one hedge back at " . $hedgeSize . " on " . $strgyData{back2ndSelection} . " at " . $strgyData{runnerPrice} . "previous now at " . $price107 . "\n";
                #cancelOrders($marketId);
                print "Placed lay order\n";
                $strgyData{back107} = 0;
          }
          elsif ($strgyData{back107} != 0 and $strgyData{back107} != $strgyData{back2ndSelection} and $strgyData{belowBackStopPrice} == 1 and $strgyData{back2ndSelection} != 0 )
          # Original horse out of race next one only one below 15
        {
                #cancelOrders($marketId);
                print "Original: ". $strgyData{back107} . " has fallen away to " . $price107 ." Cancelled any open orders \n";
                #placeLayBet($marketId, $strgyData{back107}, $backSize);
                print "Placed lay on " . $strgyData{back107};
                $strgyData{back107} = 0;
          }
          #elsif ($strgyData{belowBackPrice} == 1 and ($strgyData{belowBackStopPrice} or $strgyData{hasLives} > 1) and $betPlaced < $maxOrders )
          #{
          #  print "Runner: " . $back1stSelection . " is at " . $strgyData{backRunnerPrice} . " but " . $strgyData{belowBackStopPrice} . " are below backstop price and ". $strgyData{hasLives} . " have strgyData{lives} left\n";
          #}
          select()->flush();

      }
	}  
  }
}

1;

