#!/usr/bin/perl

use JSON;
use Data::Dumper;
use Date::Manip;
use Time::ParseDate;
use Getopt::Long;
use Pod::Usage;
use POSIX;


=head1 NAME
 
 Retrive stats for given process and JOBID

=head1 SYNOPSIS

 Usage: ivory_job_status.pl [options]

 where options can be

   --ivory_host |-ivh Hostname where Ivory Server is running
   --ivory_port |-ivp Port on Ivory Server is running
   --oozie_host |-ozh Hostname where Oozie is running
   --oozie_port |-ozp Port on Oozie is running
   --external_id|-eid external ID of your Job
   --deltatime  |-dt This is the time in the past for which you want to look for you Job 
   --processname | -pn Specify the processname you want to get the status for
   --jobid      | -jid Job id for which you want the status for 

 Example:
$ /opt/mkhoj/ops/bin/ivory_job_status.pl -pn <processname> -jid 2012-05-28T06:40Z
JOB SUCCEEDED and completed actions recordsize user-workflow ivory-succeeded-messaging user-jms-messaging ivory-succeeded-log-mover
$

$ /opt/mkhoj/ops/bin/ivory_job_status.pl -pn <processname> -jid 2012-05-28T07:40Z
JOB is right now running action user-workflow from last 717 seconds
$

$ /opt/mkhoj/ops/bin/get_oozie_stats.pl -h <processname> -p 11000 -oid 0004224-120519075902678-oozie-oozi-W -status
JOB SUCCEEDED and completed actions recordsize user-workflow ivory-succeeded-messaging user-jms-messaging ivory-succeeded-log-mover
$

=head1 AUTHOR

 Kiran Praneeth <kiran.praneeth@gmail.com>

=cut

GetOptions ("ivory_host|ivh=s" 	=> \$ivory_host,
            "ivory_port|ivp=i"      	=> \$ivory_port,
            "deltatime|dt=i" 	=> \$dt,
            "oozie_host|ozh=s"       => \$oozie_host,
            "oozie_port|ozp=i"       => \$oozie_port,
            "processname|pn=s"       => \$external_id,
            "jobid|jid=s"       => \$job_id,
            "output_appender|oa=s"       => \$output_appender,
            "output_file|of=s"		=> \$output_file,
            "help"      => \$help);

$ivory_host = "oozie.com" if ! $ivory_host;
$ivory_port = "5800" if ! $ivory_port;
$oozie_host = "oozie.com" if ! $oozie_host;
$oozie_port = "1800" if ! $oozie_port;

pod2usage( -exitval => 0 ) if ( $help );
pod2usage( -exitval => 0, -msg => "ivory server/port, oozie server/port, external id  and job id is Mandatory" ) if ( !defined $ivory_host || !defined $ivory_port || !defined $oozie_host || !defined $oozie_port || !defined $external_id || !defined $job_id);

$dt ||= 60;

$ivory_resp  = `curl -s -H "remote-user: user" "http://$ivory_host:$ivory_port/ivory/api/processinstance/status/$external_id?start=$job_id&end=$job_id"` 
        || die "Can't run curl call: $!";

$json = JSON->new->allow_nonref;
$perl_scalar = from_json( $ivory_resp, { utf8  => 1 } );

$ivory_jobs = $perl_scalar->{'instances'};

my $i=0;
my @final_out;
foreach $ij (@$ivory_jobs) {
       $oozie_json=`curl -s -H "remote-user: user" "http://$oozie_host:$oozie_port/oozie/v1/jobs?jobtype=wf&external-id=$external_id/DEFAULT/$ij->{'instance'}"` 
             || die "Failed running oozie status for getting id: $!";
       if ($oozie_json !~ /"id":""/) {
           get_oozie_status();
       } else { 
           get_wait_reason();
       }
}

sub get_oozie_status {
    $oozie_scalar = from_json( $oozie_json, { utf8  => 1 } );
    $op_append = "-oa $output_appender" if ( $output_appender);
    #print "\nRunning /home/gaminik/get_oozie_stats.pl  -h  $oozie_host -p $oozie_port -oid $oozie_scalar->{'id'} -status $op_append\n";
    $oozie_stats = `get_oozie_stats.pl  -h  $oozie_host -p $oozie_port -oid $oozie_scalar->{'id'} -status $op_append `;
    print "Null output from oozie! Check if oozie is down" if !$oozie_stats;
    push (@final_out,$oozie_stats);
}

sub get_wait_reason {
    my $i = 0;
    my $cord_json = `curl -s -H "remote-user: user" "http://$oozie_host:$oozie_port/oozie/v1/jobs?jobtype=coord&filter=name=IVORY_PROCESS_DEFAULT_$external_id"` ||
            die "Failed running curl call: $!";
    $cord_scalar = from_json( $cord_json, { utf8  => 1 } );
    my $cordinator_job_ref = $cord_scalar->{'coordinatorjobs'};
    foreach my $tmp_ref (@$cordinator_job_ref) {
         $cord_job_id = $tmp_ref->{'coordJobId'};
    }
    chomp($cord_job_id);
    my $oozie_stat_json = `curl -s -H "remote-user: user" "http://$oozie_host:$oozie_port/oozie/v1/job/$cord_job_id\@1?show=info"` || 
                 die "Failed running curl call: $!";
    my $oozie_stat_scalar = from_json($oozie_stat_json, { utf8  => 1 } );
    my $oozie_missing_dep = $oozie_stat_scalar->{'missingDependencies'};
    foreach my $dependency (split /#/, $oozie_missing_dep) {
          next if ! $dependency;
          next if $dependency !~ /_SUCCESS$/;
          get_hadoop_status($dependency);
    }
    print "JOB $cord_job_id missing below dependencies:\n";
    print @missing_files;
}

sub get_hadoop_status {
    my $file = @_[0];
    my $success_file_success = `hadoop dfs -ls $file 2>&1 /dev/null` || warn "Can't run hadoop dfs -ls for $file: $!";
    if ($? != 0) {
        push (@missing_files, $file);
    }
}
print "@final_out";
