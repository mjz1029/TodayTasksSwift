#!/bin/bash
# 跑核心库测试。
#
# 两个 CLT（只装 Command Line Tools、没装 Xcode）专属的坑：
# 1) XCTest 不随 CLT 分发，所以测试统一用 swift-testing（import Testing）。
# 2) swift-testing 的宏插件在 CLT 下加载存在竞态，偶发报
#      "plugin for module 'TestingMacros' not found"
#    同一份代码重试即过（实测多次里会踩 1-2 次），因此这里只在识别到该构建错误时重试，
#    真正的测试失败照常立刻退出，不会被重试掩盖。
set -uo pipefail
export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"
cd "$(dirname "$0")"

MAX_ATTEMPTS=6
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  rm -rf .build
  output=$(swift test "$@" 2>&1)
  code=$?
  echo "$output" | grep -vE "^\[[0-9]+ ?/ ?[0-9]+\]"

  if [[ "${output}" != *"plugin for module 'TestingMacros' not found"* ]]; then
    if [ "${code}" -eq 0 ]; then
      if [ "${attempt}" -gt 1 ]; then
        echo "（第 ${attempt} 次才通过：CLT 宏插件竞态，非代码问题）"
      fi
      exit 0
    fi
    echo "测试失败，退出码 ${code}"
    exit "${code}"
  fi
  echo "— 宏插件加载失败，重试（${attempt}/${MAX_ATTEMPTS}）"
done

echo "多次重试仍未通过，CLT 的 swift-testing 插件环境有问题；装好 Xcode 后改用 xcodebuild 跑测试。"
exit 1
