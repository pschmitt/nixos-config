#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  killall slurp still # swappy

  still -c 'slurp | grim -g- -' | swappy -f -
fi
