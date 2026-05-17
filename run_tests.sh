#!/bin/bash
exec > /tmp/quant_test_output.txt 2>&1
cd ~/Developer/Quant
xcodebuild test \
  -project Quant.xcodeproj \
  -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5' \
  -only-testing:QuantTests/NudgeInsightsTests
echo "EXIT_CODE=$?"
