import pandas as pd

raw_data_path = 'data/SST-2/dev.tsv'
output_path = 'data/SST-2/dev.txt'

data_df = pd.read_csv(raw_data_path, sep='\t')
sentences = pd.DataFrame(data_df['sentence'], columns=['sentence'])

with open(output_path, 'a') as f:
    for index, row in sentences.iterrows():
        row_str = '{"input":["' + row['sentence'] + '"]}'
        f.write(row_str+'\n')

