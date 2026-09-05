#!/bin/bash

# Enable Gemini in Chrome (macOS & Linux)
# Ported from apintocr's install.ps1 logic with Chrome 152+ fixes

set -e

echo ""
echo "🚀 Gemini in Chrome Enabler (macOS & Linux)"
echo ""

# 1. 检测操作系统并定位 Chrome 数据目录
OS_TYPE=$(uname -s)
case "$OS_TYPE" in
    Darwin)
        CHROME_USER_DATA="$HOME/Library/Application Support/Google/Chrome"
        CHROME_PROCESS="Google Chrome"
        FIRST_LAUNCH_CMD="open -a 'Google Chrome' --args --enable-features=Glic --force-variations-country=US"
        ;;
    Linux)
        CHROME_USER_DATA="$HOME/.config/google-chrome"
        CHROME_PROCESS="chrome"
        FIRST_LAUNCH_CMD="google-chrome --enable-features=Glic --force-variations-country=US &"
        ;;
    *)
        echo "❌ 不支持的操作系统: $OS_TYPE"
        exit 1
        ;;
esac

CHROME_STATE="$CHROME_USER_DATA/Local State"

# 2. 检查 Chrome 是否正在运行
check_chrome_running() {
    pgrep -x "$CHROME_PROCESS" > /dev/null 2>&1
}

if check_chrome_running; then
    echo "⚠️  Chrome 正在运行！"
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        echo "📌 请先彻底退出 Chrome (Cmd + Q)，然后再继续。"
    else
        echo "📌 请先完全关闭 Chrome，然后再继续。"
    fi
    echo ""
    read -p "关闭 Chrome 后按回车键继续... " -r
    echo ""

    if check_chrome_running; then
        echo "❌ Chrome 仍在运行，请彻底退出后重新运行脚本。"
        exit 1
    fi
fi

# 3. 检查 Local State 是否存在
if [ ! -f "$CHROME_STATE" ]; then
    echo "❌ 未找到 Chrome 配置文件: $CHROME_STATE"
    echo "   请先启动一次 Chrome 生成初始配置。"
    exit 1
fi

# 4. 备份 Local State
cp "$CHROME_STATE" "$CHROME_STATE.bak"
echo "✓ 已备份原始文件: Local State.bak"

# 5. [核心改动 1] 删除本地 Variations 种子缓存文件
# 对照 install.ps1 的删除逻辑，扩展通配符以同时清除 Chrome 152 的 VariationsSeedV2 / VariationsSafeSeedV2
deleted_count=0
for var_file in "$CHROME_USER_DATA"/Variations*; do
    if [[ -f "$var_file" && "$var_file" != *".bak" ]]; then
        rm -f "$var_file"
        ((deleted_count++)) || true
    fi
done

if [ $deleted_count -gt 0 ]; then
    echo "✓ 已清除本地缓存的 Variations 种子文件 (强制拉取全新美区种子)"
else
    echo "ℹ️  未检测到缓存的 Variations 种子文件。"
fi

# 6. [核心改动 2 & 3] 注入/修改 Local State 并清除旧种子签名
echo "🔧 正在应用 Local State 配置补丁..."

if command -v python3 >/dev/null 2>&1; then
    # 优先使用 Python：既能修改现有项，又能动态注入缺失的 is_glic_eligible 键，避免损坏 JSON
    python3 - <<EOF
import json

path = "$CHROME_STATE"
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

# 1. 强制国家为 us
data['variations_country'] = 'us'

# 2. 强制常驻一致性国家为 us
last_version = ""
if 'variations_permanent_consistency_country' in data:
    arr = data['variations_permanent_consistency_country']
    if isinstance(arr, list) and len(arr) > 0:
        last_version = arr[0]
data['variations_permanent_consistency_country'] = [last_version, 'us']

# 3. 启用所有 Profile 的 is_glic_eligible (若缺失则直接添加)
profiles = data.setdefault('profile', {}).setdefault('info_cache', {})
for profile_name, info in profiles.items():
    info['is_glic_eligible'] = True

# 4. 清除旧的种子签名，防止回滚到旧种子
keys_to_remove = [
    'variations_compressed_seed',
    'variations_seed_signature',
    'variations_safe_seed_signature',
    'variations_seed_serial_number'
]
for k in keys_to_remove:
    data.pop(k, None)

with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))

print("✓ 已注入 is_glic_eligible: true")
print("✓ 已将 variations_country 设为 us")
print("✓ 已清除 Local State 中的旧种子签名")
EOF
else
    # 如果没有 Python3，回退到纯 sed 正则处理（等同于 apintocr 的正则）
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        sed -i '' -e 's/"variations_country":"[^"]*"/"variations_country":"us"/g' \
                  -e 's/\("variations_permanent_consistency_country":\[[^]]*\)"[^"]*"\]/\1"us"]/g' \
                  -e 's/"is_glic_eligible":[[:space:]]*false/"is_glic_eligible":true/g' \
                  -e 's/"variations_compressed_seed":"[^"]*",\?//g' \
                  -e 's/"variations_seed_signature":"[^"]*",\?//g' \
                  "$CHROME_STATE"
    else
        sed -i -e 's/"variations_country":"[^"]*"/"variations_country":"us"/g' \
               -e 's/\("variations_permanent_consistency_country":\[[^]]*\)"[^"]*"\]/\1"us"]/g' \
               -e 's/"is_glic_eligible":[[:space:]]*false/"is_glic_eligible":true/g' \
               -e 's/"variations_compressed_seed":"[^"]*",\?//g' \
               -e 's/"variations_seed_signature":"[^"]*",\?//g' \
               "$CHROME_STATE"
    fi
    echo "✓ 已通过 sed 应用基础正则补丁"
fi

# 7. [核心改动 4] 首次启动指引（适配 macOS open 命令，不占用终端）
echo ""
echo "✅ 配置修改完成！"
echo ""
echo "📢 重要：首次启动说明"
echo "1. 请确保网络代理已连接到美国节点（US）。"
echo "2. 复制并执行以下命令进行首次启动（拉取美区种子）："
echo ""
echo "   $FIRST_LAUNCH_CMD"
echo ""
echo "首次启动看到右上角出现 Gemini 图标后，后续就可以像往常一样正常启动 Chrome 了。"
