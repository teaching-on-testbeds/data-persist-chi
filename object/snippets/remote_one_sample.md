
::: {.cell .markdown}

## Remote baseline: one object per sample (no mount)

In this part, we will read training data directly from S3 without mounting it as a filesystem.

The DataLoader will load each sample by making a separate S3 request for that image. This pattern is simple, but it often performs poorly at scale because it has high per-sample overhead.

We will run a benchmark notebook that uses `fsspec` to open remote objects and `PIL` to decode images.

:::

::: {.cell .markdown}

### Run Jupyter with S3 credentials as environment variables

To access S3 from inside the container, we pass credentials via environment variables in the `docker run` command.

In the following command:

* replace **ACCESS_KEY_ID** with your EC2 Access
* replace **SECRET_ACCESS_KEY** with your EC2 Secret
* replace **netID** in the bucket name

```bash
# run on node-object-chi
docker run -d --rm \
  -p 8888:8888 \
  -e AWS_ACCESS_KEY_ID=ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=SECRET_ACCESS_KEY \
  -e S3_ENDPOINT_URL=https://chi.tacc.chameleoncloud.org:7480 \
  -e S3_BUCKET=object-chi-netID \
  -e S3_PREFIX=Food-11 \
  -e FOOD11_SPLIT=evaluation \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:python-3.11
```

Get the Jupyter token:

```bash
# run on node-object-chi
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `remote_one_sample.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

Stop the container when you are done:

```bash
# run on node-object-chi
docker stop jupyter
```

:::
