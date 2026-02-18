
::: {.cell .markdown}

# Object storage on Chameleon

This part of the lab focuses on object storage: persisting training data in S3-compatible object storage and benchmarking training input pipelines (local ImageFolder, ImageFolder over an rclone mount, one-object-per-sample reads, and sharded streaming).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.

:::

::: {.cell .markdown}

## Experiment materials

* The ETL jobs in this experiment are executed using Docker compose. You can find those configurations at [object/docker](https://github.com/teaching-on-testbeds/data-persist-chi/tree/main/object/docker)
* We will benchmark different training data input strategies using the Python notebooks at [object/workspace](https://github.com/teaching-on-testbeds/data-persist-chi/tree/main/object/workspace)

:::

::: {.cell .markdown}

## Experiment resources 

For this experiment, we will provision 

* one object storage bucket on CHI@TACC
* one virtual machine on KVM@TACC, with a floating IP, to practice using the persistent storage

:::

::: {.cell .markdown}

You will see several notebooks inside the `data-persist-chi/object` directory. Open `0_intro.ipynb` and continue there.

:::
