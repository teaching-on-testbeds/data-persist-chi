
::: {.cell .markdown}

## Rclone baseline: ImageFolder on an rclone mount

In this part, we will:

1. Run an ETL pipeline to upload Food11 to the S3 bucket.
2. Use the rclone mount from the previous step.
3. Pass the mount into a Jupyter container.
4. Run the ImageFolder benchmark.

:::

::: {.cell .markdown}

### ETL pipeline (extract + transform + load to S3)

The pipeline stages are defined in `~/data-persist-chi/object/docker/docker-compose-object-load.yaml`.

It will upload the Food11 directory tree to:

* `rclone_s3:object-chi-netID/Food-11/`

First, set the bucket/container name (replace **netID**):

```bash
# run on node-object-chi
export RCLONE_CONTAINER=object-chi-netID
```

Run the extract stage:

```bash
# run on node-object-chi
docker compose -f ~/data-persist-chi/object/docker/docker-compose-object-load.yaml run extract-data
```

Run the transform stage:

```bash
# run on node-object-chi
docker compose -f ~/data-persist-chi/object/docker/docker-compose-object-load.yaml run transform-data
```

Run the load stage:

```bash
# run on node-object-chi
docker compose -f ~/data-persist-chi/object/docker/docker-compose-object-load.yaml run load-data
```

Confirm the upload by listing the mount (we expect a `Food-11/` directory):

```bash
# run on node-object-chi
ls /tmp/rclone-tests/object
```

:::

::: {.cell .markdown}

### Run Jupyter with the mount passed into the container

Start a Jupyter container and pass the mount into the container at `/mnt/Food-11`.

Note: when bind-mounting a FUSE filesystem into Docker, prefer `--mount`.

```bash
# run on node-object-chi
docker run -d --rm \
  -p 8888:8888 \
  -e FOOD11_DATA_DIR=/mnt/Food-11/Food-11 \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --mount type=bind,source=/tmp/rclone-tests/object,target=/mnt/Food-11,readonly \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:python-3.11
```

Get the Jupyter token:

```bash
# run on node-object-chi
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `imagefolder_rclone_mount.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

Stop the container when you are done:

```bash
# run on node-object-chi
docker stop jupyter
```

:::

::: {.cell .markdown}

### Unmount

When you are ready to unmount:

```bash
# run on node-object-chi
fusermount -u /tmp/rclone-tests/object
```

:::
