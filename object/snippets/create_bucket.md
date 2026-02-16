
::: {.cell .markdown}

## Create an object storage bucket

In this lab, we will store training data in object storage so we can reuse it across many training runs and many compute instances.

Chameleon object storage is only offered at the CHI@TACC and CHI@UC sites. It is not offered at KVM@TACC, which is where our VM compute instance runs.

That is not a problem, because object storage is accessed over an API. As long as there is sufficient network bandwidth and reasonably low network latency between compute and storage, we can train on data stored in object storage even when compute and storage are in different logical Chameleon sites.

We will create an object storage bucket (which in OpenStack, is also - confusingly- called a container) at CHI@TACC. Later, we will access this bucket using the S3 API.

:::

::: {.cell .markdown}

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
:::

::: {.cell .markdown}

### Generate S3 credentials

To access this object storage using the S3 API from our compute instance and from our containers, we need an access key and secret key.

In Chameleon, we can generate an EC2-style credential (access key + secret key) for our current user and project.

Important: treat the secret like a password. Save it somewhere safe. If you share screenshots or publish notebooks, clear the cell output first.

The following cells run in the Chameleon Jupyter environment.

:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
from openstack import connection
from chi import context
import chi

context.choose_project()
context.choose_site(default="CHI@TACC")
```
:::

::: {.cell .code}
```python
# run in Chameleon Jupyter environment
conn = connection.from_config()

project_id = conn.current_project_id
identity_ep = conn.session.get_endpoint(service_type="identity", interface="public")
url = f"{identity_ep}/v3/users/{conn.current_user_id}/credentials/OS-EC2"

payload = {"tenant_id": project_id}
response = conn.session.post(url, json=payload)
response.raise_for_status()
ec2 = response.json()["credential"]

print("EC2 Access:", ec2["access"])
print("EC2 Secret:", ec2["secret"])
```
:::
