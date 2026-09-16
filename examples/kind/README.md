# Kind

A one-replica setup on a local [kind cluster](https://kind.sigs.k8s.io/). This setup provides a quick way to demonstrate SurrealDB running with a TiKV backend without fully deploying on infrastructure. Best for testing chart configurations.

### Prerequisites

- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Helm v4](https://helm.sh/docs/intro/install/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)

### Setup

1. Start a kind cluster with the [kind configuration](./kind-config.yaml).
```bash
kind create cluster --config ./kind-config.yaml
```

2. Set up the environment. Alias allows us from retyping variables on each line.
```bash
alias k="kubectl"
alias h="helm"
```

3. Check the environment
```bash
k get ns
```
```text
NAME                 STATUS   AGE
default              Active   40s
kube-node-lease      Active   40s
kube-public          Active   40s
kube-system          Active   40s
local-path-storage   Active   30s
```

## Deploy TiDB Operator

1. Install CRDS
```bash
k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.crds.yaml --server-side
```

2. Install the TiDB Operator from the GitHub release manifest instead of the Helm repo index:
```bash
k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.yaml --server-side
```

3. Verify that the Pods are running (tip: add the `--watch` command to wait for changes.)
```bash
k get pods -n tidb-admin
```
```text
NAME                          READY   STATUS    RESTARTS   AGE
tidb-operator-xxx             1/1     Running   0          20s
```

## Create TiKV Cluster

Now that we have the TiDB Operator running, it's time to define a TiKV Cluster and let the Operator do the rest.

1. Install the cluster chart from the example directory.
```bash
h upgrade --install cluster ./charts/cluster -n surreal-cluster --create-namespace
```

2. Install the PD group chart.
```bash
h upgrade --install pd-group ./charts/pd-group -n surreal-cluster
k get pdgroup -n surreal-cluster
```
```text
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
pd     sdb-datastore   1         1       1         pd-pd-xxx          pd-pd-xxx          True     True    40s
```

3. Install the TiKV group chart.
```bash
h upgrade --install tikv-group ./charts/tikv-group -n surreal-cluster
k get tikvgroup -n surreal-cluster
```
```text
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
tikv   sdb-datastore   1         1       1         tikv-tikv-xxx      tikv-tikv-xxx      True     True    60s
```

4. Check the cluster status and wait until it's ready (all ready and running).
```bash
k get pods -n surreal-cluster
```
```text
NAME              READY     STATUS    RESTARTS   AGE
pd-pd-xxx         1/1       Running   0          2m
tikv-tikv-xxx     1/1       Running   0          75s
```

## Deploy SurrealDB

Now that we have a TiDB cluster running, we can deploy SurrealDB using the Helm chart included in this repository under [charts/surrealdb](./charts/surrealdb). The chart is configured to connect to the TiKV PD service and exposes the SurrealDB service through the GKE NEG.

1. Copy the surrealdb values file locally. Replace values as needed, such as version.
```bash
cp ./charts/surrealdb/values.example.yaml values.local.yaml
```

2. Install the chart from the repository checkout.
```bash
h repo add surrealdb https://helm.surrealdb.com
h repo update
h upgrade --install -f values.local.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
```

3. Check the deployment status to check everything is ready.
```bash
k get deployment -n surreal-cluster
```
```text
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
surrealdb   1/1     1            1           5s
```

## Test setup

1. Forward port 8000 to the service
```bash
k port-forward svc/surrealdb 8000:8000 -n surreal-cluster
```

2. In a new terminal, connect to the SurrealDB instance
```bash
surreal sql -u root -p root -e http://localhost:8000
```

3. Verify persistence
```surrealql
USE NS ns DB db;
CREATE record SET id = record:one;
SELECT * FROM record;
```

4. Disconnect the port forward then delete the SurrealDB pod and confirm data survives on the PVC:
```bash
k get pod -n surreal-cluster
```
```text
NAME            READY   STATUS    RESTARTS   AGE
surrealdb-xxx   1/1     Running   0          1m
```
```bash
k delete pod surrealdb-xxx -n surreal-cluster
```

5. Wait until the pod is remade, then reconnect and confirm data survived
```surrealql
USE NS ns DB db;
SELECT * FROM record;
```

## Clean up

Clean up is simple with Kind.

```bash
kind delete cluster
```

## Authors
[Dylan Vanmali](https://github.com/dvanmali)

## Contributing
See [Contribution Guidelines](../../CONTRIBUTING.md)

## License
[Apache 2.0](../../LICENSE)

## Closing

This setup took many hours of development, so if you found this following repository helpful or if you used this in your deployment, please feel free to donate or give a star :star:

<a href="https://ko-fi.com/dvanmali" target="_blank">
  <img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Support me on Ko-fi" height="35" />
</a>

Thanks! :heart: :heart: :heart: