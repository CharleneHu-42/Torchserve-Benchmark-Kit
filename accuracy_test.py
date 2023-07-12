import requests
import argparse
import ast
import numpy as np
import pandas as pd
import urllib3
import os

urllib3.disable_warnings()

parser = argparse.ArgumentParser()
parser.add_argument('-i', '--ip', type=str, metavar='', required=True,
                        help=('torchserve frontend IP'))
parser.add_argument('-p', '--port', type=str, default='8085', metavar='',
                        help=('torchserve inference port'))
parser.add_argument('-d', '--dtype', type=str, default='fp32', metavar='',
                        help=('datatype of serving model, choose from fp32/bf16/int8'))
parser.add_argument('--dataset_path', type=str, metavar='', required=True,
                        help=('path of dataset file'))

args = parser.parse_args()
serve_ip = args.ip
serve_port = args.port
dtype = args.dtype
if dtype == "fp32":
    serve_model = "BERT_LARGE_JIT_FP32_IPEX"
elif dtype == "bf16":
    serve_model = "BERT_LARGE_JIT_BF16_IPEX"
elif dtype == "int8":
    serve_model = "BERT_LARGE_INT8_IPEX"

os.environ["no_proxy"] = serve_ip

url = "https://" + serve_ip + ":" + serve_port + "/predictions/" + serve_model
raw_data_path = args.dataset_path
data_df = pd.read_csv(raw_data_path, sep='\t')
sentences = pd.DataFrame(data_df['sentence'], columns=['sentence'])

response_list = []
for index, row in sentences.iterrows():
    line = '{"input":["' + row['sentence'] + '"]}'
    response = requests.put(url, data=line.encode("utf-8"), verify=False)
    try:
        response_list.append(ast.literal_eval(response.content.decode("utf-8"))[0])
    except:
        print("Request:", line)
        print("Response:", response.content.decode("utf-8"))

response_arr = np.array(response_list)
preds = np.argmax(response_arr,axis=1)

labels = pd.DataFrame(data_df['label'], columns=['label']).values.transpose()
print("Model", serve_model, "serve accuracy:", (preds == labels).mean())
