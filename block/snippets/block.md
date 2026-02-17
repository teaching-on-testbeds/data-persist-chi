

::: {.cell .markdown}

## Using block storage

Until now, in any experiment we have run on Chameleon, the data in our experiment did not persist beyond the lifetime of our compute. That is, once the VM instance is deleted, any data we may have generated disappears with it. 

For a longer-term project, we will of course want to be able to persist data beyond the lifetime of the compute instance. That way, we can provision a compute instance, do some work, delete the compute instance, and then resume later with a *new* compute instance but pick off where we left off with respect to *data*. 

To enable this, we can create a block storage volume, which can be attached to, detached from, and re-attached to a VM instance. Data stored on the block storage volume persists until the block storage volume itself is deleted.

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
| block-persist-netID | -           | 2GiB | In-use | -     | ceph-ssd | /dev/vdb on node-block-netID     | nova            | No       | No        |
```

On the instance, let's confirm that we can see the block storage volume. Run

```bash
# run on node-block
lsblk
```

and verify that `vdb` appears in the output.

The volume is essentially a raw disk. Before we can use it **for the first time** after creating it, we need to partition the disk, create a filesystem on the partition, and mount it. In subsequent uses, we will only need to mount it.

> **Note**: if the volume already had data on it, creating a filesystem on it would erase all its data! This procedure is *only* for the initial setup of a volume, before it has any data on it.

First, we create a partition with an `ext4` filesystem, occupying the entire volume:

```bash
# run on node-block
sudo parted -s /dev/vdb mklabel gpt
sudo parted -s /dev/vdb mkpart primary ext4 0% 100%
```

Verify that we now have the partition `vdb1` in the output of 

```bash
# run on node-block
lsblk
```

Next, we format the partition:

```bash
# run on node-block
sudo mkfs.ext4 /dev/vdb1
```

Finally, we can create a directory in the local filesystem, mount the partition to that directory:

```bash
# run on node-block
sudo mkdir -p /mnt/block
sudo mount /dev/vdb1 /mnt/block
```

and change the owner of that directory to the `cc` user:

```bash
# run on node-block
sudo chown -R cc /mnt/block
sudo chgrp -R cc /mnt/block
```

Run

```bash
# run on node-block
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

For example, suppose that as part of a project we train some ML models and use MLFlow to keep track of models and the training runs that produced them. We are not working on our project *all* the time, so we should only bring up compute instances when we are actively working. But if we don't let MLFlow persist its data to some form of storage that lives beyond the lifetime of the compute instance, we would lose past experiment logs and models every time we bring VMs down.

Or, suppose we have a Jupyter service that our engineers use to experiment with model development. Some of these experiments will turn into operationalized model training pipelines, but not all; so we want to give our Jupyter users a persistent filesystem. If we mount a directory inside the Jupyter container (for example, using a Docker volume or a bind mount), then the data stored inside this mount point will persist as long as the backing storage persists.

But, what happens if the compute instance does not stay alive? This is a real concern, not a hypothetical:

* In a production system, we don't want to lose data if something happens to a compute instance. In fact, good DevOps practices suggest we should design our system so it is resilient to a compute instance acting up - we should be able to swap it out for another compute instance.
* When using a cloud environment like Chameleon for projects and development, we aren't going to run compute all the time just to keep data alive! Data is relatively cheap in a cloud, compute costs a lot more. We want to be able to turn off compute we are not using, but persist its data.

In this lab, we will run a Jupyter service, and we will mount a volume into the container as its working directory. However, instead of storing that volume on the compute instance's *ephemeral* disk, we will store it on a persistent block storage volume that is attached to the compute instance.  

Then we will edit and save a notebook into that directory, and verify that the notebook persists beyond the lifetime of the compute instance.

:::

::: {.cell .markdown}

First, we will create a persistent working directory on the block storage volume, and copy a starter notebook into it:

```bash
# run on node-block
mkdir -p /mnt/block/workspace
cp -r ~/data-persist-chi/block/workspace/* /mnt/block/workspace/
```

Now we can bring up the Jupyter service with `docker run`. This will mount `/mnt/block/workspace` into the container at `/home/jovyan/work`.

```bash
# run on node-block
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -v /mnt/block/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/minimal-notebook:latest
```

