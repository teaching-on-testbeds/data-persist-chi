
::: {.cell .markdown}

# Persistent storage on Chameleon

You've done really well operationalizing the infrastructure and configuration of the runtime environment at GourmetGram! 
Next, you're going to dig deeper into each stage of your model pipeline. But, there are two major issues you need to address first:

* Applications and services in GourmetGram - including Jupyter services for ML experimentation, model registry services, even application services - save all their data to the *ephemeral* disk of the compute instances that they are running on. When the compute instance ends, the data is lost.
* The training data for your food classifier model is also not persisted anywhere. Right now, you're only training on external data, which you can re-import at any time. But eventually, you will want to train on production data. You need an organized data repository in which to persist training data, and you want to make sure that when training your food classifier model, you will be able to pull data at a high enough rate to keep your powerful GPUs busy during training.

This lab has two parts:

* `block/`: block storage volumes on Chameleon (persistent filesystem for a VM)
* `object/`: object storage on Chameleon (persist training data and other large artifacts)

You can do either part independently.

To run this experiment, you should have already created an account on Chameleon, and become part of a project. You should also have added your SSH key to the KVM@TACC site and the CHI@TACC site.

:::

::: {.cell .markdown}

## Open this experiment on Trovi


When you are ready to begin, you will continue with the next step! To begin this step, open this experiment on Trovi:

* Use this link: [Persistent storage on Chameleon](https://chameleoncloud.org/experiment/share/a1c68238-81f8-498d-8323-9d6c46cb0a78) on Trovi
* Then, click "Launch on Chameleon". This will start a new Jupyter server for you, with the experiment materials already in it.

You will see a `block/` and an `object/` directory inside `data-persist-chi`.

Open one of:

* `block/0_intro.ipynb`
* `object/0_intro.ipynb`

and continue there.

:::
