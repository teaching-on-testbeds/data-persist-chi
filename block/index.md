

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
l = lease.Lease(f"lease-block-{username}", duration=datetime.timedelta(hours=4))
l.add_flavor_reservation(id=chi.server.get_flavor_id("m1.medium"), amount=1)
l.submit(idempotent=True)
```


```python
l.show()
```



Now we can launch an instance using that lease:



```python
s = server.Server(
    f"node-block-{username}", 
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
# reuse the lease created earlier
l = lease.get_lease(f"lease-block-{username}")
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

Verify that the root filesystem size reflects the boot volume size you requested.



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



<hr>

<small>Questions about this material? Contact Fraida Fund</small>

<hr>

<small>This material is based upon work supported by the National Science Foundation under Grant No. 2230079.</small>

<small>Any opinions, findings, and conclusions or recommendations expressed in this material are those of the author(s) and do not necessarily reflect the views of the National Science Foundation.</small>
