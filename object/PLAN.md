# data-object-chi plan

## Goal

Refocus this lab on training input performance when training data is stored in object storage, using Food11 and side-by-side DataLoader benchmarks.

Students should not write code in the lab. They should run provided commands and run provided notebooks from `workspace/`.

## Important constraint

This repo update is designed without executing Docker Compose pipelines or running notebook Python code locally in this dev environment. Validation here is limited to static checks (paths, references, build of markdown-generated lab notebooks). Runtime behavior must be validated in Chameleon.

## Scope

- Work in `labs/data-persist-chi/object`
- Assume VM repo layout:
  - `~/data-persist-chi/object/...`
- Keep notebook snippets flow (`0_intro`, `1_create_server`, `2_object`, `3_delete`)
- Keep ETL/packing logic in `docker/`
- Keep runnable benchmark notebooks in `workspace/`

## Naming decisions

- Rename server/lease to object-specific names:
  - `lease-object-chi-{username}`
  - `node-object-chi-{username}`

## Notebook strategy

One benchmark notebook per DataLoader type. Each notebook includes:

- DataLoader definition
- Benchmark code
- Results output

Notebook names will match DataLoader pattern:

- `imagefolder_local.ipynb`
- `imagefolder_rclone_mount.ipynb`
- `remote_one_sample.ipynb`
- `webdataset.ipynb`
- `litdata_streaming.ipynb`

(Each notebook writes results to `workspace/results/`.)

## Target lab flow

0. Local baseline:
   - Use Docker Compose to extract/transform Food11 into local Docker volume
   - Attach that data to Jupyter container
   - Run `imagefolder_local.ipynb`

1. Create object store container (bucket equivalent in this lab context)

2. ETL to object store:
   - Use Docker Compose pipeline to load Food11 into object store (`Food-11/`)

3. Mount object store with rclone:
   - Use `/tmp/rclone-tests/object`
   - Pass mount into container
   - Run `imagefolder_rclone_mount.ipynb`

4. Unmount rclone and stream one-sample-at-a-time:
   - Use chapter-style fsspec/open-per-sample dataset
   - Run `remote_one_sample.ipynb`

5. WebDataset sharded path:
   - Run a dedicated Docker Compose pipeline that starts from scratch and writes WebDataset shards
   - Run `webdataset.ipynb`

6. LitData optimized path:
   - Run a dedicated Docker Compose pipeline that starts from scratch and writes LitData optimized chunks
   - Run `litdata_streaming.ipynb`

## Docker plan

Create separate compose files under `docker/`, each representing one full ETL path from scratch:

- `docker-compose-local-baseline.yaml`
  - extract + transform to local Docker volume for local ImageFolder benchmark

- `docker-compose-object-load.yaml`
  - extract + transform + load to object store (`Food-11/`)

- `docker-compose-webdataset.yaml`
  - extract + transform + shard to WebDataset + upload (`Food-11-webdataset/`)

- `docker-compose-litdata.yaml`
  - extract + transform + optimize to LitData chunks + upload (`Food-11-litdata/`)

All compose files:

- Keep ETL logic inside `docker/`
- Use `RCLONE_CONTAINER` env var
- Mount `~/.config/rclone/rclone.conf` where needed
- Log outputs clearly and deterministically

## Snippet rewrite plan

### `snippets/intro.md`

- Reframe objective as training-input benchmarking for object storage
- Mention students run prepared notebooks from `workspace/`
- Update paths to `data-persist-chi/object`

### `snippets/create_server.md`

- Rename lease/server (`lease-object-chi-*`, `node-object-chi-*`)
- Use clone:
  - `git clone https://github.com/teaching-on-testbeds/data-persist-chi`
- Use object-lab subdir paths
- Keep required ports minimal (`22`, `8888`)

### `snippets/webdataset.md`

Add a runbook step for WebDataset-style sharding (tar shards) and benchmarking.

### `snippets/delete.md`

Keep cleanup notebook:

- delete `node-object-chi-{username}`
- delete object container and contents
- do not delete lease explicitly

### `README.md`

Update summary to match benchmark-oriented lab and subdirectory layout.

## Makefile plan

Keep snippet-generated notebooks:

- `0_intro.ipynb`
- `1_create_server.ipynb`
- `2_object.ipynb`
- `3_delete.ipynb`

Ensure `clean` explicitly removes only generated files (no `*.ipynb` wildcard).

## Benchmark methodology

Since we are benchmarking DataLoader behavior, keep benchmark harness consistent across notebooks:

- fixed image transform
- fixed batch size
- fixed warmup and measured steps
- fixed worker configurations tested per notebook
- write JSON summary to `workspace/results/`

Recommended metrics:

- images/sec
- batches/sec
- p50/p95 batch latency
- time-to-first-batch

## About split choice (evaluation vs training)

We are benchmarking input pipeline behavior, but split can still affect results due to:

- number of files
- class directory layout
- sample count and file-size distribution
- caching effects

Plan:

- use a fixed benchmark subset definition across all methods (same split and same max samples) for fair comparison.
- default to `evaluation` split for shorter runtime and consistency.
- note in notebook that absolute throughput may differ on `training`, but relative method ordering is usually the key takeaway.

## Validation checklist (static in this environment)

1. All `~/data-object-chi/...` paths replaced with `~/data-persist-chi/object/...`
2. Server/lease names updated to object-chi naming
3. No stale references to old single `demo.ipynb` flow
4. Snippet notebooks regenerate via `make clean && make`
5. Docker compose filenames and references match exactly
6. Cleanup flow references correct renamed server and object container
