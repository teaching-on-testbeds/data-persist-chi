

::: {.cell .markdown}

## Using block storage

Until now, in any experiment we have run on Chameleon, the data in our experiment did not persist beyond the lifetime of our compute. That is, once the VM instance is deleted, any data we may have generated disappears with it. For example, if we were using MLFlow for experiment tracking, when the compute instance that the MLFlow service is running on stops, we would lose all of our tracking history.

For a longer-term project, we will of course want to be able to persist data beyond the lifetime of the compute instance. That way, we can provision a compute instance, do some work, delete the compute instance, and then resume later with a *new* compute instance but pick off where we left off with respect to *data*. 

To enable this, we can create a block storage volume, which can be attached to, detached from, and re-attached to a **VM instance**> Data stored on the block storage volume persists until the block storage volume itself is created.

After you run this experiment, you will know how to 

* create a block storage volume at KVM@TACC, 
* attach it to an instance,
* create a filesystem on it and mount it,
* create and use Docker volumes on the block storage volume.
* and re-attach the block storage volume to a new instance after the original compute instance ends.

:::

::: {.cell .markdown}

### Block storage using the Horizon GUI

First, let's try creating a block storage volume from the OpenStack Horizon GUI. Open the GUI for KVM@TACC:

* from the [Chameleon website](https://chameleoncloud.org/hardware/)
* click "Experiment" > "KVM@TACC"
* log in if prompted to do so
* check the project drop-down menu near the top left (which shows e.g. "CHI-XXXXXX"), and make sure the correct project is selected.

In the menu sidebar on the left side, click on "Volumes" > "Volumes" and then, "Create Volume". You will be prompted to set up your volume step by step using a graphical "wizard".

* Specify the name as <code>block-persist-<b>netID</b></code> where in place of <code><b>netID</b></code> you substitute your own net ID (e.g. `ff524` in my case). 
* Specify the size as 2 GiB.
* Leave other settings at their defaults, and click "Create Volume".

Next, it's time to to attach the block storage volume to the compute instance we created earlier. From  "Volumes" > "Volumes", next to *your* volume, click the ▼ in the menu on the right and choose "Manage Attachments". In the "Attach to Instance" menu, choose your compute instance. Then, click "Attach Volume".

Now, the "Volumes" overview page in the Horizon GUI should show something like for your volume:

```
| Name                | Description | Size | Status | Group | Type     | Attached To                     | Availability Zone | Bootable | Encrypted |
|---------------------|-------------|------|--------|-------|----------|---------------------------------|-------------------|----------|-----------|
| block-persist-netID | -           | 2GiB | In-use | -     | ceph-ssd | /dev/vdb on node-persist-netID  | nova              | No       | No        |
```

On the instance, let's confirm that we can see the block storage volume. Run

```bash
# run on node-persist
lsblk
```

and verify that `vdb` appears in the output.

The volume is essentially a raw disk. Before we can use it **for the first time** after creating it, we need to partition the disk, create a filesystem on the partition, and mount it. In subsequent uses, we will only need to mount it.

> **Note**: if the volume already had data on it, creating a filesystem on it would erase all its data! This procedure is *only* for the initial setup of a volume, before it has any data on it.

First, we create a partition with an `ext4` filesystem, occupying the entire volume:

```bash
# run on node-persist
sudo parted -s /dev/vdb mklabel gpt
sudo parted -s /dev/vdb mkpart primary ext4 0% 100%
```

Verify that we now have the partition `vdb1` in the output of 

```bash
# run on node-persist
lsblk
```

Next, we format the partition:

```bash
# run on node-persist
sudo mkfs.ext4 /dev/vdb1
```

Finally, we can create a directory in the local filesystem, mount the partition to that directory:

```bash
# run on node-persist
sudo mkdir -p /mnt/block
sudo mount /dev/vdb1 /mnt/block
```

and change the owner of that directory to the `cc` user:

```bash
# run on node-persist
sudo chown -R cc /mnt/block
sudo chgrp -R cc /mnt/block
```

Run

```bash
# run on node-persist
df -h
```

and verify that the output includes a line with `/dev/vdb1` mounted on `/mnt/block`:

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb1       2.0G   24K  1.9G   1% /mnt/block
```

:::


::: {.cell .markdown}

### Create Docker volumes on persistent storage

Now that we have a block storage volume attached to our VM instance, let's see how persistent storage can be useful.

Suppose we are going to train some ML models. We will use MLFlow for experiment tracking. However, we won't necessarily be running MLFlow *all* the time. We will probably have to bring our "platform" VM(s) down and up as we iterate on our platform design. We don't want to lose all past experiment logs and models every time we bring the VMs down.

MLFLow uses two types of data systems: a relational database (Postgresql) for experiments, metrics, and parameters; and for unstructured data like artifacts and saved models, a MinIO object store. (We could hypothetically ask MinIO to use Chameleon's object store instead of running our own MinIO, but since we have already set it up for MinIO, we'll stick to that.) 

We can use a persistent block storage backend for both types of data storage to make sure that experiment logs and models persist even when the VM instance hosting MLFlow is not running.

:::

::: {.cell .markdown}

We are now going to use Docker Compose to bring up a set of services on the VM instance:

* an MLFlow server.
* a Postgresql database with persistent storage: the host directory `/mnt/block/postgres_data`, which is on the block storage volume, is going to be mounted to `/var/lib/postgresql/data` inside the container.
* a MinIO object store with persistent storage: the host directory `/mnt/block/minio_data`, which is on the block storage volume, is going to be mounted to `/data` inside the container.
* and a Jupyter server. As before, we pass the object store mount to the Jupyter server, so that it can also access the Food11 dataset in the object store.

To bring up these services, run

```bash
# run on node-persist
HOST_IP=$(curl --silent http://169.254.169.254/latest/meta-data/public-ipv4 ) docker compose -f ~/data-persist-chi/docker/docker-compose-block.yaml up -d
```

(we need to define `HOST_IP` so that we can set the MLFLow tracking URI in the Jupyter environment.)

Run

```bash
# run on node-persist
docker logs jupyter
```

and look for a line like

```
http://127.0.0.1:8888/lab?token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Paste this into a browser tab, but in place of 127.0.0.1, substitute the floating IP assigned to your instance, to open the Jupyter notebook interface that is running on your compute instance. In the "work" directory, find and open "demo.ipynb".

Also open the MLFlow service web UI: it is at


```
http://A.B.C.D:8000
```

where in place of `A.B.C.D`, you substitute the floating IP assigned to your instance.

Let's add some MLFlow tracking to our "demo.ipynb" notebook. (There's no model training in that notebook - it's just an evaluation - but it works for demo purposes!) At the end, add a cell:

```python
import mlflow
import mlflow.pytorch
mlflow.set_experiment("food11-classifier")
with mlflow.start_run():
    mlflow.log_metric(key="eval_accuracy", value=overall_accuracy)
    mlflow.pytorch.log_model(model, "food11")
```

and run the notebook.

Confirm in the MLFlow UI that both items are logged:

* the evaluation accuracy is logged as a metric, which will be stored in the Postgresql relational database
* the model is logged as an artifact, which will be stored in a MinIO bucket

:::

::: {.cell .markdown}

Now, let's confirm that the MLFlow data persists beyond the lifetime of the compute instance! We will now delete the compute instance.

The following cells run in the **Chameleon** Jupyter environment (not in the Jupyter environment that you are hosting on your compute instance!)

:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
from chi import context, server, lease
import chi
import os

context.version = "1.0" 
context.choose_project()  # Select the correct project
context.choose_site(default="KVM@TACC")
username = os.getenv('USER') # exp resources will have this suffix
```
:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# delete the old server instance!
s_old = server.get_server(f"node-persist-{username}")
s_old.delete()
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
l = lease.get_lease(f"lease-persist-{username}")
s = server.Server(
    f"node-persist-{username}", 
    image_name="CC-Ubuntu24.04",
    flavor_name=l.get_reserved_flavors()[0].name
)
s.submit(idempotent=True)
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
s.associate_floating_ip()
```
:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
s.refresh()
s.check_connectivity()
```
:::



::: {.cell .code}
```python
# run in Chameleon Jupyter environment
s.refresh()
s.show(type="widget")
```
:::



::: {.cell .code}
```python
# run in Chameleon Jupyter environment
security_groups = [
  {'name': "allow-ssh", 'port': 22, 'description': "Enable SSH traffic on TCP port 22"},
  {'name': "allow-8888", 'port': 8888, 'description': "Enable TCP port 8888 (used by Jupyter)"},
  {'name': "allow-8000", 'port': 8000, 'description': "Enable TCP port 8000 (used by MLFlow)"},
  {'name': "allow-9000", 'port': 9000, 'description': "Enable TCP port 9000 (used by MinIO API)"},
  {'name': "allow-9001", 'port': 9001, 'description': "Enable TCP port 9001 (used by MinIO Web UI)"}
]

os_conn = chi.clients.connection()
nova_server = chi.nova().servers.get(s.id)

for sg in security_groups:
  nova_server.add_security_group(sg['name'])

print(f"updated security groups: {[group.name for group in nova_server.list_security_group()]}")
```
:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
s.execute("git clone https://github.com/teaching-on-testbeds/data-persist-chi")
```
:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
s.execute("curl -sSL https://get.docker.com/ | sudo sh")
s.execute("sudo groupadd -f docker; sudo usermod -aG docker $USER")
```
:::

::: {.cell .markdown}

This cell will attach the block storage volume named "block-persist-**netID**" to your compute instance - edit it to substitute your *own* net ID:
:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
cinder_client = chi.clients.cinder()
volume = [v for v in cinder_client.volumes.list() if v.name=='block-persist-netID'][0] # Substitute your own net ID

volume_manager = chi.nova().volumes
volume_manager.create_server_volume(server_id = s.id, volume_id = volume.id)
```
:::


::: {.cell .markdown}

You can confirm in the Horizon GUI that your block storage volume is now attached to the new compute instance.

:::



::: {.cell .markdown}

Let's confirm that data we put on the block storage volume earlier, is now available on the new compute instance. 


Connect to the new instance over SSH. Mount the block storage volume:


```bash
# run on node-persist
sudo mkdir -p /mnt/block
sudo mount /dev/vdb1 /mnt/block
```

and confirm that it is not empty:

```bash
# run on node-persist
ls /mnt/block
```


for example, you can see previously logged artifacts saved by MinIO:


```bash
# run on node-persist
ls /mnt/block/minio_data/mlflow-artifacts/1/
```


Use Docker compose to bring up the services again:

```bash
# run on node-persist
HOST_IP=$(curl --silent http://169.254.169.254/latest/meta-data/public-ipv4 ) docker compose -f ~/data-persist-chi/docker/docker-compose-block.yaml up -d
```

In your browser, open the MLFlow service web UI at


```
http://A.B.C.D:8000
```

where in place of `A.B.C.D`, you substitute the floating IP assigned to your instance. Verify that the experiment runs logged by the previous compute instance are persisted to the new MLFlow instance.

:::

::: {.cell .markdown}


This MLFlow demo is just an example - the same principle applies to any other platform service we might use. Services like Prometheus that run directly on a VM can use an attached block storage volume. Services like Ray, which run on bare metal for GPU training, can use a MinIO storage backend that is hosted on a VM, and uses an attached block storage volume.

:::

::: {.cell .markdown}

### Reference: creating block volumes storage using Python

We created our block storage volume using the Horizon GUI. However it is also worthwhile to learn how to create and manage block storage volumes directly in Python, if you are automating infrastructure setup using a Python notebook.

:::

::: {.cell .markdown}

In OpenStack, the Cinder service provides block storage volumes. We can access the already-configured (authenticated) Cinder client from `python-chi` - 

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# get the Cinder Python client configured by python-chi
cinder_client = chi.clients.cinder()

```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# list current volumes
cinder_client.volumes.list()
```
:::

::: {.cell .markdown}

We can use the Cinder client to create a *new* block storage volume:

:::



::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# create a volume, specifying name and size in GiB
volume = cinder_client.volumes.create(name=f"block-persist-python-{username}", size=2)
volume._info
```
:::

::: {.cell .markdown}

We can attach the volume to a compute instance:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
server_id = chi.server.get_server(f"node-persist-{username}").id
volume_manager = chi.nova().volumes
volume_manager.create_server_volume(server_id = s.id, volume_id = volume.id)
```
:::

::: {.cell .markdown}

or detach the volume from a compute instance:

:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
volume_manager.delete_server_volume(server_id = s.id, volume_id = volume.id)
```
:::

::: {.cell .markdown}

Or, to completely delete a volume (loses all the data!):

:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
cinder_client.volumes.delete(volume = volume)
```
:::

