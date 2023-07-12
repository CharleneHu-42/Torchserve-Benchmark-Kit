#!/bin/bash

workers=$1
cores=$2
total_cores=$[workers*cores]
dtype=$3
model=ssl_bert_$dtype
config=/ppml/benchmark-kit/multi-pods/tsconfig/ssl_bert_${dtype}_config_ts.properties

if [[ `hostname` =~ tdx  ]]; then
	model=coco_$model
	core_offset=0
	frontend_cores="0,1"
else
	core_offset=`lscpu | grep "Core(s) per socket" | awk '{print $NF}'`
	frontend_cores="$[core_offset-2],$[core_offset-1]"
fi

sed -i 's/minWorkers.*$/minWorkers\": '${workers}',\\/' $config
sed -i 's/maxWorkers.*$/maxWorkers\": '${workers}',\\/' $config

export LD_PRELOAD="/path/to/libtcmalloc.so:/path/to/libiomp5.so"
export OMP_NUM_THREADS=$cores
#export KMP_SETTINGS=1
export KMP_BLOCKTIME=1
export KMP_AFFINITY=granularity=fine,compact,1,0

export LOG_LOCATION=ts_logs/$model-$workers-worker-$cores-core
mkdir -p $LOG_LOCATION

if [[ `hostname` =~ backend ]]; then
	bash -x start-torchserve-backends-multipods.sh -b "$core_offset-$[core_offset+total_cores-1]" -c $config -i 0.0.0.0 &
elif [[ `hostname` =~ frontend ]]; then
	backend_ip=$3
	bash -x start-torchserve-frontend-k8s.sh -c "$config" -i $backend_ip -f "$frontend_cores" &
fi

