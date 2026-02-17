
::: {.cell .markdown}

## Mount the bucket with rclone (S3)

In this part, we will mount the S3 bucket as a local filesystem using `rclone mount`.

:::

::: {.cell .markdown}

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

:::

::: {.cell .markdown}

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

:::

::: {.cell .markdown}

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

:::
