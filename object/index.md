

# Object storage on Chameleon

This part of the lab focuses on object storage: persisting training data in S3-compatible object storage and benchmarking training input pipelines (local ImageFolder, ImageFolder over an rclone mount, one-object-per-sample reads, and sharded streaming).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.



## Experiment resources 

For this experiment, we will provision 

* one object storage bucket on CHI@TACC
* one virtual machine on KVM@TACC, with a floating IP, to practice using the persistent storage



You will see several notebooks inside the `data-persist-chi/object` directory. Open `0_intro.ipynb` and continue there.





## Launch and set up a VM instance- with python-chi

We will use the `python-chi` Python API to Chameleon to provision a VM instance. 

We will execute the cells in this notebook inside the Chameleon Jupyter environment.

Run the following cell, and make sure the correct project is selected. 


```python
from chi import server, context, lease, network
import chi, os, time, datetime

context.version = "1.0" 
context.choose_project()
context.choose_site(default="KVM@TACC")
username = os.getenv('USER') # all exp resources will have this prefix
```


We will bring up a `m1.large` flavor server with the `CC-Ubuntu24.04` disk image. 

> **Note**: the following cell brings up a server only if you don't already have one with the same name! (Regardless of its error state.) If you have a server in ERROR state already, delete it first in the Horizon GUI before you run this cell.



First we will reserve the VM instance for 4 hours, starting now:



```python
l = lease.Lease(f"lease-object-{username}", duration=datetime.timedelta(hours=4))
l.add_flavor_reservation(id=chi.server.get_flavor_id("m1.large"), amount=1)
l.submit(idempotent=True)
```


```python
l.show()
```



Now we can launch an instance using that lease:



```python
s = server.Server(
    f"node-object-{username}", 
    image_name="CC-Ubuntu24.04",
    flavor_name=l.get_reserved_flavors()[0].name
)
s.submit(idempotent=True)
```



Then, we'll associate a floating IP with the instance:


```python
s.associate_floating_ip()
```


In the output below, make a note of the floating IP that has been assigned to your instance (in the "Addresses" row).


```python
s.refresh()
s.show(type="widget")
```


By default, all connections to VM resources are blocked, as a security measure.  We need to attach one or more "security groups" to our VM resource, to permit access over the Internet to specified ports.

The following security groups will be created (if they do not already exist in our project) and then added to our server:



```python
security_groups = [
  {'name': "allow-ssh", 'port': 22, 'description': "Enable SSH traffic on TCP port 22"},
  {'name': "allow-8888", 'port': 8888, 'description': "Enable TCP port 8888 (used by Jupyter)"}
]
```


```python
for sg in security_groups:
  secgroup = network.SecurityGroup({
      'name': sg['name'],
      'description': sg['description'],
  })
  secgroup.add_rule(direction='ingress', protocol='tcp', port=sg['port'])
  secgroup.submit(idempotent=True)
  s.add_security_group(sg['name'])

print(f"updated security groups: {[sg['name'] for sg in security_groups]}")
```

```python
s.refresh()
s.check_connectivity()
```




### Retrieve code and notebooks on the instance

Now, we can use `python-chi` to execute commands on the instance, to set it up. We'll start by retrieving the code and other materials on the instance.


```python
s.execute("git clone https://github.com/teaching-on-testbeds/data-persist-chi")
```



### Set up Docker

Here, we will set up the container framework.


```python
s.execute("curl -sSL https://get.docker.com/ | sudo sh")
s.execute("sudo groupadd -f docker; sudo usermod -aG docker $USER")
```



## Open an SSH session

Finally, open an SSH sesson on your server. From your local terminal, run

```
ssh -i ~/.ssh/id_rsa_chameleon cc@A.B.C.D
```

where

* in place of `~/.ssh/id_rsa_chameleon`, substitute the path to your own key that you had uploaded to KVM@TACC
* in place of `A.B.C.D`, use the floating IP address you just associated to your instance.



## Local baseline: ImageFolder from a Docker volume

Before we involve object storage, we will measure a local baseline. This helps us answer: if the training input pipeline was purely local disk reads, what throughput would we get?

We will use Docker Compose to run a simple ETL pipeline that prepares Food11 inside a Docker volume, and then we will run a Jupyter container with that volume mounted. Inside the Jupyter environment, we will run a benchmark notebook that uses `torchvision.datasets.ImageFolder`.



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



## Create an object storage bucket

In this lab, we will store training data in object storage so we can reuse it across many training runs and many compute instances.

Chameleon object storage is only offered at the CHI@TACC and CHI@UC sites. It is not offered at KVM@TACC, which is where our VM compute instance runs.

