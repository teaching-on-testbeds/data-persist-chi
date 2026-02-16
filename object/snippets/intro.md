
::: {.cell .markdown}

# Object storage on Chameleon

This part of the lab focuses on object storage: persisting training data in S3-compatible object storage and benchmarking training input pipelines (local ImageFolder, ImageFolder over an rclone mount, one-object-per-sample reads, and sharded streaming).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.

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
