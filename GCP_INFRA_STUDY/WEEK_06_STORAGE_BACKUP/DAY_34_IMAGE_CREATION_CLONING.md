# Day 34 — Image Creation & Cloning

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Images, Machine Images & Instance Templates

GCP has multiple ways to clone/template a VM. Each serves a different purpose:

```
┌────────────────────────────────────────────────────────────────┐
│              VM Cloning Options Comparison                      │
│                                                                │
│  ┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Custom Image │  │  Machine Image    │  │ Instance        │  │
│  │              │  │                   │  │ Template        │  │
│  │ • Boot disk  │  │ • ALL disks       │  │ • Config only   │  │
│  │   only       │  │ • VM config       │  │ • No data       │  │
│  │ • No config  │  │ • Metadata        │  │ • References    │  │
│  │ • Reusable   │  │ • Network         │  │   image family  │  │
│  │   across     │  │ • Service account │  │ • Used by MIGs  │  │
│  │   projects   │  │ • Tags            │  │                 │  │
│  │              │  │ • Full clone      │  │                 │  │
│  └──────────────┘  └──────────────────┘  └─────────────────┘  │
│                                                                │
│  When to use:                                                  │
│  Custom Image → Golden OS image, share across projects         │
│  Machine Image → Full VM backup/clone (disaster recovery)      │
│  Instance Template → Repeatable VM spec for autoscaling        │
└────────────────────────────────────────────────────────────────┘
```

**Linux analogy:**

| Linux Concept | GCP Equivalent |
|---|---|
| `dd if=/dev/sda of=disk.img` | Custom Image (disk-level) |
| Full VM export (disk + config) | Machine Image |
| Kickstart/Preseed template | Instance Template |
| Image families (latest CentOS 7.x) | Image Families |
| `packer build` output | Custom Image |

### Custom Images

```
┌─────────────────────────────────────────────────────┐
│             Custom Image Workflow                    │
│                                                     │
│  Source VM (running)                                │
│  ┌──────────┐                                       │
│  │ Boot Disk│──► Stop VM ──► Create Image           │
│  │ /dev/sda │                  │                    │
│  └──────────┘                  ▼                    │
│                          ┌──────────┐               │
│                          │  Image   │               │
│                          │ "web-v1" │               │
│                          └────┬─────┘               │
│                               │                     │
│                    ┌──────────┼──────────┐           │
│                    ▼          ▼          ▼           │
│               ┌──────┐  ┌──────┐  ┌──────┐          │
│               │ VM-1 │  │ VM-2 │  │ VM-3 │          │
│               └──────┘  └──────┘  └──────┘          │
│               (All boot from same golden image)     │
└─────────────────────────────────────────────────────┘
```

### Image Families

Image families let you reference the **latest** image in a group:

```
  Image Family: "web-server"
  ┌──────────────────────────────────┐
  │                                  │
  │  web-server-v1  (deprecated)     │
  │  web-server-v2  (deprecated)     │
  │  web-server-v3  ◄── LATEST       │
  │                                  │
  └──────────────────────────────────┘

  gcloud compute instances create vm \
    --image-family=web-server
  → Always gets v3 (the latest non-deprecated)
```

**Linux analogy:** Like `latest` tag on Docker images, or `yum install nginx` always getting the latest version in the repo.

### Machine Images (Full VM Clone)

```
┌─────────────────────────────────────────────────────┐
│           Machine Image Contents                    │
│                                                     │
│  Source VM: "prod-app-01"                           │
│  ┌────────────────────────────────────────────┐     │
│  │  Boot Disk      ✓ captured                 │     │
│  │  Data Disk 1    ✓ captured                 │     │
│  │  Data Disk 2    ✓ captured                 │     │
│  │  Machine Type   ✓ e2-standard-2            │     │
│  │  Network/Subnet ✓ custom-vpc/prod-subnet   │     │
│  │  Tags           ✓ http-server, prod        │     │
│  │  Service Acct   ✓ app-sa@project.iam       │     │
│  │  Metadata       ✓ startup-script, etc      │     │
│  │  Labels         ✓ env=prod, team=platform  │     │
│  └────────────────────────────────────────────┘     │
│                                                     │
│  = Complete VM snapshot (disk data + configuration) │
└─────────────────────────────────────────────────────┘
```

### Instance Templates

