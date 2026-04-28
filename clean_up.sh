#!/bin/bash
#
# Clean up Docker and the working directory for the lab
# !!! DESTRUCTIVE, READ THE SCRIPT FIRST !!!

docker ps -q | xargs -r docker stop # stop running containers
docker system prune -af --volumes   # remove all unused resources
docker image prune -af              # remove all unused images

# list everything
docker ps -a
docker volume ls
docker network ls
docker images

# clean up the environment, remove entries from known_hosts
rm -rfv ~/.ssh/glab-task*
rm -rfv ./hometask/
> ~/.ssh/known_hosts
