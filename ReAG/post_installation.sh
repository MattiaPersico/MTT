#!/bin/bash

REAG_DIR="/Applications/ReAG_Environment"

chmod -R u+rwx "$REAG_DIR"

spctl --add --recursive "$REAG_DIR"

source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate