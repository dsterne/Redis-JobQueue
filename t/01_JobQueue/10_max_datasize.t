#!/usr/bin/perl -w

use 5.010;
use strict;
use warnings;

use lib 'lib';

use Test::More;
plan "no_plan";

BEGIN {
    eval "use Test::Exception";
    plan skip_all => "because Test::Exception required for testing" if $@;
}

BEGIN {
    eval "use Test::RedisServer";
    plan skip_all => "because Test::RedisServer required for testing" if $@;
}

BEGIN {
    eval "use Test::TCP";
    plan skip_all => "because Test::RedisServer required for testing" if $@;
}

use Redis::JobQueue qw(
    DEFAULT_SERVER
    DEFAULT_PORT
    DEFAULT_TIMEOUT

    STATUS_CREATED
    STATUS_WORKING
    STATUS_COMPLETED
    STATUS_DELETED

    ENOERROR
    EMISMATCHARG
    EDATATOOLARGE
    ENETWORK
    EMAXMEMORYLIMIT
    EMAXMEMORYPOLICY
    EJOBDELETED
    EREDIS
    );

my $redis;
my $real_redis;
eval { $real_redis = Redis->new( server => DEFAULT_SERVER.":".DEFAULT_PORT ) };
SKIP: {
    skip( "Redis server is unavailable", 1 ) unless ( !$@ and $real_redis and $real_redis->ping );
$real_redis->quit;

my ( $jq, $job, @jobs, $maxmemory, $vm, $policy );
my $pre_job = {
    id           => '4BE19672-C503-11E1-BF34-28791473A258',
    queue        => 'lovely_queue',
    job          => 'strong_job',
    expire       => 60,
    status       => 'created',
    workload     => \'Some stuff up to 512MB long',
    result       => \'JOB result comes here, up to 512MB long',
    };

sub new_connect {
    # For real Redis:
#    $real_redis = Redis->new( server => DEFAULT_SERVER.":".DEFAULT_PORT );
#    $redis = $real_redis;
#    isa_ok( $redis, 'Redis' );

    # For Test::RedisServer
    $redis = Test::RedisServer->new( conf =>
        {
            port                => empty_port(),
            maxmemory           => $maxmemory,
#            "vm-enabled"        => $vm,
            "maxmemory-policy"  => $policy,
            "maxmemory-samples" => 100,
        } );
    isa_ok( $redis, 'Test::RedisServer' );

    $jq = Redis::JobQueue->new(
        $redis,
        );
    isa_ok( $jq, 'Redis::JobQueue');

    $jq->_call_redis( "DEL", $_ ) foreach $jq->_call_redis( "KEYS", "JobQueue:*" );
}

$maxmemory = 0;
$vm = "no";
$policy = "noeviction";
new_connect();

$jq->_call_redis( "DEL", $_ ) foreach $jq->_call_redis( "KEYS", "JobQueue:*" );

$job = $jq->add_job( $pre_job );
isa_ok( $job, 'Redis::JobQueue::Job');

@jobs = $jq->get_jobs;
ok scalar( @jobs ), "jobs exists";

#-- EDATATOOLARGE

my $prev_max_datasize = $jq->max_datasize;
my $max_datasize = 100;
$pre_job->{result} .= '*' x ( $max_datasize + 1 );
$jq->max_datasize( $max_datasize );

$job = undef;
eval { $job = $jq->add_job( $pre_job ) };
is $jq->last_errorcode, EDATATOOLARGE, "EDATATOOLARGE";
note '$@: ', $@;
is $job, undef, "the job isn't changed";
$jq->max_datasize( $prev_max_datasize );

#-- Closes and cleans up -------------------------------------------------------

$jq->_call_redis( "DEL", $_ ) foreach $jq->_call_redis( "KEYS", "JobQueue:*" );

ok $jq->_redis->ping, "server is available";
$jq->quit;
ok !$jq->_redis->ping, "no server";

};

exit;