To access the Jupyter service, we will need its randomly generated secret token (which secures it from unauthorized access). We'll get this token by running `jupyter server list` inside the `jupyter` container:

```bash
# run on node-block
docker exec jupyter jupyter server list
```

Look for a line like

```
http://localhost:8888/lab?token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Paste this into a browser tab, but in place of `localhost`, substitute the floating IP assigned to your instance, to open the Jupyter notebook interface that is running *on your compute instance*.

In the "work" directory, find and open `demo.ipynb`.

Run the notebook cell, which writes a small file named `persisted.txt` into the working directory. Then, save the notebook.

To verify that the notebook and `persisted.txt` are on the block storage volume, run on the host:

```bash
# run on node-block
ls -l /mnt/block/workspace/
```

:::

::: {.cell .markdown}

Now, let's confirm that data on the block storage volume persists beyond the lifetime of the compute instance. We will now delete the compute instance.

Before you delete the instance (or stop the container), close the browser tab that is connected to the Jupyter workspace running on the compute instance.

The following cells run in the **Chameleon** Jupyter environment (not in the Jupyter environment that you are hosting on your compute instance!)

:::


::: {.cell .code}
```python
# run in Chameleon Jupyter environment
from chi import context, server, lease, storage
import chi, os, time

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
s_old = server.get_server(f"node-block-{username}")
s_old.delete()
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
l = lease.get_lease(f"lease-block-{username}")
s = server.Server(
    f"node-block-{username}", 
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
security_groups = [
  {'name': "allow-ssh", 'port': 22, 'description': "Enable SSH traffic on TCP port 22"},
  {'name': "allow-8888", 'port': 8888, 'description': "Enable TCP port 8888 (used by Jupyter)"}
]

for sg in security_groups:
  s.add_security_group(sg['name'])
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
# volume = storage.get_volume("block-persist-netID")  # Substitute your own net ID
cinder_client = chi.clients.cinder()
volume = [v for v in cinder_client.volumes.list() if v.name == "block-persist-netID"][0]
s.attach_volume(volume.id)
```
:::


::: {.cell .markdown}

You can verify in the Horizon GUI that your block storage volume is now attached to the new compute instance.

:::



::: {.cell .markdown}

Let's confirm that data we put on the block storage volume earlier, is now available on the new compute instance. 


Connect to the new instance over SSH. Mount the block storage volume:


```bash
# run on node-block
sudo mkdir -p /mnt/block
sudo mount /dev/vdb1 /mnt/block
```

and confirm that it is not empty:

```bash
# run on node-block
ls /mnt/block
```


for example, you can see your saved notebook on the persistent volume:


```bash
# run on node-block
ls /mnt/block/workspace
```


Bring up the Jupyter service again:

```bash
# run on node-block
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -v /mnt/block/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/minimal-notebook:latest
```

To access the Jupyter service, get its token again:

```bash
# run on node-block
docker exec jupyter jupyter server list
```

Open the URL in your browser (substituting the floating IP for `localhost`) and confirm that `demo.ipynb` still has the changes you saved earlier.

:::

::: {.cell .markdown}

On the VM, stop the Jupyter container and unmount the volume:

```bash
# run on node-block
docker stop jupyter
sudo umount /mnt/block
```

:::

::: {.cell .markdown}


This Jupyter demo is just an example - the same principle applies to any other platform service we might use. If we used MLFlow, we could similarly put its backing data repositories (for example, Postgresql and an artifact store) on the block storage volume.

:::

::: {.cell .markdown}

### Delete the block storage volume

We do not use the `block-persist-netID` volume again in this lab. To avoid leaving resources allocated, we will detach and delete it now.

In the Chameleon Jupyter environment, detach the volume from the server and delete it. In the following cell, replace **netID** with your own net ID:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# volume = storage.get_volume("block-persist-netID")  # Substitute your own net ID
cinder_client = chi.clients.cinder()
volume = [v for v in cinder_client.volumes.list() if v.name == "block-persist-netID"][0]
s = server.get_server(f"node-block-{username}")

s.detach_volume(volume.id)
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# wait for the volume to become available before deleting
print("volume status:", volume.status)
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
volume.delete()
```
:::
