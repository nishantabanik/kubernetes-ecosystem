1. Add the OPA Helm Chart
```
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
```

2. Install the OPA Helm Chart
```
helm install gatekeeper/gatekeeper --name-template=gatekeeper --namespace gatekeeper-system --create-namespace
```

OR

```
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
```

3. Confirm that all Kubernetes resources were deployed.
```
kubectl get all -n gatekeeper-system
```

## Deploy and implement OPA policies

1. The config is your definition of what Gatekeeper is allowed to create policies for. For example, in the config.yaml below, Gatekeeper knows that it can only specify Policies for Pods, but no other Kubernetes resources.

```
kubectl create -f - <<EOF
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: "gatekeeper-system"
spec:
  sync:
    syncOnly:
      - group: ""
        version: "v1"
        kind: "Pod"
EOF
```

2. The Constraint Template is the rule/policy that you want to configure for your environment. It's a template, so you can use it across multiple constraints.

For example, there's a Rego policy in the constraint template in this directory that ensures no one can utilize the latest tag of a container image.

```
kubectl create -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: blocklatesttag
  annotations:
    description: Blocks container images from using the latest tag
spec:
  crd:
    spec:
      names:
        kind: blocklatesttag # this must be the same name as the name on metadata.name (line 4)
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package blocklatesttag
        violation[{"msg": msg, "details": {}}]{
        input.review.object.kind == "Pod"
        imagename := input.review.object.spec.containers[_].image
        endswith(imagename,"latest")
        msg := "Images with tag the tag \"latest\" is not allowed"
        }
EOF
```

3. The constraint itself is taking the template that you created above and bringing it to life. It allows you to utilize the template to create your own policy inside of a Kubernetes cluster.

```
kubectl create -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: blocklatesttag
metadata:
  name: nolatestcontainerimage
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    annotation: "no-latest-tag-used"
EOF
```

4. To confirm that the OPA policy that you implemented works, you can test it out with the two Kubernetes Manifests below.

The Manifest with the latest tag won’t work because you created a policy in the previous step to ensure that latest tags cannot be used. The deployment itself will deploy, but the Pods won’t come online.

Try running the below.

```
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginxdeployment
  replicas: 2
  template:
    metadata:
      labels:
        app: nginxdeployment
    spec:
      containers:
      - name: nginxdeployment
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
```

5. Wait a few minutes and when you see that it doesn't come online, delete it.
```
kubectl delete deployment nginx-deployment
```

6. The Manifest below will work and the Pods will come online because a container image version number is specified.
```
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginxdeployment
  replicas: 2
  template:
    metadata:
      labels:
        app: nginxdeployment
    spec:
      containers:
      - name: nginxdeployment
        image: nginx:1.23.1
        ports:
        - containerPort: 80
EOF
```