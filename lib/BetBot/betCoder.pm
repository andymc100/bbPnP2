#  betCoder.pm

use strict;
use warnings;
use Data::Dumper;
use WWW::BetfairNG;

package betCoder;

sub bfLogin
{
  my $params = shift;
  print "pfile: " . $params->{pfile} . "\n";  
  open(FH1, '<', $params->{pfile}) or die $!;
  my $username = <FH1>; chomp $username;
  my $password = <FH1>; chomp $password;
  my $appKey = <FH1>; chomp $appKey;
  my $pushoverToken = <FH1>; chomp $pushoverToken;
  my $pushoverUser = <FH1>; chomp $pushoverUser;
  close(FH1);
  my $bf = WWW::BetfairNG->new({app_key  => $appKey});  
  $bf->interactiveLogin({username => $username, password => $password}) or die "Failed to login\n";
  return $bf;
}
  
sub writeLog
{
  my $pid = fork;
  return if $pid;     # in the parent process
  my $outputFile = shift;
  my $data = shift;
  my $outputFileLock = shift;
  my $newFile = ( -s $outputFile ) ? 1 : 0;
  $$outputFileLock=0;
  open(FH, '>>', $outputFile) or die $!;
  shift @$data if $newFile;
  foreach my $runner (@$data)
  {
    print FH $runner . "\n"; 	 
  }
  close(FH);
  $$outputFileLock=1;
  exit;
}

sub logData
{
  my $logData = shift;
  my @data = @{$_[0]};
  
  my @runKeys = sort (keys % { $data[0] });
  push @$logData,join(";", @runKeys ) if scalar @$logData == 0;

   foreach my $runner (@data)
   {
     my $line;
     foreach my $k (@runKeys) 
	 {
	   no warnings 'uninitialized';
       $line = $line . $runner -> {$k} . ";";
	 }  
     push @$logData,$line;
   }
}

1;