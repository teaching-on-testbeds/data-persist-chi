
::: {.cell .markdown}

## Optimized baseline: LitData streaming over S3

In this part, we will write the dataset in a LitData optimized format and then stream it from S3.

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

:::

::: {.cell .markdown}

### Run Jupyter with S3 credentials as environment variables

To stream from S3 inside the container, we pass credentials via environment variables in the `docker run` command.

In the following command:

* replace **ACCESS_KEY_ID** with your EC2 Access
* replace **SECRET_ACCESS_KEY** with your EC2 Secret
* replace **netID** in the bucket name

This step also installs `litdata` in the Jupyter container before starting the notebook server.

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
  -e FOOD11_SPLIT=evaluation \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest \
  bash -lc "pip -q install lightning-utilities==0.15.2 && pip -q install --no-deps litdata==0.2.32 && start-notebook.sh"
```

Get the Jupyter token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `litdata_streaming.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is `litdata.StreamingDataset`, pointing at `s3://<bucket>/<prefix>/<split>`. It streams data into a local cache directory inside the container (`./litdata_cache` by default), and the `StreamingDataLoader` iterates it with worker processes. We decode each sample to a tensor in the collate function and then measure steady-state throughput.

Stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```

:::
