# Cinder CSI Argo CD Application

## Secret prerequisite

Before syncing this Application, the cluster must contain:

```text
Secret/cinder-csi-cloud-config
```

in `kube-system`, with a `cloud.conf` key containing valid OpenStack Cinder CSI credentials.

The secret is intentionally not stored in this directory in plaintext.

## Application sources

The Argo Application has two sources:

1. The upstream `openstack-cinder-csi` Helm chart from `https://kubernetes.github.io/cloud-provider-openstack`.
2. This Git repository's `argocd/applications/cinder-csi/resources` directory for the Git-managed StorageClasses.

This is an intentional multi-source Application: Helm owns the CSI driver; Git owns the storage policy resources.

## Bootstrap

After Argo CD is installed and the credential Secret exists:

```bash
kubectl apply -f argocd/applications/cinder-csi/application.yaml
```

Then inspect:

```bash
kubectl -n argocd get application cinder-csi
kubectl -n kube-system get pods -l app.kubernetes.io/name=openstack-cinder-csi
kubectl get csidriver cinder.csi.openstack.org
kubectl get storageclass
```

Once a root App-of-Apps is established, this `Application` itself should also be managed by Argo CD rather than applied manually.
