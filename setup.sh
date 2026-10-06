#!/bin/sh
# ------------------------------------------------------------------
# EmbyDanmaku —— 手机端一键推送到 GitHub
#
# 适用环境：a-Shell（推荐，自带 git）/ iSH（需先 apk add git）/ 任何带 git 的终端
#
# 使用方式（a-Shell）：
#   pickFolder              # 弹出选择器，选中解压出来的 EmbyDanmaku 文件夹
#   sh setup.sh             # 若 setup.sh 在上一层，用 sh EmbyDanmaku/setup.sh，脚本会自己找到位置
# ------------------------------------------------------------------

# 判断某个目录里是不是放着本项目的两个必需入口文件
have_proj() { [ -f "$1/setup.sh" ] && [ -f "$1/github-workflow.txt" ]; }

# 容错：如果当前目录不是项目根目录（比如 pickFolder 选到了上一层），
#       自动往下找一层再继续
if ! have_proj .; then
  for d in EmbyDanmaku EmbyDanmaku/EmbyDanmaku */EmbyDanmaku */; do
    if have_proj "$d"; then
      echo "（自动切换到 $d）"
      cd "$d" || exit 1
      break
    fi
  done
fi
if ! have_proj .; then
  echo
  echo "× 当前目录不像 EmbyDanmaku 项目根目录：$(pwd)"
  echo "  请用 pickFolder 选中 EmbyDanmaku 文件夹本身，再运行 sh setup.sh"
  echo "  这里现在有：$(ls)"
  exit 1
fi

echo "== 检查 git =="
if ! command -v git >/dev/null 2>&1; then
  cat <<MSG

× 本机没有 git 命令（你这版 a-Shell 的 pkg 源里也没有这个包）。
  没关系——项目里带了不需要 git 的上传脚本，直接运行：

    python3 upload.py

  它会自动创建 GitHub 仓库并上传全部文件，只需要粘贴一个令牌。
  （若 pkg install git 能装上，也可以回来继续用本脚本）

MSG
  exit 1
fi

echo "== 第 1 步：补回 iOS「文件」App 里看不见的隐藏文件 =="
mkdir -p .github/workflows
cp github-workflow.txt .github/workflows/build-ipa.yml
rm -f github-workflow.txt
printf 'build/\nbuild-signed/\nPayload/\n*.ipa\nxcuserdata/\n.DS_Store\n' > .gitignore
echo "   已生成 .github/workflows/build-ipa.yml 与 .gitignore"

echo "== 第 2 步：初始化仓库并配置 git 身份 =="
[ -d .git ] || git init
git config --global --add safe.directory "$PWD" 2>/dev/null || true
git config user.name  >/dev/null 2>&1 || git config user.name  "EmbyDanmaku"
git config user.email >/dev/null 2>&1 || git config user.email "emby@example.com"

echo "== 第 3 步：提交 =="
git add -A
git commit -m "init" 2>/dev/null || echo "（没有新变化，跳过提交）"
git branch -M main 2>/dev/null || true

echo "== 第 4 步：推送到 GitHub =="
printf "请输入你的 GitHub 用户名： "
read -r GH_USER
if [ -z "$GH_USER" ]; then
  echo "没有填用户名，退出。重新运行 sh setup.sh 即可。"
  exit 1
fi
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GH_USER/EmbyDanmaku.git"

cat <<TIP

接下来终端会弹出账号密码输入提示：
  用户名 = $GH_USER
  密码   = GitHub Personal Access Token（不是登录密码）

还没有令牌的话：Safari 打开 https://github.com/settings/tokens
  → Generate new token (classic) → 勾选 repo → 生成后复制备用
（要先在 GitHub 网页端建好名为 EmbyDanmaku 的空仓库，不要勾选初始化 README）

TIP

git push -u origin main

echo
echo "== 推送完成 =="
echo "下一步：浏览器打开 https://github.com/$GH_USER/EmbyDanmaku/actions"
echo "  选 Build iOS IPA → Run workflow → 签名方式选 unsigned → 等 5~10 分钟"
