
::: {.cell .markdown}

## Sharded baseline: stream tar shards from S3

In this part, we will create larger shard objects (tar files) and stream from those shards during training input.

Compared to reading one S3 object per sample, sharding reduces per-sample overhead by reading many samples from each shard.

:::

::: {.cell .markdown}

### ETL pipeline (extract + transform + shard + upload)

The pipeline stages are defined in `~/data-persist-chi/object/docker/wds.yaml`.

It will upload tar shards to:

* `rclone_s3:object-chi-netID/Food-11-webdataset/`

In this ETL, we take the same images, but we pack many samples into larger `.tar` shard objects. After upload, the prefix looks like:

```text
s3://object-chi-netID/Food-11-webdataset/
  training/
    shard-000000.tar
    shard-000001.tar
    ...
  validation/
    shard-000000.tar
    ...
  evaluation/
    shard-000000.tar
    ...
```

Each tar file contains many samples; for each sample key there is a `*.jpg` payload (image bytes) and a `*.cls` payload (the integer label as text).

First, set the bucket/container name (replace **netID**):

```bash
# run on node-object
export RCLONE_CONTAINER=object-chi-netID
```

Run the extract stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run --rm extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run --rm transform-data
```

Build the shards:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run --rm shard-webdataset
```

Load the shards to S3:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run --rm load-webdataset
```

:::

::: {.cell .markdown}

### Run Jupyter with S3 credentials as environment variables

To stream shards from S3 inside the container, we pass credentials via environment variables in the `docker run` command.

In the following command:

* replace **ACCESS_KEY_ID** with your EC2 Access
* replace **SECRET_ACCESS_KEY** with your EC2 Secret
* replace **netID** in the bucket name

```bash
# run on node-object
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e AWS_ACCESS_KEY_ID=ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=SECRET_ACCESS_KEY \
  -e S3_ENDPOINT_URL=https://chi.tacc.chameleoncloud.org:7480 \
  -e S3_BUCKET=object-chi-netID \
  -e S3_PREFIX=Food-11-webdataset \
  -e FOOD11_SPLIT=evaluation \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest
```

Get the Jupyter token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `webdataset.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is an `IterableDataset` that assigns shard files across DataLoader workers, opens each shard via `fsspec`, streams the tar entries, and yields `(image_tensor, label)` pairs. The DataLoader batches those streamed samples.

Stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```

:::
