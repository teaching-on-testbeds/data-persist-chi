
::: {.cell .markdown}

## Optimized baseline: LitData streaming over S3

In this part, we will write the dataset in a [LitData](https://github.com/Lightning-AI/litdata/) optimized format and then stream it from S3.

In this benchmark notebook, the Dataset is `litdata.StreamingDataset`, pointing at `s3://<bucket>/<prefix>/<split>`. It streams data into a local cache directory inside the container (`./litdata_cache` by default), and the `StreamingDataLoader` iterates it with worker processes. We decode each sample to a tensor in the collate function and then measure steady-state throughput.

This approach combines sharding with some other optimizations + a local cache.

:::

::: {.cell .markdown}

### ETL pipeline (optimize + load)

The pipeline stages are defined in `~/data-persist-chi/object/docker/lit.yaml`.

This pipeline re-uses the extract and first transform step from the local baseline: we kept the organized Food11 directory tree in a Docker volume (`food11_local_baseline`). This stage reads images from that staging volume (read-only), writes LitData output to a separate output volume, and then loads that output into S3.

It will upload optimized data to:

* `rclone_s3:object-chi-netID/Food-11-litdata/`

Instead of uploading individual image files, this ETL uses `litdata.optimize(...)` to write a streaming-friendly dataset format. The output is a directory per split with multiple chunk files plus metadata (exact filenames are implementation-specific), for example:

```text
s3://object-chi-netID/Food-11-litdata/
  training/
    <metadata files>
    <chunk files>
    ...
  validation/
    <metadata files>
    <chunk files>
    ...
  evaluation/
    <metadata files>
    <chunk files>
    ...
```

First, set the bucket/container name (replace **netID**):

```bash
# run on node-object
export RCLONE_CONTAINER=object-chi-netID
```

Build the optimized dataset:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run --rm optimize-litdata
```

Load the optimized dataset to S3:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run --rm load-litdata
```

After the load step finishes, open the Horizon GUI for CHI@TACC and navigate to "Object Store" > "Containers". Click on your container (`object-chi-netID`) and you should see a `Food-11-litdata/` prefix. Inside it, expect `training/`, `validation/`, and `evaluation/` directories containing LitData metadata and chunk files.

To free disk space after you finish the load step, remove the local LitData output volume:

```bash
# run on node-object
docker volume rm food11-litdata_lit_out
```

If Docker says the volume is in use, remove the stopped container(s) that still reference it, then try again:

```bash
# run on node-object
docker ps -a --filter volume=food11-litdata_lit_out --format "{{.ID}}" | xargs -r docker rm -f
docker volume rm food11-litdata_lit_out
```

:::

::: {.cell .markdown}

### Run Jupyter with S3 credentials as environment variables

To stream from S3 inside the container, we pass credentials via environment variables in the `docker run` command.

In the following command:

* replace **ACCESS_KEY_ID** with your EC2 Access
* replace **SECRET_ACCESS_KEY** with your EC2 Secret
* replace **netID** in the bucket name

This step installs `litdata` in the Jupyter container before starting the notebook server.

```bash
# run on node-object
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e AWS_ACCESS_KEY_ID=ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=SECRET_ACCESS_KEY \
  -e S3_ENDPOINT_URL=https://chi.tacc.chameleoncloud.org:7480 \
  -e S3_BUCKET=object-chi-netID \
  -e S3_PREFIX=Food-11-litdata \
  -e FOOD11_SPLIT=training \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest \
  bash -lc "pip -q install litdata==0.2.60 && start-notebook.py"
```

Get the Jupyter token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

It may take a few moments for the server to start (for the `pip install` to finish), so if no servers are listed in the output of that command, just wait a minute and then try again.

Open the printed URL in your browser, substituting the floating IP for `localhost`.

Before you start the benchmark in the Jupyter UI, open a separate SSH terminal on the node (not inside the Jupyter container) and run:

```bash
# run on node-object
sudo nload ens3
``` 
    
to monitor network traffic. Take a screenshot while the benchmark is running. 
  
In the Jupyter UI, open and run `litdata_streaming.ipynb`. When the benchmark finishes, it will print the results and write a JSON results file under `results/`. Download the JSON file from the `results/` folder in the Jupyter file browser.

Note that it will also create a `litdata_cache` directory in the workspace. It will keep chunks there (on the local disk) so they don't *always* have to be streamed from the remote object storage.

Run the benchmark notebook *again* and note the results; it can be substantially faster on this run, since some of the data is already cached. Take a screenshot. You may notice that less data is transferred over the network on the second run. We can tune `max_cache_size` and `max_pre_download` in the `StreamingDataset` to manage the tradeoff between network and local disk use.

Close the browser tab and stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```

:::
