# GitOps Setup
You have to do the following three steps in order to setup the environment. 
If you want to understand what is going on here, please have a look at the following book, which you can download for free [here](https://developers.redhat.com/e-books/getting-gitops-practical-platform-openshift-argo-cd-and-tekton)

## 1. Prepare your environment

### a. forking git repositories
Please make sure that you're forking the following two repositories on GitHub.com
- (Source Code)[https://github.com/wpernath/quarkus-grumpycat]
- (Configuration)[https://github.com/wpernath/grumpycat-config]

### b. prepare pipelines
Then you have to make sure that all the defaults are pointing to YOUR repositories:
```
FOR EACH pipeline in ${gitops/tekton/pipelines} DO
  spec.params.git-url -> your forked git url
  spec.params.config-git-url -> your forked git url
  spec.params.image-name -> your quay.io or dockerhub.io repository name
END
```

OR 

You can enhance `gitops/tekton/pipeline.sh` to let you specify those parameters accordingly.

### c. prepare argo cd applications
Finally, you have to open `gitops/argocd/cat-apps.yaml` and

```
FOR EACH $(argocd application in cat-apps.yaml) DO
  spec.source.repoURL -> your grumpycat config repository
END
```


## 2. Setup Tekton Pipelines (the CI part)

From `gitops/tekton`, run `./pipeline.sh init` to install the `cat-ci` namespace, Tasks, Pipelines and `pipeline-bot` ServiceAccount. It does **not** create Secrets. Never put credentials into `infra/secret.yaml` or a public fork.

Create a Quay robot account with write access to your image repository. Its username is usually `your-quay-account+robot-name`; use its token, not your Quay login password. After logging in with `oc`, create the Secret in `cat-ci` without putting the token in your command history or a local file:

```bash
read -rsp 'Quay robot token: ' QUAY_TOKEN; printf '\n'
printf '%s' "$QUAY_TOKEN" | oc -n cat-ci create secret generic quay-push-secret \
  --type=kubernetes.io/basic-auth \
  --from-literal=username='YOUR_QUAY_ROBOT_USERNAME' \
  --from-file=password=/dev/stdin
unset QUAY_TOKEN
oc -n cat-ci annotate secret quay-push-secret tekton.dev/docker-0=https://quay.io
```

Both build pipelines read this Secret in the Maven step; the staging pipelines' `skopeo-copy` task uses it via `pipeline-bot`. No password is passed as a pipeline parameter. For the GitOps update step, create a separate GitHub fine-grained token with **Contents: read/write** access to your `grumpycat-config` fork (the public source fork needs no write access):

```bash
read -rsp 'GitHub token: ' GITHUB_TOKEN; printf '\n'
printf '%s' "$GITHUB_TOKEN" | oc -n cat-ci create secret generic git-user-pass \
  --type=kubernetes.io/basic-auth \
  --from-literal=username='YOUR_GITHUB_USERNAME' \
  --from-file=password=/dev/stdin
unset GITHUB_TOKEN
oc -n cat-ci annotate secret git-user-pass tekton.dev/git-0=https://github.com
```

If you run `build-all`, its Argo CD sync Task also needs these resources in `cat-ci` (the server value is a hostname, without `https://`):

```bash
oc -n cat-ci create configmap argocd-env-configmap --from-literal=ARGOCD_SERVER='YOUR_ARGO_HOST'
read -rsp 'Argo CD password: ' ARGO_PASSWORD; printf '\n'
printf '%s' "$ARGO_PASSWORD" | oc -n cat-ci create secret generic argocd-env-secret \
  --from-literal=ARGOCD_USERNAME=admin \
  --from-file=ARGOCD_PASSWORD=/dev/stdin
unset ARGO_PASSWORD
```



## 3. Setup ArgoCD Applications (the CD part)

To initialize the ArgoCD part, call the following

```bash
$ oc apply -k gitops/argocd
```

This will create two namespaces with all roles properly setup so that Argo CD can then start initializing the environment. It will take a while until you're able to see the `cat-dev` and `cat-stage` namespaces with the two versions of the app deployed in. 

## Calling the pipelines

In order to call one of the build pipelines in `cat-ci`, either call 

```bash
./pipeline.sh build-client -r main
```

or 
```bash
./pipeline.sh build-server -r main
```


This starts the development pipelines as discussed in chapter 5. Whenever the pipeline is successfully executed, you should see an updated message on the `grumpycat-config` Git repository. And you should see that ArgoCD has initiated a synchronization process, which ends with a redeployment of the Quarkus application.

To start one of the staging pipelines, either call
```bash
$ ./pipeline.sh stage-client -r v1.0.1-testing
```

or

To start one of the staging pipelines, either call
```bash
$ ./pipeline.sh stage-server -r v1.0.1-testing
```

This creates a new branch in Git called `release-v1.0.1-testing`, uses the current DEV image, tags it on quay.io and updates the `stage` config in git. 

In order to apply the changes, you need to either merge the branch directly or create a pull request and merge the changes then. 

## Starting client-dev and server-dev pipelines as a pipeline
If you want to start the `build-all` pipeline, you just have to call `tkn` with the following arguments

```shell
tkn p start build-all -s pipeline-bot --use-param-defaults
```

This starts the dev-pipeline and the client-dev-pipeline and waits for both until they are done. It's then telling ArgoCD to do a redeployment of the `cat-dev` app.
