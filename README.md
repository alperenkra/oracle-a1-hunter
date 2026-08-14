# oracle-a1-hunter

A small GitHub Actions job that waits for capacity on Oracle Cloud's **Always Free**
ARM shape (`VM.Standard.A1.Flex`). In the Frankfurt region this shape constantly returns
"Out of host capacity", so the job keeps retrying at a fixed interval until capacity opens up.

## How it works

- Runs every 15 minutes (`.github/workflows/hunt.yml`).
- Each run spends about 4 minutes trying, stepping down through
  **4 OCPU / 24 GB → 2/12 → 1/6** across every availability domain in the tenancy.
  The first shape that gets accepted is the one you keep.
- Availability domains and the latest Ubuntu 24.04 aarch64 image are looked up from the
  API on every run, so nothing has to be updated by hand.
- If the API replies with a rate limit (429), the delay between attempts doubles itself.
- If the tenancy already has a running instance, the run exits without trying anything.
  That way it never collides with another hunter running elsewhere (for example on a laptop)
  and never burns the free quota on a second instance.
- When an instance is created, the workflow opens an issue containing the public IP and a
  ready-to-use `ssh` command.

## Required secrets

| Secret | Contents |
| --- | --- |
| `OCI_CLI_USER` | User OCID |
| `OCI_CLI_TENANCY` | Tenancy OCID |
| `OCI_CLI_FINGERPRINT` | API key fingerprint |
| `OCI_CLI_KEY_CONTENT` | API private key (PEM) |
| `OCI_CLI_REGION` | Region, e.g. `eu-frankfurt-1` |
| `OCI_SUBNET_ID` | OCID of the public subnet the instance attaches to |
| `OCI_SSH_PUBKEY` | SSH public key to install on the instance |

The workflow is triggered only by `schedule` and `workflow_dispatch`. There is no pull
request trigger, so code coming from forks can never reach the secrets.
