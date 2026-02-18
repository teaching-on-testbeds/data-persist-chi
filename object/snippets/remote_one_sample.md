
::: {.cell .markdown}

## Remote baseline: one object per sample (no mount)

In this part, we will read training data directly from S3 without mounting it as a filesystem.

The DataLoader will load each sample by making a separate S3 request for that image. This pattern is simple, but it often performs poorly at scale because it has high per-sample overhead.

We will run a benchmark notebook that uses `fsspec` to open remote objects and `PIL` to decode images.

This benchmark assumes the dataset is already uploaded as one object per image under `s3://object-chi-netID/Food-11/`, for example:

```text
s3://object-chi-netID/Food-11/
  evaluation/
    class_00/
      0_123.jpg
      ...
    class_01/
      1_456.jpg
      ...
    ...
```

:::

::: {.cell .markdown}

### Run Jupyter with S3 credentials as environment variables

To access S3 from inside the container, we pass credentials via environment variables in the `docker run` command.

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
  -e S3_PREFIX=Food-11 \
  -e FOOD11_SPLIT=training \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest \
  bash -lc "pip -q install s3fs && start-notebook.py"
```

Get the Jupyter token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `remote_one_sample.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is a small custom `torch.utils.data.Dataset` that first lists objects once to build an index (not timed), then loads each sample by doing an S3 GET for that one image via `fsspec`, decoding with PIL, and applying the usual resize/crop/normalize transform. The DataLoader batches those decoded tensors.

Stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```

:::
