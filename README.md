# k8s-configs

This [Ansible](https://www.ansible.com/) playbook offers a highly-optimized [Kubernetes](https://kubernetes.io/) package for the [mdx](https://mdx.jp/) computing platform.

The playbook automatically installs the following components as a usable form within 10 minites:
- [k0s](https://k0sproject.io/) (a light-weight Kubernetes distribution)
- [containerd](https://containerd.io/) and nvidia container runtime (as container runtimes on computing nodes)
- [Topology](https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/), [CPU](https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/), and [memory managers](https://kubernetes.io/docs/tasks/administer-cluster/memory-manager/) (for NUMA-aware, static resource partitioning)
- [Docker](https://www.docker.com/) (for building container images on the bastion host)
- [Harbor](https://goharbor.io/) private container repository with private self-certificate 
- [Exascaler File CSI driver](https://github.com/DDNStorage/exa-csi-driver) (as a container persistent volume driver)
- [NVIDIA's GPU](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html) and [network operators](https://docs.nvidia.com/networking/display/COKAN10/Network+Operator) (for A100 GPUs and ROCEv2 networking)
- [MetalLB](https://metallb.universe.tf/) (as a load balancer)
- [MPI operator](https://github.com/kubeflow/mpi-operator) (for supporting parallel computing jobs)
- [Spark on k8s Operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) with [RAPIDS and UCX shuffle manager](https://rapids.ai/) (for large data processing)
- [Kube Prometheus stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) (for monitoring and alerting)

This playbook was written being inspired from the [machine-configs](https://github.com/mdx-jp/machine-configs), but doesn't currently share the code with it.

## Prerequisites

This playbook assumes the following virtual machines exist in a user tenant. All machines should be installed with Ubuntu 20.04 server.

- a single bastion host 
  - with 1 or a higher number of CPU cores, PortGroup networking
- a single harbor private repository host
  - with 2 or a higher number of CPU cores, 160GB or larger disk capacity, PortGroup networking
- a single kubernetes master node 
  - with 2 or a higher number of CPU cores, PortGroup networking
- 0 or a larger number of kubernetes computing nodes. 
  - each with 2 or a higher number of CPU cores, 100GB or larger disk capacity, SR-IOV (RDMA) networking
- 0 or a larger number of GPU nodes. 
  - each with 1 or a larger number of GPUs, 100GB or larger disk capacity, SR-IOV (RDMA) networking

We assume that all the above nodes are SSH-accessible from the basion host by using public key authentication without entering passwords (Initial passwords must be set on each node beforehand after OS installation).

For example, use the ``-A`` (ForwardAgent) option to allow recursive SSH access to other nodes using the same public/private key pairs.
```sh
% eval `ssh-agent`
% ssh-add
% ssh -A (bastion's IP address)
```

## Getting Started

Clone k8s-config repository
```sh
cd ~
git clone https://github.com/fukumame/k8s-configs.git
```

Update the list of packages
```sh
$ sudo apt update
```

Install [uv](https://docs.astral.sh/uv/)
```sh
$ curl -LsSf https://astral.sh/uv/install.sh | sh
```

Install python packages with uv
```shell
$ cd ~/k8s-configs 
$ uv sync
```

Install other required libraries
```shell
sh install_dep_packages.sh
```

Create the inventory of your environment. Each environment has its own directory under ``inventories/``. The ``hosts.ini`` of each environment is not stored in git.
```sh
$ cp -r inventories/example inventories/<env>
$ mg inventories/<env>/hosts.ini
$ mg inventories/<env>/group_vars/all.yaml
```
In ``hosts.ini``, fill in the IP addresses of each node (by ansible_host and roce_host). Copy the kube-node and kube-gpu entries as needed.

In ``group_vars/all.yaml``, set the environment:
- ``env_name``: the directory name (``<env>``)
- ``env_protected``: ``true`` for production
- ``lustre_net``: ``tcp10`` when the storage network is "仮想NIC（自動）", ``o2ib10`` when it is "SR-IOV"
- ``node_ip_mode``: ``static`` (node IPs set by hand, in the host range 1-100) or ``dhcp``
- ``k8s_pod_cidr``, ``k8s_service_cidr``: must not overlap with the networks of the mdx project
- ``network_operator_enabled``, ``gpu_operator_rdma_enabled``: ``false`` when there is no RDMA device (virtual NIC)
- ``k0s_version``, ``kubectl_version``, ``kubectl_checksum`` (optional): another Kubernetes version than the default in ``roles/k8s/defaults/main.yaml``. Set all three together.
- ``gpu_operator_chart_version``, ``network_operator_chart_version``, ``prometheus_stack_chart_version`` (optional): other Helm chart versions than the defaults in ``roles/k8s_service/defaults/main.yaml``
- ``metallb_enabled``, ``metallb_addresses``: install MetalLB (tag ``service``). See "Using LoadBalancer".
- ``knative_enabled``, ``knative_domain``, ``kourier_lb_ip``: install Knative Serving and Kourier (tag ``knative``). See "Using Knative Serving".
- ``entry_proxy_server_name``, ``entry_proxy_routes``: nginx in front of Kourier for the hosts in ``[entry_proxy]`` (tag ``entry_proxy``). See "Using the entry proxy".

If you used ``inventory.ini`` before, move it to ``inventories/prod/hosts.ini``.

Copy the password file from the template and rewrite it. 
```sh
$ cp vault.yaml.template vault.yaml
$ mg vault.yaml
```

Set the harbor's admin and database passwords and grafana password.

```yaml
---
harbor_admin_password:
harbor_db_password:

grafana_password:
```

Encrypt the above file by Ansible Vault (set the Vault password).
```sh
$ encrypt_vault.sh
```

Run the playbook and wait until the Kubernetes platform is constructed.
```sh
$ ./play.sh <env> --tags all
```

A protected environment (``env_protected: true``, such as ``prod``) stops unless you confirm it. Also narrow the run with ``--tags`` and ``--limit``:
```sh
$ ./play.sh prod --tags <tags> --limit <hosts> -e confirm_env=prod
```

## How to use the cluster

The ``examples`` directory contains some sample manifest files to show how to use the cluster.

### Using kubectl and helm
The kubectl and helm commands are installed on the bastion host.

```sh
bastion:~$ kubectl get node
NAME         STATUS   ROLES    AGE    VERSION
kube-gpu1    Ready    <none>   6d9h   v1.23.3+k0s
kube-gpu2    Ready    <none>   6d9h   v1.23.3+k0s
kube-node1   Ready    <none>   6d9h   v1.23.3+k0s
kube-node2   Ready    <none>   6d9h   v1.23.3+k0s
```

### Accessing Kubernetes cluster from LENS
LENS should be installed on an operator side machine that accesses the bastion host via SSH. 

Copy and paste the ``.kube/config`` file to the LENS configuration and rewrite the kube-master's address to  ``localhost`` or ``127.0.0.1``.

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ...
    server: https://kube-master:6443 # to localhost or 127.0.0.1
  name: k0s-cluster
```

When accessing, use SSH port forwarding to make kube-master accessible from LENS.

```sh
% ssh -L 6443:(kube-master's IP address):6443 -A (bastion's IP address)
```

### Accessing Harbor 
Harbor accepts connections on 443 port of the Harbor host. Use SSH port forwarding to make it accessible from the local web browser.
```ssh
% ssh -L 8443:(harbor's IP address):443 -A (bastion's IP address)
```
Harbor's admin password was set during installation.

### Pushing container images to Harbor

Before pushing a container image to the Harbor, the user must login to the Harbor registory.

```sh
bastion:~$ sudo docker login harbor.internal
bastion:~$ sudo docker build . -t harbor.internal/library/<image name>:<tag>
bastion:~$ sudo docker push harbor.internal/library/<image name>:<tag>
```

### Accessing Grafana
To access Grafana dashboard, use the ``kubectl port-forward`` and SSH port forwarding. The Grafana's password was set in ``vault.yaml`` during installation process.

To make the access more persistent, use the LoadBalancer service instead of default one (Please see ``examples/grafana`` directory).

### Using persistent volumes

Two storage classes are predefined during installation. Write PVC (persistent volume claim) and Pod manifest files to use a persistent volume in a pod.

```sh
bastion:~$ kubectl get sc
NAME                 PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
exascaler-sc-fast    exa.csi.ddn.com   Delete          Immediate           false                  5d18h
exascaler-sc-large   exa.csi.ddn.com   Delete          Immediate           false                  5d18h
```
### Utilizing GPUs and RDMA devices

GPUs and RDMA devices are defined as allocatable resourcees on nodes.

```sh
bastion:~$ kubectl describe node kube-gpu1
...
Addresses:
  Hostname:    kube-gpu1
Capacity:
  nvidia.com/gpu:           1
  rdma/rdma_shared_device:  1k
Allocatable:
  nvidia.com/gpu:           1
  rdma/rdma_shared_device:  1k
```  

### MIG (multi-instance GPU) support 
NVIDIA GPU operator supports MIG. This playbook doesn't enable MIG by default, but it can be enabled by [configuring MIG profiles](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/gpu-operator-mig.html).

```sh
bastion:~$ kubectl label nodes kube-gpu1 nvidia.com/mig.config=all-1g.5gb
```

### SR-IOV networking

SR-IOV networking is supported as a secondary network in a pod by using [Multus](https://github.com/k8snetworkplumbingwg/multus-cni) and [Whereabouts](https://github.com/k8snetworkplumbingwg/whereabouts).

To use this feature, write a network attachment definition:
```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: rdma-ipvlan-conf
spec:
  config: '{
      "cniVersion": "0.3.0",
      "name": "rdma-ipvlan-conf",
      "type": "ipvlan",
      "master": "ens192",
      "mode": "l2",
      "ipam": {
        "type": "whereabouts",
        "range": "10.146.16.0/21",
        "range_start": "10.146.18.100",
        "range_end": "10.146.18.120",
        "log_file": "/tmp/whereabouts.log",
        "log_level": "debug"
      }
    }'
```
and add an annotation to the pod definition:
```yaml
    annotations:
      "k8s.v1.cni.cncf.io/networks": "rdma-ipvlan-conf"
```
### Using LoadBalancer

MetalLB automatically assigns public IP addresses (which are opened to the outside of the cluster) to Services from the pooled address range. It can be used by specifiyng the ``LoadBalancer`` type in a Kubernetes service definition.

MetalLB is off by default. Turn it on and set the pooled addresses in ``inventories/<env>/group_vars/all.yaml``:
```yaml
metallb_enabled: true
metallb_addresses: ['10.18.20.200-10.18.20.210']
```
Use free addresses in the service network that no VM uses. MetalLB runs in L2 mode, and only the ``kube_node`` hosts answer for the addresses (``metallb_l2_nodes``), so stopping a GPU node does not stop a LoadBalancer service.

To make it globally accessible from the outside of the mdx, please configure the DNAT and ACL entries from the mdx's user portal. This operation isn't needed when accessing services using SSH port forwarding.

### Using Knative Serving

Knative Serving and its ingress Kourier are off by default. Turn them on in ``group_vars/all.yaml`` and run the ``knative`` tag (after ``service``, which installs MetalLB):
```yaml
knative_enabled: true
knative_domain: knative.internal
kourier_lb_ip: 10.18.20.200   # optional, one of metallb_addresses
```
```sh
$ ./play.sh <env> --tags knative
```
The Kourier service gets a LoadBalancer address from MetalLB. A Knative service is reached through this address with the host name ``<service>.<namespace>.<knative_domain>`` in the ``Host`` header. Without ``knative_domain``, Knative uses ``svc.cluster.local``, and the services can be reached only from inside the cluster.

The role also sets the Knative ConfigMaps in ``knative_serving_config`` (``roles/knative/defaults/main.yaml``): for example node affinity, PVCs and priority classes in pod specs, and ``initial-scale: 0``.

### Using the entry proxy

The entry proxy is nginx on a VM with a global IP address (it can be the bastion host). It ends TLS with a Let's Encrypt certificate, checks the API key, and sends each path to a Knative service through Kourier. A request without a valid key gets 401 and never reaches Knative, so it cannot start a GPU pod.

Before you run it:
- Register the DNS name of the VM.
- In the mdx user portal, set the DNAT of the global IP address to the VM, and open TCP 80 and 443 in the ACL. Let's Encrypt checks the name over port 80 from addresses that are not published, so port 80 must be open to everyone. Port 80 serves only these checks and a redirect to https.

Put the VM in the ``[entry_proxy]`` group of ``hosts.ini``, and set the routes in ``group_vars/all.yaml`` (``kourier_lb_ip`` and ``knative_domain`` are also needed):
```yaml
entry_proxy_server_name: api.example.org
entry_proxy_routes:
  - path: model-a           # https://api.example.org/model-a/v1/...
    service: model-a-vllm   # Knative service in the namespace "default"
```
Set one or two API keys in ``vault.yaml``. Each key is 32 to 200 characters of letters, digits, ``_`` and ``-`` (for example from ``openssl rand -hex 32``). Use two keys to change a key without stopping the service: add the new key, change the clients, then remove the old key.
```yaml
entry_proxy_api_keys:
  - <key>
```
```sh
$ ./play.sh <env> --tags entry_proxy
```
The first run gets the certificate. certbot renews it with its systemd timer and reloads nginx after each renewal.

Clients send the key as ``Authorization: Bearer <key>``. The header is passed to the service, so you can also give the same key to the service (for example ``--api-key`` of vLLM) as a second check. ``https://<server_name>/healthz`` answers without a key, for monitoring.

### Running parallel jobs
Please refer the [MPI operator's document](https://github.com/kubeflow/mpi-operator).

### Running Spark applications
Please refer [Spark RAPIDS document](https://nvidia.github.io/spark-rapids/docs/get-started/getting-started-kubernetes.html).

## NUMA-aware resource management

The default playbook reserves the following resources for the underlying kubelet and system daemons. More specifically, it reserves a single CPU core and 1.1GB memory, and 2GB ephemeral storage for not using them to Kubernetes pods. If you want to run a Kubernetes cluster in more limited host resources or to change the management policies or the amount of reserved resources, change the ``k8s-configs/roles/k8s_worker/vars/main.yaml`` file accordingly.

```yaml
kubelet_extra_args: >-
  --topology-manager-scope=container
  --topology-manager-policy=single-numa-node 
  --cpu-manager-policy=static 
  --memory-manager-policy=Static 
  --kube-reserved=cpu=500m,memory=500Mi,ephemeral-storage=1Gi 
  --system-reserved=cpu=500m,memory=500Mi,ephemeral-storage=1Gi 
  --reserved-memory=0:memory=1100Mi
```

## Known issues and limitations

- Apache Spark jobs don't work properly due to bugs at this time.
- Virtual machines must be set up manually in the current mdx configuration.

## Future work
- Support for [Strimzi Kafka Operator](https://github.com/strimzi/strimzi-kafka-operator)
- Support for JupyterHub/BinderHub Operators
- Support for [MySQL Operator](https://github.com/mysql/mysql-operator)
- Support for other k8s distributions (such as [k3s](https://k3s.io/), [MicroK8s](https://microk8s.io/))
- Building a cluster of k8s clusters, like [Fleet](https://github.com/rancher/fleet)
- Data tranfer and processing from/to S3-compatible object storage
