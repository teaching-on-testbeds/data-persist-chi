
::: {.cell .markdown}

## Using object storage

Until now, in any experiment we have run on Chameleon, we had to re-download large training sets each time we launched a new compute instance to work on that data. For example, in our "GourmetGram" use case, we had to re-download the Food11 dataset each time we brought up a compute instance to train or evaluate a model on that data.

For a longer-term project, we will want to persist large data sets beyond the lifetime of the compute instance. That way, we can download a very large data set *once* and then re-use it many times with different compute instances, without having to keep a compute instance "alive" all the time, or re-download the data. We will use the object storage service in Chameleon to enable this.

Of the various types of storage available in a cloud computing environment (object, block, file), object storage is the most appropriate for large training data sets. Object storage is cheap, and optimized for storing and retrieving large volumes of data, where the data is not modified frequently. (In object storage, there is no in-place modification of objects - only replacement - so it is not the best solution for files that are frequently modified.)

After you run this experiment, you will know how to:

* create an object store container at CHI@TACC
* copy objects to it,
* and mount it as a filesystem in a compute instance.

The object storage service is available at CHI@TACC or CHI@UC. In this tutorial, we will use CHI@TACC. The CHI@TACC object store can be accessed from a KVM@TACC VM instance.

:::

::: {.cell .markdown}

### Object storage using the Horizon GUI

First, let's try creating an object storage container from the OpenStack Horizon GUI. 

Open the GUI for CHI@TACC:

