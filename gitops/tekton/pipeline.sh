#!/bin/bash
# This starts the pipeline new-pipeline with a given 

set -e -u -o pipefail
declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)
declare COMMAND="help"

GIT_URL=https://github.com/wpernath/grumpycat-config.git
GIT_REVISION=release-v0.6.x
PIPELINE=dev-pipeline
CONTEXT_DIR=.
IMAGE_NAME=quay.io/wpernath/quarkus-grumpycat
TARGET_NAMESPACE=cat-ci

valid_command() {
  local fn=$1; shift
  [[ $(type -t "$fn") == "function" ]]
}

info() {
    printf "\n# INFO: $@\n"
}

err() {
  printf "\n# ERROR: $1\n"
  exit 1
}

command.help() {
  cat <<-EOF
  Starts a new pipeline in current kubernetes context

  Usage:
      pipeline.sh [command] [options]
  
  Examples:
      pipeline.sh init
      pipeline.sh build-all -r <source-branch>
      pipeline.sh build-client -r <source-branch>
      pipeline.sh build-server -r <source-branch>

      pipeline.sh stage-all -r v1.2.5 
      pipeline.sh stage-client -r v1.2.5 [-g <config-git-rep>] 
      pipeline.sh stage-server -r v1.2.5 [-g <config-git-rep>] 
      pipeline.sh logs [-t <target-namespace]
  
  COMMANDS:
      init                           creates ConfigMaps, Tasks and Pipelines in cat-ci (create Secrets separately)
      build-all                      starts both build pipelines as a pipeline
      build-client                   starts the client-dev-pipeline in $TARGET_NAMESPACE      
      build-server                   starts the dev-pipeline in $TARGET_NAMESPACE
      stage-all                      starts both stage pipelines as a pipeline
      stage-server                   starts the stage-pipeline in $TARGET_NAMESPACE
      stage-client                   starts the client-stage-pipeline in $TARGET_NAMESPACE
      logs                           shows logs of the last pipeline run in $TARGET_NAMESPACE
      help                           Help about this command

  OPTIONS:
      -i, --target-image            Target image name to push to ($IMAGE_NAME)
      -c, --context-dir             Which context-dir to user ($CONTEXT_DIR)
      -t, --target-namespace        Which target namespace to start the app ($TARGET_NAMESPACE)
      -g, --git-repo                Which quarkus repository to clone ($GIT_URL)
      -r, --git-revision            Which git revision to use ($GIT_REVISION)
EOF
}

while (( "$#" )); do
  case "$1" in
    build-client|stage-client|logs|init|build-server|stage-server|build-all|stage-all)
      COMMAND=$1
      shift
      ;;
    -c|--context-dir)
      CONTEXT_DIR=$2
      shift 2
      ;;
    -i|--target-image)
      IMAGE_NAME=$2
      shift 2
      ;;
    -t|--target-namespace)
      TARGET_NAMESPACE=$2
      shift 2
      ;;
    -g|--git-repo)
      GIT_URL=$2
      shift 2
      ;;
    -r|--git-revision)
      GIT_REVISION=$2
      shift 2
      ;;
    -l|--pipeline)
      PIPELINE=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*|--*)
      command.help
      err "Error: Unsupported flag $1"
      ;;
    *) 
      break
  esac
done


command.init() {
  oc apply -k "$SCRIPT_DIR"
}


command.logs() {
    tkn pr logs -f -L -n $TARGET_NAMESPACE
}

command.stage-server() {
  info "Start staging server service on OpenShift..."
  tkn pipeline start stage-server \
            -s pipeline-bot \
            -p release-name=$GIT_REVISION \
            -w name=shared-workspace,claimName=builder-pvc \
            --use-param-defaults

}

command.build-server() {
  info "Start building server service on OpenShift..."
  tkn pipeline start build-server -s pipeline-bot \
            -p git-revision=$GIT_REVISION \
            -w name=source,claimName=builder-pvc \
            -w name=maven-settings,config=maven-settings \
            --use-param-defaults
}

command.stage-client() {
  info "Start staging client on OpenShift..."
  tkn pipeline start stage-client \
            -s pipeline-bot \
            -p release-name=$GIT_REVISION \
            -w name=shared-workspace,claimName=client-builder-pvc \
            --use-param-defaults

}

command.build-client() {
  info "Start building client on OpenShift..."
  tkn pipeline start build-client -s pipeline-bot \
            -p git-revision=$GIT_REVISION \
            -w name=source,claimName=client-builder-pvc \
            -w name=maven-settings,config=maven-settings \
            --use-param-defaults
}


command.build-all() {
  info "Starting build-all pipeline..."
  tkn pipeline start build-all -s pipeline-bot \
               -p git-revision=$GIT_REVISION \
               --use-param-defaults
}

command.stage-all() {
  info "Starting stage-all pipeline..."
  tkn pipeline start stage-all -s pipeline-bot \
                -p release-name=$GIT_REVISION
}

main() {
  local fn="command.$COMMAND"
  valid_command "$fn" || {
    command.help
    err "invalid command '$COMMAND'"
  }

  cd $SCRIPT_DIR
  $fn
  return $?
}

main
