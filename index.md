

# Persistent storage on Chameleon

You've done really well operationalizing the infrastructure and configuration of the runtime environment at GourmetGram, in [Build an MLOps Pipeline](https://teaching-on-testbeds.github.io/mlops-chi/)! Next, you're going to dig deeper into each stage of your model pipeline. But, there are two major issues you need to address first:

* Applications and services in GourmetGram - including Jupyter services for ML experimentation, model registry services, even application services - save all their data to the *ephemeral* disk of the compute instances that they are running on. When the compute instance ends, the data is lost.
* The training data for your food classifier model is also not persisted anywhere. Right now, you're only training on external data, which you can re-import at any time. But eventually, you will want to train on production data. You need an organized data repository in which to persist training data, and you want to make sure that when training your food classifier model, you will be able to pull data at a high enough rate to keep your powerful GPUs busy during training.

This lab has two parts:

* `block/`: block storage volumes on Chameleon (persistent filesystem for a VM)
* `object/`: object storage on Chameleon (persist training data and other large artifacts)

You can do either part independently.

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.



## Open this experiment on Trovi


When you are ready to begin, you will continue with the next step! To begin this step, open this experiment on Trovi:

* Use this link: [Persistent storage on Chameleon](https://chameleoncloud.org/experiment/share/a1c68238-81f8-498d-8323-9d6c46cb0a78) on Trovi
* Then, click "Launch on Chameleon". This will start a new Jupyter server for you, with the experiment materials already in it.

You will see a `block/` and an `object/` directory inside `data-persist-chi`.

Open one of:

* `block/0_intro.ipynb`
* `object/0_intro.ipynb`

and continue there.



# Block storage on Chameleon

This part of the lab focuses on block storage: how to attach a persistent block volume to a VM and use it as a durable filesystem (for example, to persist a Jupyter workspace across VM deletion and recreation).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site.



## Experiment resources 

For this experiment, we will provision 

* one block storage volume on KVM@TACC
* one virtual machine on KVM@TACC, with a floating IP, to practice using the persistent storage



You will see several notebooks inside the `data-persist-chi/block` directory. Open `0_intro.ipynb` and continue there.





## Launch and set up a VM instance- with python-chi

We will use the `python-chi` Python API to Chameleon to provision a VM instance. 

We will execute the cells in this notebook inside the Chameleon Jupyter environment.

Run the following cell, and make sure the correct project is selected. 


```python
# run in Chameleon Jupyter environment
from chi import server, context, lease, network
import chi, os, time, datetime

context.version = "1.0" 
context.choose_project()
context.choose_site(default="KVM@TACC")
username = os.getenv('USER') # all exp resources will have this prefix
```


We will bring up a `m1.medium` flavor server with the `CC-Ubuntu24.04` disk image. 

> **Note**: the following cell brings up a server only if you don't already have one with the same name! (Regardless of its error state.) If you have a server in ERROR state already, delete it first in the Horizon GUI before you run this cell.



First we will reserve the VM instance for 4 hours, starting now:



```python
# run in Chameleon Jupyter environment
l = lease.Lease(f"lease-block-{username}", duration=datetime.timedelta(hours=4))
l.add_flavor_reservation(id=chi.server.get_flavor_id("m1.medium"), amount=1)
l.submit(idempotent=True)
```


```python
# run in Chameleon Jupyter environment
l.show()
```



Now we can launch an instance using that lease:



```python
# run in Chameleon Jupyter environment
s = server.Server(
    f"node-block-{username}", 
    image_name="CC-Ubuntu24.04",
    flavor_name=l.get_reserved_flavors()[0].name
)
s.submit(idempotent=True)
```



Then, we'll associate a floating IP with the instance:


```python
# run in Chameleon Jupyter environment
s.associate_floating_ip()
```


In the output below, make a note of the floating IP that has been assigned to your instance (in the "Addresses" row).


```python
# run in Chameleon Jupyter environment
s.refresh()
s.show(type="widget")
```


By default, all connections to VM resources are blocked, as a security measure.  We need to attach one or more "security groups" to our VM resource, to permit access over the Internet to specified ports.

The following security groups will be created (if they do not already exist in our project) and then added to our server:



```python
# run in Chameleon Jupyter environment
security_groups = [
  {'name': "allow-ssh", 'port': 22, 'description': "Enable SSH traffic on TCP port 22"},
  {'name': "allow-8888", 'port': 8888, 'description': "Enable TCP port 8888 (used by Jupyter)"}
]
```


```python
# run in Chameleon Jupyter environment
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
# run in Chameleon Jupyter environment
s.refresh()
s.check_connectivity()
```




### Retrieve code and notebooks on the instance

Now, we can use `python-chi` to execute commands on the instance, to set it up. We'll start by retrieving the code and other materials on the instance.


```python
# run in Chameleon Jupyter environment
s.execute("git clone https://github.com/teaching-on-testbeds/data-persist-chi")
```



### Set up Docker

Here, we will set up the container framework.


```python
# run in Chameleon Jupyter environment
s.execute("curl -sSL https://get.docker.com/ | sudo sh")
s.execute("sudo groupadd -f docker; sudo usermod -aG docker $USER")
```



## Open an SSH session

Finally, open an SSH sesson on the server. From your local terminal, run

```
ssh -i ~/.ssh/id_rsa_chameleon cc@A.B.C.D
```

where

* in place of `~/.ssh/id_rsa_chameleon`, substitute the path to your own key that you had uploaded to KVM@TACC
* in place of `A.B.C.D`, use the floating IP address you just associated to your instance.




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




### Create Docker volumes on persistent storage

Now that we have a block storage volume attached to our VM instance, let's see how persistent storage can be useful.

For example, suppose that as part of a project we train some ML models and use MLFlow to keep track of models and the training runs that produced them. We are not working on our project *all* the time, so we should only bring up compute instances when we are actively working. But if we don't let MLFlow persist its data to some form of storage that lives beyond the lifetime of the compute instance, we would lose past experiment logs and models every time we bring VMs down.

Or, suppose we have a Jupyter service that our engineers use to experiment with model development. Some of these experiments will turn into operationalized model training pipelines, but not all; so we want to give our Jupyter users a persistent filesystem. If we mount a directory inside the Jupyter container (for example, using a Docker volume or a bind mount), then the data stored inside this mount point will persist as long as the backing storage persists.

But, what happens if the compute instance does not stay alive? This is a real concern, not a hypothetical:

* In a production system, we don't want to lose data if something happens to a compute instance. In fact, good DevOps practices suggest we should design our system so it is resilient to a compute instance acting up - we should be able to swap it out for another compute instance.
* When using a cloud environment like Chameleon for projects and development, we aren't going to run compute all the time just to keep data alive! Data is relatively cheap in a cloud, compute costs a lot more. We want to be able to turn off compute we are not using, but persist its data.

In this lab, we will run a Jupyter service, and we will mount a volume into the container as its working directory. However, instead of storing that volume on the compute instance's *ephemeral* disk, we will store it on a persistent block storage volume that is attached to the compute instance.  

Then we will edit and save a notebook into that directory, and verify that the notebook persists beyond the lifetime of the compute instance.



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



Now, let's confirm that data on the block storage volume persists beyond the lifetime of the compute instance. We will now delete the compute instance.

Before you delete the instance (or stop the container), close the browser tab that is connected to the Jupyter workspace running on the compute instance.

The following cells run in the **Chameleon** Jupyter environment (not in the Jupyter environment that you are hosting on your compute instance!)



```python
# run in Chameleon Jupyter environment
from chi import context, server, lease, storage
import chi, os, time

context.version = "1.0" 
context.choose_project()  # Select the correct project
context.choose_site(default="KVM@TACC")
username = os.getenv('USER') # exp resources will have this suffix
```


```python
# run in Chameleon Jupyter environment
# delete the old server instance!
s_old = server.get_server(f"node-block-{username}")
s_old.delete()
```

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

```python
# run in Chameleon Jupyter environment
s.associate_floating_ip()
```


```python
# run in Chameleon Jupyter environment
security_groups = [
  {'name': "allow-ssh", 'port': 22, 'description': "Enable SSH traffic on TCP port 22"},
  {'name': "allow-8888", 'port': 8888, 'description': "Enable TCP port 8888 (used by Jupyter)"}
]

for sg in security_groups:
  s.add_security_group(sg['name'])
```

```python
# run in Chameleon Jupyter environment
s.refresh()
s.check_connectivity()
```



```python
# run in Chameleon Jupyter environment
s.refresh()
s.show(type="widget")
```



```python
# run in Chameleon Jupyter environment
s.execute("git clone https://github.com/teaching-on-testbeds/data-persist-chi")
```


```python
# run in Chameleon Jupyter environment
s.execute("curl -sSL https://get.docker.com/ | sudo sh")
s.execute("sudo groupadd -f docker; sudo usermod -aG docker $USER")
```


This cell will attach the block storage volume named "block-persist-**netID**" to your compute instance - edit it to substitute your *own* net ID:


```python
# run in Chameleon Jupyter environment
# volume = storage.get_volume("block-persist-netID")  # Substitute your own net ID
cinder_client = chi.clients.cinder()
volume = [v for v in cinder_client.volumes.list() if v.name == "block-persist-netID"][0]
s.attach_volume(volume.id)
```



You can verify in the Horizon GUI that your block storage volume is now attached to the new compute instance.





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



On the VM, stop the Jupyter container and unmount the volume:

```bash
# run on node-block
docker stop jupyter
sudo umount /mnt/block
```




This Jupyter demo is just an example - the same principle applies to any other platform service we might use. If we used MLFlow, we could similarly put its backing data repositories (for example, Postgresql and an artifact store) on the block storage volume.



### Delete the block storage volume

We do not use the `block-persist-netID` volume again in this lab. To avoid leaving resources allocated, we will detach and delete it now.

In the Chameleon Jupyter environment, detach the volume from the server and delete it. In the following cell, replace **netID** with your own net ID:


```python
# run in Chameleon Jupyter environment
# volume = storage.get_volume("block-persist-netID")  # Substitute your own net ID
cinder_client = chi.clients.cinder()
volume = [v for v in cinder_client.volumes.list() if v.name == "block-persist-netID"][0]
s = server.get_server(f"node-block-{username}")
s.detach_volume(volume.id)
```

```python
# run in Chameleon Jupyter environment
# wait for the volume to become available before deleting
volume = cinder_client.volumes.get(volume.id)
print("volume status:", volume.status)
```

```python
# run in Chameleon Jupyter environment
volume.delete()
```


## Reference: creating and managing block volumes with Cinder (Python)

We created our block storage volume using the Horizon GUI. However, it is also useful to learn how to create and manage block storage volumes directly in Python, especially if we are automating infrastructure setup using a notebook.

Some block storage functionality is not available using the `python-chi` library managed by Chameleon. In OpenStack, the Cinder service provides block storage volumes. We can access the already-configured (authenticated) Cinder client from `python-chi`, then use that directly for anything that is not supported by `python-chi`.


```python
# run in Chameleon Jupyter environment
from chi import context, lease, server
import chi, os, time

context.version = "1.0"
context.choose_project()
context.choose_site(default="KVM@TACC")

username = os.getenv('USER')
```


```python
# run in Chameleon Jupyter environment
# get the Cinder Python client configured by python-chi
cinder_client = chi.clients.cinder()
```

```python
# run in Chameleon Jupyter environment
# list current volumes
cinder_client.volumes.list()
```


We can use the Cinder client to create a new block storage volume:


```python
# run in Chameleon Jupyter environment
# create a volume, specifying name and size in GiB
volume = cinder_client.volumes.create(name=f"block-persist-python-{username}", size=2)
volume._info
```


We can attach the volume to a compute instance:


```python
# run in Chameleon Jupyter environment
# server_id = server.get_server(f"node-block-{username}").id
server_id = chi.nova().servers.find(name=f"node-block-{username}").id
volume_manager = chi.nova().volumes
volume_manager.create_server_volume(server_id=server_id, volume_id=volume.id)

```


Or, detach the volume from a compute instance:


```python
# run in Chameleon Jupyter environment
volume_manager.delete_server_volume(server_id=server_id, volume_id=volume.id)
```


Or, to completely delete a volume (loses all the data!):


```python
# run in Chameleon Jupyter environment
cinder_client.volumes.delete(volume=volume)
```


At this point, we are done with the server we have been using, so we will delete it:


```python
# run in Chameleon Jupyter environment
# s = server.get_server(f"node-block-{username}")
s = chi.nova().servers.find(name=f"node-block-{username}")
s.delete()
```


Note: This pattern of creating a volume, attaching it to an instance, doing some work on it, and then deleting it again, is especially useful when we need a very large ephemeral staging area for an ETL job.  




## Reference: booting a compute instance from a volume (create from image)

Sometimes we need more disk space than the default root disk that comes with a compute instance. This is common for GPU instances: large model checkpoints, cached datasets, container images with machine learning frameworks, and intermediate artifacts can quickly consume tens or hundreds of GiB. 

One way to address this is to create a bootable Cinder volume from an image, with a size we choose, and then boot the server from that volume. We also set whether the boot volume should persist after the server is deleted:

* If `delete_on_termination=True`, the boot volume is deleted when the server is deleted. This behaves like ephemeral instance storage, but larger.
* If `delete_on_termination=False`, the boot volume remains after the server is deleted. We can later boot a new server from the same volume (but we must remember to delete it when finished).




First, look up the image ID for the image we want to boot (for example, `CC-Ubuntu24.04`).


```python
# run in Chameleon Jupyter environment
os_conn = chi.clients.connection()

# find an image by name
images = list(os_conn.image.images(name="CC-Ubuntu24.04"))
image_id = images[0].id
image_id
```


Now create a bootable volume from that image, specifying a size in GiB.


```python
# run in Chameleon Jupyter environment
boot_vol_size_gib = 60
boot_vol = cinder_client.volumes.create(
    name=f"boot-vol-{username}",
    size=boot_vol_size_gib,
    imageRef=image_id,
)
boot_vol._info
```


Wait for the volume to become available:


```python
# run in Chameleon Jupyter environment
boot_vol = cinder_client.volumes.get(boot_vol.id)
print("boot volume status:", boot_vol.status)
```



When we boot from volume, we create the server with a block device mapping that uses the volume as the root disk.


```python
# run in Chameleon Jupyter environment
# reuse the lease created earlier
l = lease.get_lease(f"lease-block-{username}")
```


```python
# run in Chameleon Jupyter environment
delete_on_termination = True

bdm = [{
    "boot_index": 0,
    "uuid": boot_vol.id,
    "source_type": "volume",
    "destination_type": "volume",
    "delete_on_termination": delete_on_termination,
}]

server_from_vol = os_conn.compute.create_server(
    name=f"node-bootable-{username}",
    flavor_id=server.get_flavor_id(l.get_reserved_flavors()[0].name),
    block_device_mapping_v2=bdm,
    networks=[{"uuid": os_conn.network.find_network("sharednet1").id}],
)

server_from_vol.id
```

```python
# run in Chameleon Jupyter environment
# wait for the server to become ACTIVE
server_from_vol = os_conn.compute.wait_for_server(server_from_vol)
server_from_vol.status
```

```python
# run in Chameleon Jupyter environment
# allow inbound SSH (TCP/22)
os_conn.compute.add_security_group_to_server(server_from_vol, "allow-ssh")
```


Next, associate a floating IP so that we can SSH to the instance:


```python
# run in Chameleon Jupyter environment
# python-chi's server wrapper does not work reliably for boot-from-volume instances,
# so we use the OpenStack SDK connection to allocate and attach a floating IP.
server = os_conn.compute.find_server(f"node-bootable-{username}")
sharednet = os_conn.network.find_network("sharednet1")
port = next(p for p in os_conn.network.ports(device_id=server.id) if p.network_id == sharednet.id)
```

```python
floating_net = os_conn.network.find_network("public")
fip = os_conn.network.create_ip(floating_network_id=floating_net.id)
fip.floating_ip_address
```

```python
os_conn.network.update_ip(fip, port_id=port.id)
print("floating ip:", fip.floating_ip_address)
```



Make a note of the floating IP in the output above. Then, from a local terminal, SSH to the instance:

```
ssh -i ~/.ssh/id_rsa_chameleon cc@A.B.C.D
```

Substitute your key path for `~/.ssh/id_rsa_chameleon` and your floating IP for `A.B.C.D`.

On the instance, run:

```bash
df -h /
```

Verify that the size of the root filesystem (mounted at `/`) reflects the boot volume size you requested.



When you are finished with this boot-from-volume instance, delete it. Since we set `delete_on_termination=True`, deleting the server will also delete the boot volume.


```python
# run in Chameleon Jupyter environment
server_from_vol = os_conn.compute.find_server(f"node-bootable-{username}")
os_conn.compute.delete_server(server_from_vol, ignore_missing=True)
```


**Comparing boot-from-volume vs attaching a non-bootable data volume** - 

When we boot-from-volume:

* Pros: our root disk can be as large as we need; everything is already on the large disk without extra mount/partition steps.
* Cons: with a *persistent* boot volume, we tend to accumulate configuration drift (we are carrying the OS state forward). It is also less flexible: a boot volume is tied to a specific node role, so it is harder to repurpose than a separate data volume. And, the persistent volume must be larger than a non-bootable volume for just data would be (because it is also carrying the entire OS, software runtime, and ephemeral artifacts that we don't care to save) which makes it more expensive.

When we attach a non-bootable data volume (what we did in the previous notebook):

* Pros: keep the OS lifecycle separate from data; detach/re-attach the data volume between servers; simpler to keep instances "cattle" and data "pet".
* Cons: we must format/mount the volume and ensure services use it.

In practice, we will use non-bootable data volumes for durable service state, and use boot-from-volume when we specifically need a large ephemeral root disk. We will try to avoid *persistent* bootable data volumes, for the reasons described above.



# Object storage on Chameleon

This part of the lab focuses on object storage: persisting training data in S3-compatible object storage and benchmarking training input pipelines (local ImageFolder, ImageFolder over an rclone mount, one-object-per-sample reads, and sharded streaming).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.



## Experiment materials

* The ETL jobs in this experiment are executed using Docker compose. You can find those configurations at [object/docker](https://github.com/teaching-on-testbeds/data-persist-chi/tree/main/object/docker)
* We will benchmark different training data input strategies using the Python notebooks at [object/workspace](https://github.com/teaching-on-testbeds/data-persist-chi/tree/main/object/workspace)



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


We will bring up a `m1.xlarge` flavor server with the `CC-Ubuntu24.04` disk image. 

> **Note**: the following cell brings up a server only if you don't already have one with the same name! (Regardless of its error state.) If you have a server in ERROR state already, delete it first in the Horizon GUI before you run this cell.



First we will reserve the VM instance for 4 hours, starting now:



```python
l = lease.Lease(f"lease-object-{username}", duration=datetime.timedelta(hours=4))
l.add_flavor_reservation(id=chi.server.get_flavor_id("m1.xlarge"), amount=1)
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


and we also install some software on the host that we will use to monitor network usage, when we are streaming to/from object store.


```python
s.execute("sudo apt-get update; sudo apt-get -y install nload")
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

In these stages, we are downloading the raw data into a staging area, then transforming it into a layout that is convenient for training input. We are not loading the data to its permanent home yet. In later stages of this lab, we will keep this staging area around (as a Docker volume), reuse the organized data, and then load it into object storage or convert it into other formats.

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
docker compose -f ~/data-persist-chi/object/docker/local.yaml run --rm extract-data
```

Run the transform stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/local.yaml run --rm transform-data
```



### Run Jupyter with the dataset mounted

Now run a Jupyter container and mount:

* the Food11 data volume at `/mnt` (read-only). The dataset will be available at `/mnt/Food-11` inside the container.
* the lab notebooks at `/home/jovyan/work`

Run:

```bash
# run on node-object
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e FOOD11_DATA_DIR=/mnt/Food-11 \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  -v food11_local_baseline:/mnt:ro \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest
```

To access the Jupyter service, get its token:

```bash
# run on node-object
docker exec jupyter jupyter server list
```

Open the printed URL in your browser, substituting the floating IP for `localhost`.

In the Jupyter UI, open `imagefolder_local.ipynb`. In this notebook, the Dataset is `torchvision.datasets.ImageFolder`, pointing at a local directory (`/mnt/Food-11/<split>`). The DataLoader reads individual image files from the mounted volume, decodes them (PIL), applies a resize/crop/normalize transform, and batches tensors.

Run the notebook. When the benchmark finishes, it will write a JSON results file under `results/` and also print its results. Download the JSON file from the `results/` folder in the Jupyter file browser. You can interpret the throughput metrics as follows:

* `imgs/s` (images per second) - higher is better. This is the main steady-state metric for how quickly the input pipeline can produce training examples.
* `batches/s` (batches per second) - higher is better. This is the same idea as `imgs/s`, but expressed in batches.
* `avg_batch_s` (average seconds per batch) - lower is better. This is approximately the inverse of `batches/s`.

In later parts of the lab, we will compare these same metrics across different storage and dataset formats.

When you are done with the local baseline, close the browser tab with the Jupyter service running on the instance, and then stop the container:

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

Important: treat the secret like a password. Save it somewhere safe. If you share screenshots or publish notebooks that include a credential, clear the cell output first.



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
conn = chi.clients.connection()

project_id = conn.current_project_id
identity_ep = conn.session.get_endpoint(service_type="identity", interface="public")
url = f"{identity_ep}/v3/users/{conn.current_user_id}/credentials/OS-EC2"

resp = conn.session.post(url, json={"tenant_id": project_id})
resp.raise_for_status()
ec2 = resp.json()["credential"]

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
  --dir-cache-time 10s \
  --daemon
```



## Rclone baseline: ImageFolder on an rclone mount

In this part, we will:

1. Run an ETL pipeline to upload Food11 to the S3 bucket.
2. Use the rclone mount from the previous step.
3. Pass the mount into a Jupyter container.
4. Run the ImageFolder benchmark, but this time with rclone mount that is actually a remote S3 bucket, not a local disk.



### ETL pipeline (load to S3)

The pipeline stages are defined in `~/data-persist-chi/object/docker/load.yaml`.

This pipeline re-uses the extract and first transform step from the local baseline: we kept the organized Food11 directory tree in a Docker volume (`food11_local_baseline`). This stage mounts that staging volume read-only and loads its contents into S3.

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

Run the load stage:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/load.yaml run --rm load-data
```

After the load step finishes, open the Horizon GUI for CHI@TACC and navigate to "Object Store" > "Containers". Click on your container (`object-chi-netID`) and you should see a `Food-11/` prefix. Inside it, expect `training/`, `validation/`, and `evaluation/`, each with `class_XX/` subdirectories and JPEG images. Take a screenshot for later reference.

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

In the Jupyter UI, open `imagefolder_rclone_mount.ipynb`. In this notebook, the Dataset is `torchvision.datasets.ImageFolder`, but the filesystem backing it is an rclone FUSE mount of the S3 bucket. The DataLoader still does ordinary file opens and reads, but every read is translated into S3 GET requests under the hood.

Before you start the benchmark in the Jupyter UI, open a separate SSH terminal on the node (not inside the Jupyter container) and run:

```bash
# run on node-object
sudo nload ens3
```

to watch the network traffic while the DataLoader is reading.

In particular, note the current (`Curr`) incoming data rate shown to the side of the ASCII plot.

Run the benchmark, and take a screenshot of the `nload` output showing inbound network traffic. When the benchmark is finished, it will print the results and write a JSON results file under `results/`. Download the JSON file from the `results/` folder in the Jupyter file browser.

Use Ctrl + C to stop the running `nload` process.

Close the browser tab for the Jupyter server on the instance, and stop the container when you are done:

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


We will run a benchmark notebook that uses `fsspec` to open remote objects and `PIL` to decode images. In this notebook, the Dataset is a small custom `torch.utils.data.Dataset` that first lists objects once to build an index (not timed), then loads each sample by doing an S3 GET for that one image via `fsspec`, decoding with PIL, and applying the usual resize/crop/normalize transform. The DataLoader batches those decoded tensors.

The DataLoader will load each sample by making a separate S3 request for that image. This pattern is simple, but it often performs poorly at scale because it has high per-sample overhead.

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

which we have done in the previous stage, so there is no ETL step here.



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

Before you start the benchmark in the Jupyter UI, open a separate SSH terminal on the node (not inside the Jupyter container) and run:

```bash
# run on node-object
sudo nload ens3
```

to monitor network traffic. In particular, note the current (`Curr`) incoming data rate shown to the side of the ASCII plot. Take a screenshot while the benchmark is running.

In the Jupyter UI, open and run `remote_one_sample.ipynb`. When the benchmark finishes, it will print results and write a JSON results file under `results/`. Download the JSON file from the `results/` folder in the Jupyter file browser.

Close the browser tab for the Jupyter server running inside the instance, and stop the container when you are done:

```bash
# run on node-object
docker stop jupyter
```



## Sharded baseline: stream tar shards from S3

In this part, we will create larger shard objects (tar files) and stream from those shards during training input.

In this benchmark notebook, the Dataset is an `IterableDataset` that assigns shard files across DataLoader workers, opens each shard via `fsspec`, streams the tar entries, and yields `(image_tensor, label)` pairs. The DataLoader batches those streamed samples.

Compared to reading one S3 object per sample, sharding reduces per-sample overhead by reading many samples from each shard.



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

After the load step finishes, open the Horizon GUI for CHI@TACC and navigate to "Object Store" > "Containers". Click on your container (`object-chi-netID`) and you should see a `Food-11-webdataset/` prefix. Inside it, expect `training/`, `validation/`, and `evaluation/` directories with multiple `shard-*.tar` objects. Take a screenshot for later reference.

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



## Optimized baseline: LitData streaming over S3

In this part, we will write the dataset in a [LitData](https://github.com/Lightning-AI/litdata/) optimized format and then stream it from S3.

In this benchmark notebook, the Dataset is `litdata.StreamingDataset`, pointing at `s3://<bucket>/<prefix>/<split>`. It streams data into a local cache directory inside the container (`./litdata_cache` by default), and the `StreamingDataLoader` iterates it with worker processes. We decode each sample to a tensor in the collate function and then measure steady-state throughput.

This approach combines sharding with some other optimizations + a local cache.



### ETL pipeline (optimize + load)

The pipeline stages are defined in `~/data-persist-chi/object/docker/lit.yaml`.

This pipeline re-uses the extract and first transform step from the local baseline: we kept the organized Food11 directory tree in a Docker volume (`food11_local_baseline`). This stage reads images from that staging volume (read-only), writes LitData output to a separate output volume, and then loads that output into S3.

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

Build the optimized dataset:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run --rm optimize-litdata
```

Load the optimized dataset to S3:

```bash
# run on node-object
docker compose -f ~/data-persist-chi/object/docker/lit.yaml run --rm load-litdata
```

After the load step finishes, open the Horizon GUI for CHI@TACC and navigate to "Object Store" > "Containers". Click on your container (`object-chi-netID`) and you should see a `Food-11-litdata/` prefix. Inside it, expect `training/`, `validation/`, and `evaluation/` directories containing LitData metadata and chunk files. Take a screenshot for later reference.

To free disk space after you finish the load step, remove the local LitData output volume:

```bash
# run on node-object
docker volume rm food11-litdata_lit_out
```

If Docker says the volume is in use, remove the stopped container(s) that still reference it, then try again:

```bash
# run on node-object
docker ps -a --filter volume=food11-litdata_lit_out --format "{{.ID}}" | xargs -r docker rm -f
docker volume rm food11-litdata_lit_out
```



### Run Jupyter with S3 credentials as environment variables

To stream from S3 inside the container, we pass credentials via environment variables in the `docker run` command.

In the following command:

* replace **ACCESS_KEY_ID** with your EC2 Access
* replace **SECRET_ACCESS_KEY** with your EC2 Secret
* replace **netID** in the bucket name

This step installs `litdata` in the Jupyter container before starting the notebook server.

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
  -e FOOD11_SPLIT=training \
  -v ${HOME}/data-persist-chi/object/workspace:/home/jovyan/work \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest \
  bash -lc "pip -q install litdata==0.2.60 && start-notebook.py"
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
    
to monitor network traffic. In particular, note the current (`Curr`) incoming data rate shown to the side of the ASCII plot. Take a screenshot while the benchmark is running.
  
In the Jupyter UI, open and run `litdata_streaming.ipynb`. When the benchmark finishes, it will print the results and write a JSON results file under `results/`. Download the JSON file from the `results/` folder in the Jupyter file browser.

Note that it will also create a `litdata_cache` directory in the workspace. It will keep chunks there (on the local disk) so they don't *always* have to be streamed from the remote object storage.

Run the benchmark notebook *again* and note the results; it can be substantially faster on this run, since some of the data is already cached. Take a screenshot. You may notice that less data is transferred over the network on the second run. We can tune `max_cache_size` and `max_pre_download` in the `StreamingDataset` to manage the tradeoff between network and local disk use.

Close the browser tab and stop the container when you are done:

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
