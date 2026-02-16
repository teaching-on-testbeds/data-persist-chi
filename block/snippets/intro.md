
::: {.cell .markdown}

# Block storage on Chameleon

This part of the lab focuses on block storage: how to attach a persistent block volume to a VM and use it as a durable filesystem (for example, to persist a Jupyter workspace across VM deletion and recreation).

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site.

:::

::: {.cell .markdown}

## Experiment resources 

For this experiment, we will provision 

* one block storage volume on KVM@TACC
* one virtual machine on KVM@TACC, with a floating IP, to practice using the persistent storage

:::

::: {.cell .markdown}

You will see several notebooks inside the `data-persist-chi/block` directory. Open `0_intro.ipynb` and continue there.

:::