* from the [Chameleon website](https://chameleoncloud.org/hardware/)
* click "Experiment" > "CHI@TACC"
* log in if prompted to do so
* check the project drop-down menu near the top left (which shows e.g. "CHI-XXXXXX"), and make sure the correct project is selected.

In the menu sidebar on the left side, click on "Object Store" > "Containers" and then, "Create Container". You will be prompted to set up your container step by step using a graphical "wizard".

* Specify the name as <code>object-persist-<b>netID</b></code> where in place of <code><b>netID</b></code> you substitute your own net ID (e.g. `ff524` in my case). 
* Leave other settings at their defaults, and click "Submit".

:::

::: {.cell .markdown}

### Use `rclone` and authenticate to object store from a compute instance

We will want to connect to this object store from the compute instance we configured earlier, and copy some data to it!

For *write* access to the object store from the compute instance, we will need to authenticate with valid OpenStack credentials. To support this, we will create an *application credential*, which consists of an ID and a secret that allows a script or application to authenticate to the service. 

An application credential is a good way for something like a data pipeline to authenticate, since it can be used non-interactively, and can be revoked easily in case it is compromised without affecting the entire user account.

In the menu sidebar on the left side of the Horizon GUI, click "Identity" > "Application Credentials". Then, click "Create Application Credential".

* In the "Name", field, use "data-persist". 
* Set the "Expiration" date to the end date of the current semester. (Note that this will be in UTC time, not your local time zone.) This ensures that if your credential is leaked (e.g. you accidentially push it to a public Github repository), the damage is mitigated.
* Click "Create Application Credential".
* Copy the "ID" and "Secret" displayed in the dialog, and save them in a safe place. You will not be able to view the secret again from the Horizon GUI. Then, click "Download openrc file" to have another copy of the secret.

Now that we have an application credential, we can use it to allow an application to authenticate to the Chameleon object store service. There are several applications and utilities for working with OpenStack's Swift object store service; we will use one called [`rclone`](https://github.com/rclone/rclone).


On the compute instance, install `rclone`:


```bash
# run on node-persist
curl https://rclone.org/install.sh | sudo bash
```

We also need to modify the configuration file for FUSE (**F**ilesystem in **USE**rspace: the interface that allows user space applications to mount virtual filesystems), so that object store containers mounted by our user will be availabe to others, including Docker containers:

```bash
# run on node-persist
# this line makes sure user_allow_other is un-commented in /etc/fuse.conf
sudo sed -i '/^#user_allow_other/s/^#//' /etc/fuse.conf
```

Next, create a configuration file for `rclone` with the ID and secret from the application credential you just generated:

```bash
# run on node-persist
mkdir -p ~/.config/rclone
nano  ~/.config/rclone/rclone.conf
```

Paste the following into the config file, but substitute your own application credential ID and secret. 

You will also need to substitute your own user ID. You can find it using "Identity" > "Users" in the Horizon GUI; it is an alphanumeric string (*not* the human-readable user name).


```
[chi_tacc]
type = swift
user_id = YOUR_USER_ID
application_credential_id = APP_CRED_ID
application_credential_secret = APP_CRED_SECRET
auth = https://chi.tacc.chameleoncloud.org:5000/v3
region = CHI@TACC
```


Use Ctrl+O and Enter to save the file, and Ctrl+X to exit `nano`.

To test it, run

```bash
# run on node-persist
rclone lsd chi_tacc:
```

and verify that you see your container listed. This confirms that `rclone` can authenticate to the object store.

:::

::: {.cell .markdown}

### Create a pipeline to load training data into the object store

Next, we will prepare a simple ETL pipeline to get the Food11 dataset into the object store. It will:

* extract the data into a staging area (local filesystem on the instance)
* transform the data, organizing it into directories by class as required by PyTorch
* and then load the data into the object store

We are going to define the pipeline stages inside a Docker compose file. All of the services in the container will share a common `food11` volume. Then, we have:

1. A service to extract the Food11 data from the Internet. This service runs a Python container image, downloads the dataset, and unzips it.

```
  extract-data:
    container_name: etl_extract_data
    image: python:3.11
    user: root
    volumes:
      - food11:/data
    working_dir: /data
    command:
      - bash
      - -c
      - |
        set -e

        echo "Resetting dataset directory..."
        rm -rf Food-11
        mkdir -p Food-11
        cd Food-11

        echo "Downloading dataset zip..."
        curl -L https://nyu.box.com/shared/static/m5kvcl25hfpljul3elhu6xz8y2w61op4.zip \
          -o Food-11.zip

        echo "Unzipping dataset..."
        unzip -q Food-11.zip
        rm -f Food-11.zip

        echo "Listing contents of /data after extract stage:"
        ls -l /data
```

2. A service that runs a Python container image, and uses a Python script to organize the data into directories according to class label.

```
  transform-data:
    container_name: etl_transform_data
    image: python:3.11
    volumes:
      - food11:/data
    working_dir: /data/Food-11
    command:
      - bash
      - -c
      - |
        set -e

        python3 -c '
        import os
        import shutil

        dataset_base_dir = "/data/Food-11"
        subdirs = ["training", "validation", "evaluation"]
        classes = [
            "Bread", "Dairy product", "Dessert", "Egg", "Fried food",
            "Meat", "Noodles/Pasta", "Rice", "Seafood", "Soup", "Vegetable/Fruit"
        ]

        for subdir in subdirs:
            dir_path = os.path.join(dataset_base_dir, subdir)
            if not os.path.exists(dir_path):
                continue

            for i, class_name in enumerate(classes):
                class_dir = os.path.join(dir_path, f"class_{i:02d}")
                os.makedirs(class_dir, exist_ok=True)
                for f in os.listdir(dir_path):
                    if f.startswith(f"{i}_"):
                        shutil.move(
                            os.path.join(dir_path, f),
                            os.path.join(class_dir, f)
                        )
        '

        echo "Listing contents of /data/Food-11 after transform stage:"
        ls -l /data/Food-11
```

3. And finally, a service that uses `rclone copy` to load the organized data into the object store. Note that we pass some arguments to `rclone copy` to increase the parallelism, so that the data is loaded more quicly. Also note that since the name of the container includes your individual net ID, we have specified it using an environment variable that must be set before this stage can run.

```
    container_name: etl_load_data
    image: rclone/rclone:latest
    volumes:
      - food11:/data
      - ~/.config/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro
    entrypoint: /bin/sh
    command:
      - -c
      - |
        if [ -z "$RCLONE_CONTAINER" ]; then
          echo "ERROR: RCLONE_CONTAINER is not set"
          exit 1
        fi
        echo "Cleaning up existing contents of container..."
        rclone delete chi_tacc:$RCLONE_CONTAINER --rmdirs || true

        rclone copy /data/Food-11 chi_tacc:$RCLONE_CONTAINER \
        --progress \
        --transfers=32 \
        --checkers=16 \
        --multi-thread-streams=4 \
        --fast-list

        echo "Listing directories in container after load stage:"
        rclone lsd chi_tacc:$RCLONE_CONTAINER
```

These services are defined in `~/data-persist-chi/docker/docker-compose-etl.yaml`.

Now, we can run the stages using Docker. (If we had a workflow orchestrator, we could use it to run the pipeline stages - but we don't really need orchestration at this point.)


```bash
# run on node-persist
docker compose -f ~/data-persist-chi/docker/docker-compose-etl.yaml run extract-data
```

```bash
# run on node-persist
docker compose -f ~/data-persist-chi/docker/docker-compose-etl.yaml run transform-data
```

For the last stage, the container name is not specified in the Docker compose YAML (since it has your net ID in it) - so we have to pass it as an environment variable first. Substitute your own net ID in the line below:

```bash
# run on node-persist
export RCLONE_CONTAINER=object-persist-netID
docker compose -f ~/data-persist-chi/docker/docker-compose-etl.yaml run load-data
```

Now our training data is loaded into the object store and ready to use for training! We can clean up the Docker volume used as the temporary staging area:

```bash
# run on node-persist
docker volume rm food11-etl_food11
```

In the Horizon GUI, note that we can browse the object store and download any file from it. This container is independent of any compute instance - it will persist, and its data is still saved, even if we have no active compute instance. (In fact, we *already* have no active compute instance on CHI@TACC.)

:::

::: {.cell .markdown}

### Mount an object store to local file system

Now that our data is safely inside the object store, we can use it anywhere - on a VM, on a bare metal site, on multiple compute instances at once, even outside of Chameleon - to train or evaluate a model. We would not have to repeat the ETL pipeline each time we want to use the data.

If we were working on a brand-new compute instance, we would need to download `rclone` and create the `rclone` configuration file at `~/.config/rclone.conf`, as we have above. Since we already done these steps in order to load data into the object store, we don't need to repeat them.

The next step is to create a mount point for the data in the local filesystem:

```bash
# run on node-persist
sudo mkdir -p /mnt/object
sudo chown -R cc /mnt/object
sudo chgrp -R cc /mnt/object
```

Now finally, we can use `rclone mount` to mount the object store at the mount point (substituting your own **netID** in the command below).

```bash
# run on node-persist
rclone mount chi_tacc:object-persist-netID /mnt/object --read-only --allow-other --daemon
```

Here, 

* `chi_tacc` tells `rclone` which section of its configuration file to use for authentication information
* `object-persist-netID` tells it what object store container to mount
* `/mnt/object` says where to mount it

Since we only intend to read the data, we can mount it in read-only mode and it will be slightly faster; and we are also protected from accidental writes. We also specified `--allow-other` so that we can use the mount from Docker, and `--daemon` means the `rclone` process will be started in the background.


Run 

```bash
# run on node-persist
ls /mnt/object
```

and confirm that we can now see the Food11 data directories (`evaluation`, `training`, `validation`) there.

Now, we can start a Docker container with access to that virtual "filesystem", by passing that directory as a bind mount. Note that to mount a directory that is actually a FUSE filesystem inside a Docker container, we have to pass it using a slightly different `--mount` syntax, instead of the `-v` that we had used in previous examples.

```bash
# run on node-persist
docker run -d --rm \
  -p 8888:8888 \
  --shm-size 8G \
  -e FOOD11_DATA_DIR=/mnt/Food-11 \
  -v ~/data-persist-chi/workspace:/home/jovyan/work/ \
  --mount type=bind,source=/mnt/object,target=/mnt/Food-11,readonly \
  --name jupyter \
  quay.io/jupyter/pytorch-notebook:latest
```

To access the Jupyter service, we will need its randomly generated secret token (which secures it from unauthorized access). We'll get this token by running `jupyter server list` inside the `jupyter` container:

```bash
# run on node-persist
docker exec jupyter jupyter server list
```

Look for a line like

```
http://localhost:8888/lab?token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Paste this into a browser tab, but in place of `localhost`, substitute the floating IP assigned to your instance, to open the Jupyter notebook interface that is running *on your compute instance*.

Then, find the `demo.ipynb` notebook. This notebook evaluates the `food11.pth` model on the evaluation set, which is **streamed from the object store**.

To validate this, on the host, run

```bash
# run on node-persist
sudo apt update
sudo apt -y install nload
nload ens3
```

to monitor the load on the network. Run the `demo.ipynb` notebook inside the Jupyter instance running on "node-persist", which also watching the `nload` output. 

Note the incoming data volume, which should be on the order of Mbits/second when a batch is being loaded.

Close the Jupyter container tab in your browser, and then stop the container with


```bash
# run on node-persist
docker stop jupyter
```

since we will bring up a different Jupyter instance in the next section.

:::

::: {.cell .markdown}

### Un-mount an object store

We'll keep working with this object store in the next part, so you do not have to un-mount it now. But generally speaking to stop `rclone` running and un-mount the object store, you would run

```
fusermount -u /mnt/object
```

where you specify the path of the mount point.


:::
