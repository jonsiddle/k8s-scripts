# k8s-scripts

## `provision-1n-k8s.sh` - provision a single node k8s cluster

1. Log in to the node to be
2. run::
```bash
curl -fsSL https://raw.githubusercontent.com/jonsiddle/k8s-scripts/main/provision-1n-k8s.sh | bash
```
3. Follow the on-screen promps and watch for errors
4. Check your cluster is running reliably:
```bash
while true ; do sleep 1 ; kubectl get pods ; done
```

### Troubleshooting

You will get sporadic connection issues for step 4 if you select docker as the CRI on Debian 12 (bookworm). I don't know why.