```
┌─────────────────────────────────────────────────┐
│          Instance Template                      │
│                                                 │
│  Name: web-template-v3                          │
│  ┌───────────────────────────────────────────┐  │
│  │  Machine Type:  e2-medium                 │  │
│  │  Image:         image-family/web-server   │  │
│  │  Disk:          pd-balanced, 20GB         │  │
│  │  Network:       custom-vpc/web-subnet     │  │
│  │  Tags:          http-server               │  │
│  │  SA:            web-sa@project.iam        │  │
│  │  Startup:       install_nginx.sh          │  │
│  │  Labels:        env=prod                  │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Used by: Managed Instance Group (MIG)          │
│  Note: Templates are IMMUTABLE (create new one  │
│        to change, then update MIG reference)    │
└─────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export VM_SOURCE="source-vm-lab34"
```

### Step 1 — Create a Source VM with Software Installed

```bash
# Create source VM
gcloud compute instances create ${VM_SOURCE} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=lab34,http-server \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
echo "Golden Image v1 - $(hostname)" > /var/www/html/index.html
systemctl enable nginx'

# Wait for startup script to complete
sleep 60

# Verify nginx is running
gcloud compute ssh ${VM_SOURCE} --zone=${ZONE} --command="
systemctl status nginx --no-pager
curl -s localhost
cat /var/www/html/index.html
"
```

### Step 2 — Create a Custom Image from the VM

```bash
# Stop the VM first (recommended for consistent images)
gcloud compute instances stop ${VM_SOURCE} --zone=${ZONE}

# Create image from the boot disk
gcloud compute images create web-server-v1 \
  --source-disk=${VM_SOURCE} \
  --source-disk-zone=${ZONE} \
  --family=web-server \
  --description="Debian 12 + Nginx - v1" \
  --labels=version=v1,env=lab

# Verify image
gcloud compute images describe web-server-v1
gcloud compute images list --filter="family=web-server"
```

### Step 3 — Create VMs from the Custom Image

```bash
# Create VM using the specific image
gcloud compute instances create from-image-lab34 \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image=web-server-v1 \
  --tags=lab34

# Create VM using the image family (always gets latest)
gcloud compute instances create from-family-lab34 \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=web-server \
  --tags=lab34

# Verify both VMs have nginx
for vm in from-image-lab34 from-family-lab34; do
  echo "=== ${vm} ==="
  gcloud compute ssh ${vm} --zone=${ZONE} --command="curl -s localhost"
done
```

### Step 4 — Update Image and Use Families

```bash
# Start source VM, make changes
gcloud compute instances start ${VM_SOURCE} --zone=${ZONE}
sleep 30

gcloud compute ssh ${VM_SOURCE} --zone=${ZONE} --command="
echo 'Golden Image v2 - $(hostname) - with monitoring' | sudo tee /var/www/html/index.html
sudo apt-get install -y htop iotop
"

# Stop and create v2 image
gcloud compute instances stop ${VM_SOURCE} --zone=${ZONE}

gcloud compute images create web-server-v2 \
  --source-disk=${VM_SOURCE} \
  --source-disk-zone=${ZONE} \
  --family=web-server \
  --description="Debian 12 + Nginx + monitoring tools - v2" \
  --labels=version=v2,env=lab

# Deprecate v1
gcloud compute images deprecate web-server-v1 \
  --state=DEPRECATED \
  --replacement=web-server-v2

# Verify family now points to v2
gcloud compute images describe-from-family web-server
```

### Step 5 — Create a Machine Image (Full Clone)

```bash
# Start the source VM
gcloud compute instances start ${VM_SOURCE} --zone=${ZONE}
sleep 30

# Create machine image (captures everything)
gcloud compute machine-images create full-clone-lab34 \
  --source-instance=${VM_SOURCE} \
  --source-instance-zone=${ZONE} \
  --storage-location=${REGION}

# Verify
gcloud compute machine-images describe full-clone-lab34

# Create a new VM from the machine image
gcloud compute instances create from-machine-image-lab34 \
  --zone=${ZONE} \
  --source-machine-image=full-clone-lab34

# Verify it's a full clone
gcloud compute ssh from-machine-image-lab34 --zone=${ZONE} --command="
curl -s localhost
dpkg -l | grep -E 'nginx|htop'
"
```

### Step 6 — Create an Instance Template

```bash
# Create instance template from the custom image family
gcloud compute instance-templates create web-template-lab34 \
  --machine-type=e2-micro \
  --image-family=web-server \
  --boot-disk-size=10GB \
  --tags=http-server,lab34 \
  --region=${REGION} \
  --labels=env=lab,week=6

# Verify
gcloud compute instance-templates describe web-template-lab34

# Create a VM from the template
gcloud compute instances create from-template-lab34 \
  --zone=${ZONE} \
  --source-instance-template=web-template-lab34
```

### Cleanup