That is not a problem, because object storage is accessed over an API. As long as there is sufficient network bandwidth and reasonably low network latency between compute and storage, we can train on data stored in object storage even when compute and storage are in different logical Chameleon sites.

We will create an object storage bucket (which in OpenStack, is also - confusingly- called a container) at CHI@TACC. Later, we will access this bucket using the S3 API.



### Create the bucket in the Horizon GUI

Open the GUI for CHI@TACC:

* from the [Chameleon website](https://chameleoncloud.org/hardware/)
* click "Experiment" > "CHI@TACC"
* log in if prompted
* check the project drop-down near the top left and make sure the correct project is selected

In the menu sidebar, click "Object Store" > "Containers" and then "Create Container".

Set the name to:

* `object-chi-netID`

where you replace `netID` with your own net ID (for example, `object-chi-ff524`). Leave other settings at defaults and click "Submit".


### Generate S3 credentials

To access this object storage using the S3 API from our compute instance and from our containers, we need an access key and secret key.

In Chameleon, we can generate an EC2-style credential (access key + secret key) for our current user and project.

Important: treat the secret like a password. Save it somewhere safe. If you share screenshots or publish notebooks, clear the cell output first.

The following cells run in the Chameleon Jupyter environment.


```python
# run in Chameleon Jupyter environment
from openstack import connection
from chi import context
import chi

context.choose_project()
context.choose_site(default="CHI@TACC")
```

```python
# run in Chameleon Jupyter environment
conn = connection.from_config()

project_id = conn.current_project_id
identity_ep = conn.session.get_endpoint(service_type="identity", interface="public")
url = f"{identity_ep}/v3/users/{conn.current_user_id}/credentials/OS-EC2"

payload = {"tenant_id": project_id}
response = conn.session.post(url, json=payload)
response.raise_for_status()
ec2 = response.json()["credential"]

print("EC2 Access:", ec2["access"])
print("EC2 Secret:", ec2["secret"])
```


## Mount the bucket with rclone (S3)

In this part, we will mount the S3 bucket as a local filesystem using `rclone mount`.



### Install rclone and enable FUSE allow-other

On the VM instance, install `rclone`:

```bash
# run on node-object
curl https://rclone.org/install.sh | sudo bash
```

We also need to allow mounts created by our user to be visible to other users (including the Docker daemon / containers):

```bash
# run on node-object
sudo sed -i '/^#user_allow_other/s/^#//' /etc/fuse.conf
```



### Configure rclone for S3

Create the rclone config file:

```bash
# run on node-object
mkdir -p ~/.config/rclone
nano ~/.config/rclone/rclone.conf
```

Add a config section named `rclone_s3`. For `access_key_id` and `secret_access_key`, use the EC2 Access and EC2 Secret you generated in the previous step.

```
[rclone_s3]
type = s3
provider = Ceph
access_key_id = ACCESS_KEY_ID
secret_access_key = SECRET_ACCESS_KEY
endpoint = https://chi.tacc.chameleoncloud.org:7480
```

Save (Ctrl + O) and exit (Ctrl + X).

Test that rclone can talk to S3:

```bash
# run on node-object
rclone lsd rclone_s3:
```



### Mount the bucket to a local path

We will mount the bucket at `/tmp/rclone-tests/object`:

```bash
# run on node-object
sudo mkdir -p /tmp/rclone-tests/object
sudo chown -R cc /tmp/rclone-tests/object
sudo chgrp -R cc /tmp/rclone-tests/object
```

Mount the bucket (replace **netID**):

```bash
# run on node-object
rclone mount rclone_s3:object-chi-netID /tmp/rclone-tests/object \
  --read-only \
  --allow-other \
  --vfs-cache-mode off \
  --daemon
```



## Rclone baseline: ImageFolder on an rclone mount

In this part, we will:

1. Run an ETL pipeline to upload Food11 to the S3 bucket.
2. Use the rclone mount from the previous step.
3. Pass the mount into a Jupyter container.
4. Run the ImageFolder benchmark.



### ETL pipeline (extract + transform + load to S3)

The pipeline stages are defined in `~/data-persist-chi/object/docker/load.yaml`.

It will upload the Food11 directory tree to:

* `rclone_s3:object-chi-netID/Food-11/`

The load stage uploads normal files (one object per image) arranged to work well with ImageFolder. After the upload, the S3 prefix looks like this:

```text
s3://object-chi-netID/Food-11/
  training/
    class_00/
      0_0.jpg
      0_1.jpg
      ...
    ...
  validation/
    class_00/
      ...
    ...
  evaluation/
    class_00/
      ...
    ...
```

First, set the bucket/container name (replace **netID**):

```bash
# run on node-object
export RCLONE_CONTAINER=object-chi-netID
```

Run the extract stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/load.yaml run extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/load.yaml run transform-data
```

Run the load stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/load.yaml run load-data
```

Confirm the upload by listing the mount (we expect a `Food-11/` directory):

```bash
# run on node-object
ls /tmp/rclone-tests/object
```



### Run Jupyter with the mount passed into the container

Start a Jupyter container and pass the mount into the container at `/mnt/Food-11`.

Note: when bind-mounting a FUSE filesystem into Docker, prefer `--mount`.

```bash
# run on node-object
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e FOOD11_DATA_DIR=/mnt/Food-11 \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --mount type=bind,source=/tmp/rclone-tests/object/Food-11,target=/mnt/Food-11,readonly \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest
```

Get the Jupyter token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open and run `imagefolder_rclone_mount.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is `torchvision.datasets.ImageFolder`, but the filesystem backing it is an rclone FUSE mount of the S3 bucket. The DataLoader still does ordinary file opens and reads, but every read is translated into S3 GET requests under the hood.

Stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```



### Unmount

When you are ready to unmount:

```bash
# run on node-object
fusermount -u /tmp/rclone-tests/object
```



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

In the Jupyter UI, open and run `remote_one_sample.ipynb`. When the benchmark finishes, it will write a JSON results file under `results/`.

In this notebook, the Dataset is a small custom `torch.utils.data.Dataset` that first lists objects once to build an index (not timed), then loads each sample by doing an S3 GET for that one image via `fsspec`, decoding with PIL, and applying the usual resize/crop/normalize transform. The DataLoader batches those decoded tensors.

Stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```



## Sharded baseline: stream tar shards from S3

In this part, we will create larger shard objects (tar files) and stream from those shards during training input.

Compared to reading one S3 object per sample, sharding reduces per-sample overhead by reading many samples from each shard.



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
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run transform-data
```

Build the shards:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run shard-webdataset
```

Upload the shards:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/wds.yaml run upload-webdataset
```



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



## Optimized baseline: LitData streaming over S3

In this part, we will write the dataset in a LitData optimized format and then stream it from S3.



### ETL pipeline (extract + transform + optimize + upload)

The pipeline stages are defined in `~/data-persist-chi/object/docker/lit.yaml`.

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

Run the extract stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run transform-data
```

Build the optimized dataset:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run optimize-litdata
```

Upload the optimized dataset:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run upload-litdata
```



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
  bash -lc "pip -q install litdata==0.2.32 && start-notebook.sh"
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



## Delete resources

When we are finished, we must delete 

* the VM server instance 
* and the object store container

to make the resources available to other users.

We will execute the cells in this notebook inside the Chameleon Jupyter environment.

Run the following cell, and make sure the correct project is selected. 


```python
# run in Chameleon Jupyter environment
from chi import server, context
import chi, os, time, datetime

context.version = "1.0" 
context.choose_project()
context.choose_site(default="KVM@TACC")
```



Delete the compute instance:



```python
# run in Chameleon Jupyter environment
username = os.getenv('USER')
s = server.get_server(f"node-object-{username}")
s.delete()
```


And finally, delete the object store container at CHI@TACC. We will use the OpenStack Swift client to delete all the objects, and then the container. 



```python
# run in Chameleon Jupyter environment
context.choose_project()
context.choose_site(default="CHI@TACC")
```

```python
# run in Chameleon Jupyter environment
os_conn = chi.clients.connection()
token = os_conn.authorize()
storage_url = os_conn.object_store.get_endpoint()

import swiftclient
swift_conn = swiftclient.Connection(preauthurl=storage_url,
                                    preauthtoken=token,
                                    retries=5)
```


In the following cell, replace **netID** with your own net ID: 


```python
# run in Chameleon Jupyter environment
container_name = "object-chi-netID"
while True:
    _, objects = swift_conn.get_container(container_name, full_listing=True)
    if not objects:
        break
    paths = "\n".join(f"{container_name}/{obj['name']}" for obj in objects)
    swift_conn.post_account(
        headers={"Content-Type": "text/plain"},
        data=paths,
        query_string="bulk-delete"
    )
swift_conn.delete_container(container_name)
print("Container deleted.")
```


<hr>

<small>Questions about this material? Contact Fraida Fund</small>

<hr>

<small>This material is based upon work supported by the National Science Foundation under Grant No. 2230079.</small>

<small>Any opinions, findings, and conclusions or recommendations expressed in this material are those of the author(s) and do not necessarily reflect the views of the National Science Foundation.</small>
