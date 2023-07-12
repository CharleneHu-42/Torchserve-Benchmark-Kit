# Bert-large TorchServe with TDX CoCo Benchmark #
## Prerequisites ##
- CoCo environment setup
- K8S cluster setup with static cpu manager (follow [link](https://wiki.ith.intel.com/display/HEL/Setup+static+CPU+management))

## Start pods for frontend and backend ##
1. Edit yaml files

Configure hostPath of mount volume `benchmark-kit` and `model-store` to corresponding host directories as below:

	volumes:
    - name: benchmark-kit
      hostPath:
        path: /path/to/benchmark/kit
	- name: model-store
	  hostPath:
	    path: /path/to/model/store

For TDX CoCo, also configure the cpu/memory resource/limit for backend and frontend pods. Typically, we allocate cpus of one socket/64GB memory for backend, and 2 cores/5GB memory for frontend. Below is the example of backend pod on 2S48C SPR.

    resources:
      limits:
        cpu: "48"
        memory: "64Gi"
      requests:
        cpu: "48"
        memory: "64Gi"


2. Start pods
	- For native mode, directly start pods by
		```
		kubectl apply -f bigdl-dlserving-backend.yaml
		kubectl apply -f bigdl-dlserving-frontend.yaml
		```
	- For TDX CoCo, 

		Configure cpus and memory to the same value configured in backend pods yaml in `/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-tdx.toml`
		```
		default_vcpus = 48
		default_memory = 65536
		```
		Start backend pod
		```
		kubectl apply -f tdxcc-bigdl-dlserving-backend.yaml
		```		
		Configure cpus and memory to the same value configured in frontend pods yaml in `/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-tdx.toml`
		```
		default_vcpus = 2
		default_memory = 5120
		```
		Start frontend pod	
		```
		kubectl apply -f tdxcc-bigdl-dlserving-frontend.yaml
		```
## Start TorchServe ##
Make sure to delete TDX CoCo pods before starting native mode pods to avoid cpu resource conflict.
### Start backend ###
Enter backend pod and init

    kubectl exec <backend_pod> -it -- bash
	cd /ppml/<workdir>/multi-pods
	apt update && apt install -y numactl

Install intel-openmp and tcmalloc ([guide](https://github.com/IntelAI/models/tree/master/quickstart/language_modeling/pytorch/bert_large/inference/cpu#bare-metal)), modify lib file path in `start-service.sh` as:
	
	export LD_PRELOAD="/path/to/libtcmalloc.so:/path/to/libiomp5.so"

For kernel version later than 5.15, apply patch for inside CoCo pod with

	python_version=`python -V | awk -F '.' '{print $2}'`
	patch /usr/local/lib/python3.${python_version}/dist-packages/psutil/_pslinux.py /ppml/serve-benchmark/pslinux.patch
 
Configure `config=<path/to/tsconfig>` in `start-service.sh`, and configure SSL key/password in used `tsconfig`, take below as an example:

	keystore=/ppml/keys/keystore.jks
	keystore_pass=<password>
	keystore_type=JKS

start TorchServe backend. Typically, `<cores_per_worker>` is set to `4` and `<worker_num>` is set to `cores_per_socket/4`, e.g. 12 workers and 4 cores/worker on 2S48C SPR.

	bash start-service.sh <worker_num> <cores_per_worker>

### Start frontend ###
Enter frontend pod and init

    kubectl exec <frontend_pod> -it -- bash
	cd /ppml/<workdir>/multi-pods

For kernel version later than 5.15, apply patch for inside CoCo pod with

	python_version=`python -V | awk -F '.' '{print $2}'`
	patch /usr/local/lib/python3.${python_version}/dist-packages/psutil/_pslinux.py /ppml/serve-benchmark/pslinux.patch

Configure `config=<path/to/tsconfig>` in `start-service.sh`, and configure SSL key/password in used `tsconfig` as the same for backend pod

Start TorchServe frontend. `<cores_per_worker>` and `<worker_num>` are the same value as for backend, `<backend_pod_ip>` can be obtained by `kubectl get pods <backend_pod> -o wide`

	bash start-service.sh <worker_num> <cores_per_worker> <backend_pod_ip>

## Torchserve Benchmark ##

### Prepare Dataset ###
Download dataset file for benchmark, here we use validation split of SST-2 dataset ([download link](https://dl.fbaipublicfiles.com/glue/data/SST-2.zip)) for reference.

### Performance Benchmark ###

Use `convert_data_to_json.py` to convert the original tsv dataset file to  the format for sending request with lua script. Modify `raw_data_path` and `output_path` to the path of input tsv file and output file.

Modify dataset file path `"data/SST-2/dev.txt"` in `test_bert.lua` to the converted file path in the previous step.

Firstly warmup for 5s, `<worker_num>` is the backend worker number, `<frontend_pod_ip>` is the frontend pod IP, below is the example to benchmark bert-large BF16:

	 wrk -d5s -c<worker_num> -t2 -s test_bert.lua --latency https://<frontend_pod_ip>:8085/predictions/BERT_LARGE_JIT_BF16_IPEX

Run wrk test for 60s, usually we run 3 rounds and take average for final result.

	wrk -d60s -c<worker_num> -t2 -s test_bert.lua --latency https://<frontend_pod_ip>:8085/predictions/BERT_LARGE_JIT_BF16_IPEX
### Accuracy Benchmark ###
Benchmark serving accuracy with `accuracy_test.py`, for example:

	python accuracy_test.py -i <frontend_pod_ip> -p 8085 -d fp32 --dataset_path data/SST-2/dev.tsv
Note that `dataset_path` is the path of the original tsv dataset file.
