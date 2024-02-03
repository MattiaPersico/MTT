#!/bin/bash

dir1="/Applications/ReAG_Environment"

if [ -d "$dir1" ]; then
    source "$dir1/AG_P3Env_02/bin/deactivate"
    rm -rf "$dir1"
fi