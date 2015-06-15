#!/bin/bash

# Usage:
# 1. place your fastq data files in to the inputData folder (as described below)
# 2. (optional) delete the example data files
# 3. run the pipeline by executing ./runATACPipeline.sh in your terminal
# 4. look for results to appear in a folder called ATACPipeOutput (the report .pdf file is probably what you want)

# NOTE: If you get an error when updating the docker image:
# "FATA[0002] Error: image greyson/pipelines:latest not found"
# then make sure that
# A: you're logged in with your docker user (run `docker login`)
# and
# B: Your docker user has permission to download the greyson/pipelines image (email grey@christoforo.net to ask)

# Setup some defaults
: ${USE_DOCKER:=true}
: ${MOUSE_MODEL:="mm9"}
: ${HUMAN_MODEL:="hg19"}
: ${GENDER:="male"}

# pull the latest docker image (if needed)
[ "$USE_DOCKER" = true ] && docker pull greyson/pipelines

# this is the absolute path to the directory of this script
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"

# this folder should contain subfolder(s) with named according to the species to be processed, i.e. "human and/or mouse"
# you put folders containing your two fastq input data files into these species folders
# each of the two fastq file names you use must uniquely match the patterns "*R1*fastq*" and "*R2*fastq*"
# so an example would be putting your two fastq input data files in a folder structure like this:
# inputData/mouse/trialA/billyTheMouse_R1_brain.fastq.gz
# inputData/mouse/trialA/billyTheMouse_R2_brain.fastq.gz
: ${DATA_FLDR:="${BASEDIR}/inputData"}

# path to directory containing vplot index files
: ${VINDEX_DIR:="${BASEDIR}/vPlotIndex"}

# path to pipelines repo directory (unused if running in docker mode)
: ${PIPELINES_REPO:="${BASEDIR}/pipelines"}

# path to directory containing size files
: ${SIZE_FILES:="${BASEDIR}/genomeSize"}

# path to bowtie 2 index directory
: ${BT2INDEX_DIR:="${BASEDIR}/bowtie2Index"}

# here is a folder that will get filled with directories containing output files for each experiment
: ${OUTPUT_DIR:="${BASEDIR}/ATACPipeOutput"}

# cpu threads to use
: ${THREADS:=4}
#THREADS=$(nproc)

#===========probably don't edit below here==========

# add the pipeline scripts to PATH
if [ "$USE_DOCKER" != true ] ; then
  export PATH=$PATH:"${PIPELINES_REPO}"/atac
fi

function process_data {
  echo "Processing $SPECIES_DIR..."
  for DATAPATH in "${SPECIES_DIR}"/*/ ; do
    echo
    echo "Found ${DATAPATH}"
    READ1FILE="$(find "${DATAPATH}" -type f -name *R1*fastq*)"
    echo "Using read #1 input file: $READ1FILE"
    READ2FILE="$(find "${DATAPATH}" -type f -name *R2*fastq*)"
    echo "Using read #2 input file: $READ2FILE"
    if [ -f "$READ1FILE" ] && [ -f "$READ2FILE" ]; then
      # compute some pipleine variables
      DATA_FOLDER="$(basename "${DATAPATH}")"
      OUTPUT_FOLDER="${OUTPUT_DIR}/${SPECIES}/${DATA_FOLDER}".output
      echo "Results will be stored in ${OUTPUT_FOLDER}"

      # delete the output folder (if it exists before we start)
      rm -rf "${OUTPUT_FOLDER}"

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
          #echo
          #echo "To enter the container interactively, use:"
          #eval echo "docker run -i ${DOCKER_OPTS} bash"
        fi
        RUN_PIPELINE='ATACpipeline.sh "${BT2INDEX}" "${READ1FILE}" "${READ2FILE}" ${THREADS} ${MODEL} "${SIZEFILE}" "${VINDEXFILE}" "${OUTPUT_FOLDER}"'

        echo
        echo "Now running the ATAC-Seq Pipeline ${DOCKER_TEXT}with the following command:"
        eval echo "${RUN_PIPELINE}"
        echo
        eval ${DOCKER_PREFIX} ${RUN_PIPELINE}

        [ "$USE_DOCKER" = true ] && docker cp atac:"${OUTPUT_FOLDER}" "${OUTPUT_DIR}/${SPECIES}" && chmod -R o+r "${OUTPUT_FOLDER}"
    else
      echo "Could not use the two input fastq data files."
    fi
  done
}

declare -a SPECIESES=("mouse" "human")
for SPECIES in "${SPECIESES[@]}"; do
  SPECIES_DIR="$DATA_FLDR/$SPECIES"
  if [ -d "$SPECIES_DIR" ]; then
    if [ "$SPECIES" = "mouse" ]; then
      GENOME_MODEL=$MOUSE_MODEL
      MODEL=mm
    fi
    if [ "$SPECIES" = "human" ]; then
      GENOME_MODEL=$HUMAN_MODEL
      MODEL=hs
    fi
    if [ -z "$MODEL" ]; then
      echo "$SPECIES not supported, skipping."
    else
      VINDEXFILE="${VINDEX_DIR}"/knownGene_${GENOME_MODEL}vPlotIndex.bed
      SIZEFILE="${SIZE_FILES}"/${GENOME_MODEL}.genome
      BT2INDEX="${BT2INDEX_DIR}"/${GENOME_MODEL}
      process_data
    fi
  else
    echo "$SPECIES_DIR does not exist, skipping"
  fi
done
