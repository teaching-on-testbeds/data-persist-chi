
::: {.cell .markdown}

## Local baseline: ImageFolder from a Docker volume

Before we involve object storage, we will measure a local baseline. This helps us answer: if the training input pipeline was purely local disk reads, what throughput would we get?

We will use Docker Compose to run a simple ETL pipeline that prepares Food11 inside a Docker volume, and then we will run a Jupyter container with that volume mounted. Inside the Jupyter environment, we will run a benchmark notebook that uses `torchvision.datasets.ImageFolder`.

:::

::: {.cell .markdown}

### ETL pipeline (extract + transform)

The ETL pipeline stages are defined in `~/data-persist-chi/object/docker/local.yaml`.

It uses a shared Docker volume named `food11_local_baseline`:

* `extract-data` downloads and unzips Food11 into the volume.
* `transform-data` reorganizes images into class subdirectories so they can be read by `ImageFolder`.

After the transform stage, the volume contains a normal directory tree (one file per image) that looks like this when mounted at `/mnt/Food-11`:

```text
/mnt/Food-11/
  training/
    class_00/
      0_0.jpg
      0_1.jpg
      ...
    class_01/
      1_0.jpg
      ...
    ...
  validation/
    class_00/
      0_0.jpg
      ...
    ...
  evaluation/
    class_00/
      0_0.jpg
      ...
    ...
```

Run the extract stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/local.yaml run extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/local.yaml run transform-data
```

:::

::: {.cell .markdown}

### Run Jupyter with the dataset mounted

Now run a Jupyter container and mount:

* the Food11 data volume at `/mnt/Food-11` (read-only)
* the lab notebooks at `/home/jovyan/work`

Run:

```bash
# run on node-object
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e FOOD11_DATA_DIR=/mnt/Food-11 \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  -v food11_local_baseline:/mnt/Food-11:ro \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest
```

To access the Jupyter service, get its token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `imagefolder_local.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is `torchvision.datasets.ImageFolder`, pointing at a local directory (`/mnt/Food-11/<split>`). The DataLoader reads individual image files from the mounted volume, decodes them (PIL), applies a resize/crop/normalize transform, and batches tensors.

When you are done with the local baseline, stop the container:

```bash
# run on node-object
docker stop jupyter
```

:::
