
::: {.cell .markdown}

## Reference: creating and managing block volumes with Cinder (Python)

We created our block storage volume using the Horizon GUI. However, it is also useful to learn how to create and manage block storage volumes directly in Python, especially if we are automating infrastructure setup using a notebook.

Some block storage functionality is not available using the `python-chi` library managed by Chameleon. In OpenStack, the Cinder service provides block storage volumes. We can access the already-configured (authenticated) Cinder client from `python-chi`, then use that directly for anything that is not supported by `python-chi`.

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
from chi import context, lease, server
import chi, os, time

context.version = "1.0"
context.choose_project()
context.choose_site(default="KVM@TACC")

username = os.getenv('USER')
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# reuse the lease created earlier
l = lease.get_lease(f"lease-block-{username}")
```
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

We can use the Cinder client to create a new block storage volume:

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
# server_id = server.get_server(f"node-block-{username}").id
server_id = chi.nova().servers.find(name=f"node-block-{username}").id
volume_manager = chi.nova().volumes
volume_manager.create_server_volume(server_id=server_id, volume_id=volume.id)

```
:::

::: {.cell .markdown}

Or, detach the volume from a compute instance:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
volume_manager.delete_server_volume(server_id=server_id, volume_id=volume.id)
```
:::

::: {.cell .markdown}

Or, to completely delete a volume (loses all the data!):

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
cinder_client.volumes.delete(volume=volume)
```
:::

::: {.cell .markdown}

At this point, we are done with the server we have been using, so we will delete it:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# s = server.get_server(f"node-block-{username}")
s = chi.nova().servers.find(name=f"node-block-{username}")
s.delete()
```
:::

::: {.cell .markdown}

Note: This pattern of creating a volume, attaching it to an instance, doing some work on it, and then deleting it again, is especially useful when we need a very large ephemeral staging area for an ETL job.  

:::


::: {.cell .markdown}

## Reference: booting a compute instance from a volume (create from image)

Sometimes we need more disk space than the default root disk that comes with a compute instance. This is common for GPU instances: large model checkpoints, cached datasets, container images with machine learning frameworks, and intermediate artifacts can quickly consume tens or hundreds of GiB. 

One way to address this is to create a bootable Cinder volume from an image, with a size we choose, and then boot the server from that volume. We also set whether the boot volume should persist after the server is deleted:

* If `delete_on_termination=True`, the boot volume is deleted when the server is deleted. This behaves like ephemeral instance storage, but larger.
* If `delete_on_termination=False`, the boot volume remains after the server is deleted. We can later boot a new server from the same volume (but we must remember to delete it when finished).

:::

::: {.cell .markdown}


First, look up the image ID for the image we want to boot (for example, `CC-Ubuntu24.04`).

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
os_conn = chi.clients.connection()

# find an image by name
images = list(os_conn.image.images(name="CC-Ubuntu24.04"))
image_id = images[0].id
image_id
```
:::

::: {.cell .markdown}

Now create a bootable volume from that image, specifying a size in GiB.

:::

::: {.cell .code}
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
:::

::: {.cell .markdown}

Wait for the volume to become available:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
boot_vol = cinder_client.volumes.get(boot_vol.id)
print("boot volume status:", boot_vol.status)
```
:::

::: {.cell .markdown}


When we boot from volume, we create the server with a block device mapping that uses the volume as the root disk.

:::

::: {.cell .code}
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
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# wait for the server to become ACTIVE
server_from_vol = os_conn.compute.wait_for_server(server_from_vol)
server_from_vol.status
```
:::

::: {.cell .markdown}

Next, associate a floating IP so that we can SSH to the instance:

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
# python-chi's server wrapper does not work reliably for boot-from-volume instances,
# so we use the OpenStack SDK connection to allocate and attach a floating IP.
server = os_conn.compute.find_server(f"node-bootable-{username}")
sharednet = os_conn.network.find_network("sharednet1")
port = next(p for p in os_conn.network.ports(device_id=server.id) if p.network_id == sharednet.id)
```
:::

::: {.cell .code}
```python
floating_net = os_conn.network.find_network("public")
fip = os_conn.network.create_ip(floating_network_id=floating_net.id)
fip.floating_ip_address
```
:::

::: {.cell .code}
```python
os_conn.network.update_ip(fip, port_id=port.id)
print("floating ip:", fip.floating_ip_address)
```
:::


::: {.cell .markdown}

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

:::

::: {.cell .markdown}

When you are finished with this boot-from-volume instance, delete it. Since we set `delete_on_termination=True`, deleting the server will also delete the boot volume.

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
server_from_vol = os_conn.compute.find_server(f"node-bootable-{username}")
os_conn.compute.delete_server(server_from_vol, ignore_missing=True)
```
:::

::: {.cell .markdown}

**Comparing boot-from-volume vs attaching a non-bootable data volume** - 

When we boot-from-volume:

* Pros: our root disk can be as large as we need; everything is already on the large disk without extra mount/partition steps.
* Cons: with a *persistent* boot volume, we tend to accumulate configuration drift (we are carrying the OS state forward). It is also less flexible: a boot volume is tied to a specific node role, so it is harder to repurpose than a separate data volume. And, the persistent volume must be larger than a non-bootable volume for just data would be (because it is also carrying the entire OS, software runtime, and ephemeral artifacts that we don't care to save) which makes it more expensive.

When we attach a non-bootable data volume (what we did in the previous notebook):

* Pros: keep the OS lifecycle separate from data; detach/re-attach the data volume between servers; simpler to keep instances "cattle" and data "pet".
* Cons: we must format/mount the volume and ensure services use it.

In practice, we will use non-bootable data volumes for durable service state, and use boot-from-volume when we specifically need a large ephemeral root disk. We will try to avoid *persistent* bootable data volumes, for the reasons described above.

:::
