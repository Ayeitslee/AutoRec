#!/bin/bash
# Run on a Mac or Linux box with Theos installed (https://theos.dev) and an iOS 15+ SDK in $THEOS/sdks
set -e
cd "$(dirname "$0")"
: "${THEOS:?Set THEOS first, e.g. export THEOS=~/theos}"
make clean package FINALPACKAGE=1
ls -1 packages/*.deb
