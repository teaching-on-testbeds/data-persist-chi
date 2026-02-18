
::: {.cell .markdown}

## Sharded baseline: stream tar shards from S3

In this part, we will create larger shard objects (tar files) and stream from those shards during training input.

In this benchmark notebook, the Dataset is an `IterableDataset` that assigns shard files across DataLoader workers, opens each shard via `fsspec`, streams the tar entries, and yields `(image_tensor, label)` pairs. The DataLoader batches those streamed samples.

Compared to reading one S3 object per sample, sharding reduces per-sample overhead by reading many samples from each shard.

:::

::: {.cell .markdown}

### ETL pipeline (shard + load)

The pipeline stages are defined in `~/data-persist-chi/object/docker/wds.yaml`.

This pipeline re-uses the extract and first transform step from the local baseline: we kept the organized Food11 directory tree in a Docker volume (`food11_local_baseline`). This stage reads images from that staging volume (read-only), writes shards to a separate output volume, and then loads those shards into S3.

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

After the load step finishes, open the Horizon GUI for CHI@TACC and navigate to "Object Store" > "Containers". Click on your container (`object-chi-netID`) and you should see a `Food-11-webdataset/` prefix. Inside it, expect `training/`, `validation/`, and `evaluation/` directories with multiple `shard-*.tar` objects.

Note: it is normal to occasionally see transient upload errors like "source file is being updated (size changed...)". This can happen if a shard is still being finalized while rclone starts uploading. It is fine as long as rclone succeeds on a retry and the final output shows 100% of shards transferred.

To free disk space after you finish the load step, remove the local shard output volume:

```bash
# run on node-object
docker volume rm food11-webdataset_wds_out
```

If Docker says the volume is in use, remove the stopped container(s) that still reference it, then try again:

```bash
# run on node-object
docker ps -a --filter volume=food11-webdataset_wds_out --format "{{.ID}}" | xargs -r docker rm -f
docker volume rm food11-webdataset_wds_out
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
  -e FOOD11_SPLIT=training \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest \
  bash -lc "pip -q install s3fs webdataset==1.0.2 && start-notebook.py"
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

to monitor network traffic. In particular, note the current (`Curr`) incoming data rate shown to the side of the ASCII plot. Take a screenshot while the benchmark is running. You may notice a different network access pattern than in your previous tests!

In the Jupyter UI, open and run `webdataset.ipynb`. When the benchmark finishes, it will print the results and write a JSON results file under `results/`. Download the JSON file from the `results/` folder in the Jupyter file browser.

Close the browser tab for the Jupyter server running inside the instance, and stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```

:::
