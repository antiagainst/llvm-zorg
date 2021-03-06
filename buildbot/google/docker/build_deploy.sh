#!/bin/bash
#===-- build_deploy.sh ---------------------------------------------------===//
# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
#===----------------------------------------------------------------------===//
# This script will deploy a docker image to the registry.
# Arguments: <path to Dockerfile> 
# 
# This updates the `VERSION` file with the latest version number.
#===----------------------------------------------------------------------===//

set -eu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
IMAGE_NAME="${1%/}"

# increment version number
cd "${DIR}/${IMAGE_NAME}"

# get version numbers from repository
# FIXME: use variables to configure URL
ALL_VERSIONS=$(gcloud container images list-tags gcr.io/sanitizer-bots/${IMAGE_NAME} --format=text | \
  awk '/tags.*:\W+[0-9]+$/ {print $2}')
# read local version number from file and add it to the array
ALL_VERSIONS+=($(cat VERSION))
# find maximum version number and increment it
VERSION=$(echo "${ALL_VERSIONS[*]}" | sort -nr | head -n1)
VERSION=$(( ${VERSION} + 1 ))

# get the git hash and add some suffixes
GIT_HASH=$(git rev-parse HEAD)
if [[ $(git diff --stat) != '' ]]; then
  # if working copy is dirty
  GIT_HASH+="-dirty-${USER}"
elif [[ $(git --no-pager diff origin/master | wc -l) > 0 ]]; then
  # if the hash has not been uploaded to origin/master yet
  GIT_HASH+="-local-${USER}"
fi

# fully qualified image name
# FIXME: use variables to configure URL
QUALIFIED_NAME="gcr.io/sanitizer-bots/${IMAGE_NAME}"
# tags to be added to the image and pushed to the repository
TAGS=(
  "${QUALIFIED_NAME}:latest" 
  "${QUALIFIED_NAME}:${VERSION}"
  "${QUALIFIED_NAME}:${GIT_HASH}"
  )

# build the image and tag it locally
docker build -t ${IMAGE_NAME}:latest -t ${IMAGE_NAME}:${VERSION} .

# print the list of tags to be pushed
echo "-----------------------------------------"
echo "image version: ${VERSION}"
echo "tags:"
printf '   %s\n' "${TAGS[@]}"
echo "-----------------------------------------"
read -p "Push to registry? [yN]" -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
  for TAG in "${TAGS[@]}"
  do
    docker tag ${IMAGE_NAME}:${VERSION} "${TAG}"
    docker push "${TAG}"
  done
  # store the version number
  echo "${VERSION}" > VERSION
fi
