#  DataLogger.pm

use strict;
use warnings;
use Data::Dumper;

package DataLogger;

  
sub writeLog
{
  my $outputFile = shift;
  my $i = 1;
  while (1)
  { 
    if (exists %prices->{$1} > $i)
	{
        my $newFile = ( -s $outputFile ) ? 1 : 0;
        $$outputFileLock=0;
        open(FH, '>>', $outputFile) or die $!;
        shift @$data if $newFile;
        foreach my $runner (@$data)
        {
          print FH $runner . "\n"; 	 
        }
        close(FH);
	}	
  }	
  $$outputFileLock=1;
  exit;
}

1;
