#!/bin/bash

sudo gem install cfn-nag -v 0.3.54
cfn_nag_scan --input-path ./cloudformation