```bash
# Delete VMs
for vm in ${VM_SOURCE} from-image-lab34 from-family-lab34 from-machine-image-lab34 from-template-lab34; do
  gcloud compute instances delete ${vm} --zone=${ZONE} --quiet 2>/dev/null
done

# Delete instance template
gcloud compute instance-templates delete web-template-lab34 --quiet

# Delete machine image
gcloud compute machine-images delete full-clone-lab34 --quiet

# Delete custom images
gcloud compute images delete web-server-v1 --quiet
gcloud compute images delete web-server-v2 --quiet

# Terraform:
# terraform destroy -auto-approve
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Custom Image** = boot disk only; shareable across projects; use for golden OS images
- **Image Family** = pointer to latest non-deprecated image in a group
- **Machine Image** = full VM clone (all disks + config + metadata); use for DR/migration
- **Instance Template** = VM specification (no data); immutable; used by MIGs
- **Stop VM** before creating images for consistency (not required but recommended)
- **Deprecate** old images to guide users to the latest version

### Essential Commands

```bash
# Custom images
gcloud compute images create NAME --source-disk=DISK --source-disk-zone=ZONE --family=FAMILY
gcloud compute images list --filter="family=FAMILY"
gcloud compute images describe-from-family FAMILY
gcloud compute images deprecate NAME --state=DEPRECATED --replacement=NEW_IMAGE

# Machine images
gcloud compute machine-images create NAME --source-instance=VM --source-instance-zone=ZONE
gcloud compute instances create VM --source-machine-image=MACHINE_IMAGE

# Instance templates
gcloud compute instance-templates create NAME --machine-type=TYPE --image-family=FAMILY
gcloud compute instances create VM --source-instance-template=TEMPLATE
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: You need to deploy 50 identical web servers. Should you use a custom image, machine image, or instance template? Why?</strong></summary>

**Answer:** Use a **combination of custom image + instance template:**

1. **Custom Image** — Create a golden image with your OS + software (e.g., `web-server-v3`) and add it to an image family
2. **Instance Template** — Reference the image family, set machine type, network, tags, startup scripts
3. **Managed Instance Group (MIG)** — Uses the template to create 50 identical VMs with auto-healing and rolling updates

**Why not machine image alone?** Machine images capture a specific VM's full state including unique identifiers, hostnames, and data — not suitable for 50 identical copies. Instance templates + custom images separate the OS+software (image) from the VM specification (template), giving you clean scalability.
</details>

<details>
<summary><strong>Q2: What's the advantage of image families over referencing a specific image name?</strong></summary>

**Answer:** Image families provide **automatic version resolution:**

- `--image-family=web-server` always resolves to the **latest non-deprecated** image
- When you bake a new image (e.g., security patches), new VMs automatically pick it up
- No need to update instance templates, scripts, or Terraform configs with new image names
- You can **deprecate** old images and users are automatically guided to the replacement
- Rollback is simple: deprecate the bad image, and the family reverts to the previous good one

**Analogy:** It's like pointing to `latest` in a package repo vs pinning `nginx-1.24.0-3.el9.x86_64.rpm`.
</details>

<details>
<summary><strong>Q3: Your team needs to clone a running production VM to a staging environment (different VPC, same region). What approach do you use?</strong></summary>

**Answer:** Use a **Machine Image:**

1. Create machine image from the prod VM (can be done while running): `gcloud compute machine-images create prod-clone --source-instance=prod-vm-01 --source-instance-zone=europe-west2-a`
2. Create new VM in staging VPC from machine image, overriding network settings: `gcloud compute instances create staging-vm-01 --source-machine-image=prod-clone --zone=europe-west2-a --subnet=staging-subnet --no-address`

**Why machine image?** It captures ALL disks and the full VM configuration. A custom image only captures the boot disk, so you'd lose data disks, metadata, and labels. The machine image preserves everything, and you can override specific settings (network, name) at creation time.
</details>

<details>
<summary><strong>Q4: Should you stop a VM before creating a custom image? What are the risks of imaging a running VM?</strong></summary>

**Answer:**

**Recommended: Stop the VM first.**

**Risks of imaging a running VM:**
- **Filesystem inconsistency** — writes in progress may be captured partially (dirty buffers)
- **Database corruption** — database files may be in an inconsistent state
- **Application state** — in-memory state not flushed to disk is lost

**If you must image a running VM:**
1. Quiesce the application (stop writes)
2. Flush filesystem: `sync && fsfreeze --freeze /mnt/data`
3. Create the image
4. Unfreeze: `fsfreeze --unfreeze /mnt/data`

**Note:** GCP custom images from running VMs do use a "best-effort" consistency mechanism for the boot disk, but it's not guaranteed for data disks or databases. Always stop if possible, or use application-level quiescing.
</details>
