#!/bin/bash

#TODO: find good example data. modify to run human and mouse in same command. fix preseq legend issue.

# example Usage:
# USE_DOCKER=true ./runATACPipeline.sh ./inputData/mouse mm9

# update the docker image (if needed)
[ "$USE_DOCKER" = true ] && docker pull greyson/pipelines

# NOTE: If you get an error here: "FATA[0002] Error: image greyson/pipelines:latest not found" then make sure
# A: you're logged in with your docker user (run `docker login`)
# and
# B: Your docker user has permission to download the greyson/pipelines image (email grey@christoforo.net to ask)

BASEDIR="$(dirname $(realpath $0))"

# path to directory containing vplot index files
VINDEX_DIR="${BASEDIR}/vPlotIndex/"

# path to pipelines repo directory
PIPELINES_REPO="${BASEDIR}/pipelines/"

# path to directory containing size files
SIZE_FILES="${BASEDIR}/genomeSize/"

# path to bowtie 2 index directory
BT2INDEX_DIR="${BASEDIR}/bowtie2Index/"

# here is a folder that will get filled with directories containing output files for each experiment
OUTPUT_DIR="${BASEDIR}/ATACPipeOutput/"

# this folder should contain one or more folders each containing two fastq files
INPUT_DIR=$(realpath $1)

# genome model to match against (could be mm9 or hg19, etc.)
#GENOME_MODEL=mm9
GENOME_MODEL=$2
GENDER=male

# threads to use for alignment
THREADS=4
#THREADS=$(nproc)

# the following is generally not user editable

if [[ $GENOME_MODEL == *"hg"* ]]; then
  MODEL=hs
elif [[ $GENOME_MODEL == *"mm"* ]]; then
  MODEL=mm
else
  echo "Could not match genome model"
  exit 1
fi

# add the pipeline scripts to PATH
if [ "$USE_DOCKER" != true ] ; then
  export PATH=$PATH:"${PIPELINES_REPO}"/atac
fi

VINDEXFILE="${VINDEX_DIR}"/knownGene_${GENOME_MODEL}vPlotIndex.bed
SIZEFILE="${SIZE_FILES}"/${GENOME_MODEL}.genome
BT2INDEX="${BT2INDEX_DIR}"/${GENOME_MODEL}/${GENDER}/${GENOME_MODEL}${GENDER}

for DATAPATH in "${INPUT_DIR}"/*/ ; do
  echo
  echo "Processing ${DATAPATH}"

  # compute some pipleine variables
  DATA_FOLDER=$(basename "${DATAPATH}")
  OUTPUT_FOLDER="${OUTPUT_DIR}"/"${DATA_FOLDER}".output

  # delete the output folder (if it exists before we start)
  rm -rf "${OUTPUT_FOLDER}"

  # input data files MUST have "R1" or "R2" before "fastq" in their file names
  READ1FILE=$(find "${DATAPATH}" -type f -name *R1*fastq*)
  echo "Found read #1 input file: $READ1FILE"
  READ2FILE=$(find "${DATAPATH}" -type f -name *R2*fastq*)
  echo "Found read #2 input file: $READ2FILE"

  # run the atac pipeline
  if [ "$USE_DOCKER" = true ] ; then
    DOCKER_TEXT="(inside a Docker container) "
    docker stop atac >/dev/null 2>/dev/null
    docker rm atac >/dev/null 2>/dev/null
    DOCKER_OPTS="-v ${BT2INDEX_DIR}:${BT2INDEX_DIR} -v ${READ1FILE}:${READ1FILE} -v ${READ2FILE}:${READ2FILE} -v ${SIZEFILE}:${SIZEFILE} -v ${VINDEXFILE}:${VINDEXFILE} --name atac -t greyson/pipelines"
    DOCKER_PREFIX="docker run ${DOCKER_OPTS}"
    echo
    echo "A Docker container will be used here. It will be run/setup in the following way:"
    eval echo "$DOCKER_PREFIX"
    echo
    echo "To enter the container interactively, use:"
    eval echo "docker run -i ${DOCKER_OPTS} bash"
  fi
  RUN_PIPELINE='ATACpipeline.sh "${BT2INDEX}" "${READ1FILE}" "${READ2FILE}" ${THREADS} ${MODEL} "${SIZEFILE}" "${VINDEXFILE}" "${OUTPUT_FOLDER}"'
  
  echo
  echo "Now running the ATAC-Seq Pipeline ${DOCKER_TEXT}with the following command:"
  eval echo "${RUN_PIPELINE}"
  echo
  eval ${DOCKER_PREFIX} ${RUN_PIPELINE}

  [ "$USE_DOCKER" = true ] && docker cp atac:"${OUTPUT_FOLDER}" "${OUTPUT_FOLDER}" 
  chmod -R o+r "${OUTPUT_FOLDER}"
done


realpath() {
    canonicalize_path "$(resolve_symlinks "$1")"
}

resolve_symlinks() {
    local dir_context path
    path=$(readlink -- "$1")
    if [ $? -eq 0 ]; then
        dir_context=$(dirname -- "$1")
        resolve_symlinks "$(_prepend_path_if_relative "$dir_context" "$path")"
    else
        printf '%s\n' "$1"
    fi
}

_prepend_path_if_relative() {
    case "$2" in
        /* ) printf '%s\n' "$2" ;;
         * ) printf '%s\n' "$1/$2" ;;
    esac 
}

canonicalize_path() {
    if [ -d "$1" ]; then
        _canonicalize_dir_path "$1"
    else
        _canonicalize_file_path "$1"
    fi
}   

_canonicalize_dir_path() {
    (cd "$1" 2>/dev/null && pwd -P) 
}           

_canonicalize_file_path() {
    local dir file
    dir=$(dirname -- "$1")
    file=$(basename -- "$1")
    (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$file")
}
