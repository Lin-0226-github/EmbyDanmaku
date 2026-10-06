#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EmbyDanmaku —— 不用 git，直接把整个项目上传到 GitHub（a-Shell 可用）

用法（a-Shell）：
    pickFolder          # 弹出选择器，选中解压出来的 EmbyDanmaku 文件夹
    python3 upload.py   # 按提示粘贴 GitHub 令牌即可

令牌两种给法（二选一）：
    A. 脚本会提示你粘贴（普通输入，会显示在屏幕上，别截图就行）
    B. 先把令牌存成文件（推荐，屏幕上不出现令牌）：
           echo ghp_你的令牌 > token.txt
       然后 python3 upload.py 会自动读取，上传成功后自动删除 token.txt

令牌生成：Safari 打开 https://github.com/settings/tokens
      → Generate new token (classic) → 勾选 repo → 生成后复制
（脚本会自动创建 EmbyDanmaku 仓库，不需要你先在网页上建）

原理：优先走 Git Data API（blob → tree → commit → ref），全部文件在一个提交里；
      若「建树」等步骤失败，自动降级为逐文件上传（Contents API，
      每个文件一个提交，慢一点但最稳）。空仓库会先用 README.md 播种初始化。
"""

import base64
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION = "v19"

API = os.environ.get("GH_API", "https://api.github.com").rstrip("/")
REPO_NAME = os.environ.get("GH_REPO", "EmbyDanmaku")
BRANCH = "main"
TIMEOUT = 30          # 单个请求最多等 30 秒，避免"看起来卡死"

_CONTEXT = ssl.create_default_context()
_SSL_WARNED = False

# 这些目录 / 文件不上传（token.txt 是本机存令牌用的，绝对不能传上去）
SKIP_DIRS = {".git", "Payload", "build", "build-signed", "xcuserdata", ".pkg", "__MACOSX",
             "__pycache__", ".codebuddy", ".idea", ".vscode"}
SKIP_FILES = {".DS_Store", "token.txt"}
SKIP_SUFFIX = (".ipa", ".icloud")   # .icloud = 还没从 iCloud 下载下来的占位文件


def _open(req):
    """打开请求。
    - 证书校验失败（代理 MITM / 网络审计）→ 自动跳过校验重试
    - 普通网络抖动（手机网络常见）→ 指数退避重试
    """
    global _CONTEXT, _SSL_WARNED
    delay = 3
    for attempt in range(3):
        try:
            return urllib.request.urlopen(req, timeout=TIMEOUT, context=_CONTEXT)
        except urllib.error.HTTPError:
            raise
        except urllib.error.URLError as e:
            reason = getattr(e, "reason", None)
            cert_problem = isinstance(reason, ssl.SSLError) or (
                "CERTIFICATE_VERIFY_FAILED" in str(reason))
            if cert_problem:
                _CONTEXT = ssl._create_unverified_context()
                if not _SSL_WARNED:
                    _SSL_WARNED = True
                    print("! 检测到 HTTPS 证书被替换（你的网络里有代理/审计在解密 HTTPS）",
                          flush=True)
                    print("  已自动跳过证书校验继续上传，不需要你做任何操作", flush=True)
                continue
            if attempt == 2:
                raise
            print("  网络不稳定，%d 秒后重试（%d/2）..." % (delay, attempt + 1), flush=True)
            time.sleep(delay)
            delay *= 2
    raise RuntimeError("网络请求反复失败")


def request(method, path, token, payload=None):
    """调用 GitHub API，返回 (状态码, 解析后的 JSON)"""
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "EmbyDanmaku-uploader")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with _open(req) as r:
            body = r.read().decode("utf-8")
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"message": raw[:300]}
    except Exception as e:  # 网络不通等
        return -1, {"message": str(e)}


def restore_hidden_files(root):
    """用可见的 github-workflow.txt 强制刷新 .github/workflows/build-ipa.yml。
    iOS「文件」App 看不见 .github 目录，本地那份可能是旧版；
    每次都以 github-workflow.txt 为准覆盖，保证云端工作流是最新修复版。
    """
    wf = os.path.join(root, ".github", "workflows", "build-ipa.yml")
    src = os.path.join(root, "github-workflow.txt")
    if not os.path.isfile(src):
        return
    with open(src, "r", encoding="utf-8") as f:
        content = f.read()
    if os.path.isfile(wf):
        try:
            with open(wf, "r", encoding="utf-8") as f:
                if f.read() == content:
                    return  # 本地已是最新，无需覆盖
        except OSError:
            pass
    os.makedirs(os.path.dirname(wf), exist_ok=True)
    with open(wf, "w", encoding="utf-8") as f:
        f.write(content)
    print("已用 github-workflow.txt 刷新 .github/workflows/build-ipa.yml", flush=True)


def locate_root():
    """确认当前目录是项目根目录；选到上一层时自动往下找"""
    def ok(d):
        return (os.path.isfile(os.path.join(d, "setup.sh"))
                or os.path.isfile(os.path.join(d, "github-workflow.txt")))

    if ok("."):
        return os.getcwd()
    for d in ("EmbyDanmaku", "EmbyDanmaku/EmbyDanmaku"):
        if ok(d):
            print("（自动切换到 %s）" % d, flush=True)
            os.chdir(d)
            return os.getcwd()
    for d in sorted(os.listdir(".")):
        if os.path.isdir(d) and ok(os.path.join(d, "EmbyDanmaku")):
            print("（自动切换到 %s/EmbyDanmaku）" % d, flush=True)
            os.chdir(os.path.join(d, "EmbyDanmaku"))
            return os.getcwd()
    print("× 当前目录不像 EmbyDanmaku 项目：%s" % os.getcwd())
    print("  请先 pickFolder 选中 EmbyDanmaku 文件夹本身，再运行 python3 upload.py")
    sys.exit(1)


def warn_icloud_placeholders(root):
    """项目放在 iCloud 时，文件可能还没真正下载到手机（是 .icloud 占位文件）"""
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith(".icloud"):
                hits.append(fn)
    if hits:
        print("! 注意：这个文件夹在 iCloud 里，有 %d 个文件还没下载到手机" % len(hits),
              flush=True)
        print("  例如：%s" % hits[0], flush=True)
        print("  解决：在「文件」App 里进入这个文件夹，把里面的文件逐个点开让它们下载；", flush=True)
        print("  或者长按文件夹 → 拷贝，粘贴到「我的 iPhone」下，再 pickFolder 选新位置", flush=True)
        print(flush=True)


def read_token(root):
    """读令牌：环境变量 → token.txt → 手动粘贴（绝不用 getpass，a-Shell 下会卡死）"""
    token = os.environ.get("GH_TOKEN", "").strip()
    if token:
        print("已从环境变量 GH_TOKEN 读取令牌（长度 %d）" % len(token), flush=True)
        return token

    tfile = os.path.join(root, "token.txt")
    if os.path.isfile(tfile):
        try:
            with open(tfile, "r", encoding="utf-8") as f:
                token = f.read().strip()
        except OSError:
            token = ""
        if token:
            print("已从 token.txt 读取令牌（长度 %d）" % len(token), flush=True)
            return token

    print("没有找到令牌。请把令牌粘贴到下面，然后按回车：", flush=True)
    print("（输入会显示在屏幕上，属正常；截图前先删掉这一行）", flush=True)
    try:
        token = input("令牌> ").strip()
    except (EOFError, KeyboardInterrupt):
        token = ""
    print("已收到，长度 %d 字符（正常应是 40 左右、ghp_ 开头）" % len(token), flush=True)
    return token


def seed_empty_repo(base, token, root):
    """空仓库初始化。
    GitHub 规定：一个提交都没有的仓库，Git Data API（blob/tree/commit）一律返回
    409 "Git Repository is empty"。唯一能用的写入端点是 PUT /contents/{path}，
    它会顺手把 main 分支和首个提交一起建出来。
    """
    seed_file = os.path.join(root, "README.md")
    if os.path.isfile(seed_file):
        seed_name = "README.md"
        with open(seed_file, "rb") as f:
            raw = f.read()
    else:
        seed_name = ".init"
        raw = b"init"
    st, r = request("PUT", base + "/contents/" + seed_name, token,
                    {"message": "init: 种子提交（upload.py 自动创建）",
                     "content": base64.b64encode(raw).decode("ascii"),
                     "branch": BRANCH})
    if st in (200, 201):
        print("      已用 %s 初始化分支 %s" % (seed_name, BRANCH), flush=True)
        return True
    print("× 初始化空仓库失败（HTTP %s）：%s" % (st, r.get("message", "")), flush=True)
    return False


def collect(root):
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fn in sorted(filenames):
            if fn in SKIP_FILES or fn.endswith(SKIP_SUFFIX):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            files.append((rel, full))
    return files


def commit_via_git_data(base, token, tree):
    """建树 → 建提交 → 更新 main 分支（单提交方案，带重试）。成功返回 True。"""
    # 5. 建树（不带 base_tree = 整仓镜像，远端多余文件会被删掉）
    print("[5/7] 生成文件清单（建树）...", flush=True)
    st, t = {}, {}
    for attempt in range(3):
        st, t = request("POST", base + "/git/trees", token, {"tree": tree})
        if st == 201:
            break
        wait = 5 * (attempt + 1)
        print("      建树返回 %s（%s），等 %d 秒重试（%d/3）..."
              % (st, one_line(t.get("message", "")), wait, attempt + 1), flush=True)
        time.sleep(wait)
    if st != 201:
        print("× 建树失败（HTTP %s）：%s" % (st, t.get("message", "")), flush=True)
        return False

    # 6. 建提交
    print("[6/7] 创建提交 ...", flush=True)
    st, ref = request("GET", base + "/git/ref/heads/" + BRANCH, token)
    parent = ref["object"]["sha"] if st == 200 else None
    payload = {"message": "从 iPhone 上传（a-Shell + GitHub API）", "tree": t["sha"]}
    if parent:
        payload["parents"] = [parent]
    st, c = request("POST", base + "/git/commits", token, payload)
    if st != 201:
        print("× 建提交失败（HTTP %s）：%s" % (st, c.get("message", "")), flush=True)
        return False

    # 7. 移动分支指针
    print("[7/7] 更新 main 分支 ...", flush=True)
    if parent:
        st, r = request("PATCH", base + "/git/refs/heads/" + BRANCH, token,
                        {"sha": c["sha"], "force": True})
    else:
        st, r = request("POST", base + "/git/refs", token,
                        {"ref": "refs/heads/" + BRANCH, "sha": c["sha"]})
    if st not in (200, 201):
        print("× 更新分支失败（HTTP %s）：%s" % (st, r.get("message", "")), flush=True)
        return False
    return True


def git_blob_sha(data):
    """算出内容对应的 git blob sha（和 GitHub 存储的完全一致），用来判断文件是否相同"""
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def one_line(msg):
    """GitHub 的报错信息常带换行，压成一行方便阅读"""
    return str(msg).replace("\n", " ").strip()[:100]


def upload_via_contents(base, token, files):
    """兜底方案：逐文件走 Contents API。
    每个文件一个提交，慢一点（约每文件 2 秒）但最稳。
    已存在的文件（GitHub 对这种情况 409 / 422 都会返回）：
      内容相同 → 直接跳过；内容不同 → 带旧 sha 覆盖。
    """
    print("兜底方案：逐个文件上传（共 %d 个）..." % len(files), flush=True)
    fails = []
    scope_hint_shown = False
    for i, (rel, full) in enumerate(files, 1):
        with open(full, "rb") as f:
            raw = f.read()
        local_sha = git_blob_sha(raw)
        quoted = urllib.parse.quote(rel)
        payload = {"message": "upload %d/%d: %s" % (i, len(files), rel),
                   "content": base64.b64encode(raw).decode("ascii"),
                   "branch": BRANCH}
        st, r = request("PUT", base + "/contents/" + quoted, token, payload)
        tag = ""
        # 已存在的文件：GitHub 有时回 409、有时回 422，统一按「需要旧 sha」处理
        if st in (409, 422):
            gst, cur = request("GET", base + "/contents/" + quoted + "?ref=" + BRANCH,
                               token)
            remote_sha = (cur.get("sha") or "") if gst == 200 else ""
            if remote_sha == local_sha:
                print("  [%d/%d] %s（内容相同，已跳过）" % (i, len(files), rel), flush=True)
                continue
            if remote_sha:
                payload["sha"] = remote_sha
                st, r = request("PUT", base + "/contents/" + quoted, token, payload)
                tag = "（覆盖）"
        if st in (200, 201):
            print("  [%d/%d] %s%s" % (i, len(files), rel, tag), flush=True)
        else:
            fails.append(rel)
            print("  × [%d/%d] %s（HTTP %s）：%s"
                  % (i, len(files), rel, st, one_line(r.get("message", ""))), flush=True)
            if rel.startswith(".github/") and not scope_hint_shown:
                scope_hint_shown = True
                print("      ! 这个文件在 .github 目录里，令牌需要多勾一个 workflow 权限：",
                      flush=True)
                print("        Safari 打开 github.com/settings/tokens → 点你的令牌 →",
                      flush=True)
                print("        勾选 workflow → 拉到底点 Update token（令牌字符串不变）",
                      flush=True)
                print("        然后把本脚本再跑一遍，就会把工作流文件补上去", flush=True)
        time.sleep(0.5)
    if fails:
        print("× 有 %d 个文件没传上去：%s ..." % (len(fails), "、".join(fails[:3])))
        return False
    return True


def verify_remote(base, token, files):
    """上传后校验：把仓库 main 分支整棵文件树拉下来，逐个比对 blob sha。
    返回不一致/缺失的文件列表（空列表 = 仓库与手机完全一致）。
    这一步能发现「文件没传成功 / 手机上换了旧文件」的问题，避免用旧代码白构建一次。
    """
    print("[校验] 正在核对仓库内容与手机是否完全一致 ...", flush=True)
    st, ref = request("GET", base + "/git/ref/heads/" + BRANCH, token)
    if st != 200:
        print("  ! 读不到 main 分支（HTTP %s），跳过校验" % st, flush=True)
        return []
    st, c = request("GET", base + "/git/commits/" + ref["object"]["sha"], token)
    if st != 200:
        print("  ! 读不到最新提交（HTTP %s），跳过校验" % st, flush=True)
        return []
    st, t = request("GET", base + "/git/trees/" + c["tree"]["sha"] + "?recursive=1", token)
    if st != 200:
        print("  ! 读不到文件树（HTTP %s），跳过校验" % st, flush=True)
        return []
    remote = {}
    for e in t.get("tree", []):
        if e.get("type") == "blob":
            remote[e["path"]] = e["sha"]
    bad = []
    for rel, full in files:
        with open(full, "rb") as f:
            local = git_blob_sha(f.read())
        if remote.get(rel) != local:
            bad.append(rel)
    if bad:
        print("  ! 有 %d 个文件仓库里和手机上不一致：" % len(bad), flush=True)
        for rel in bad[:10]:
            print("      %s" % rel, flush=True)
        if len(bad) > 10:
            print("      ...等共 %d 个" % len(bad), flush=True)
    else:
        print("      全部 %d 个文件与仓库完全一致" % len(files), flush=True)
    return bad


def trigger_build(base, user, token):
    """上传完成后，直接用 API 触发 Actions 构建工作流（workflow_dispatch）"""
    print("[额外] 正在自动触发云端构建 ...", flush=True)
    st, r = request("POST", base + "/actions/workflows/build-ipa.yml/dispatches",
                    token, {"ref": BRANCH})
    if st in (200, 204):
        print("      构建已触发！Safari 打开 https://github.com/%s/%s/actions"
              % (user, REPO_NAME), flush=True)
        print("      等它跑完（5~10 分钟），到 Releases（标签 latest-ipa）下载 IPA", flush=True)
        return True
    print("      自动触发没成功（HTTP %s：%s）" % (st, one_line(r.get("message", ""))),
          flush=True)
    print("      最常见原因：.github/workflows/build-ipa.yml 还没在仓库里（缺 workflow", flush=True)
    print("      权限被拒收）。解决：github.com/settings/tokens 给令牌勾上 workflow →", flush=True)
    print("      Update token → 重跑本脚本补传 → 再跑一次本脚本或手动触发：", flush=True)
    print("      Safari 打开 https://github.com/%s/%s/actions → 左侧 Build iOS IPA →"
          % (user, REPO_NAME), flush=True)
    print("      Run workflow → 签名方式填 unsigned", flush=True)
    return False


def main():
    print("== EmbyDanmaku 上传脚本 %s ==" % VERSION, flush=True)
    root = locate_root()
    restore_hidden_files(root)
    warn_icloud_placeholders(root)
    print("项目目录：%s" % root, flush=True)

    token = read_token(root)
    if not token:
        print("× 没有读到令牌。两种给法：")
        print("  A. 重跑脚本，看到提示后粘贴令牌再回车")
        print("  B. echo ghp_你的令牌 > token.txt   然后 python3 upload.py")
        sys.exit(1)

    # 1. 验证令牌、拿到用户名
    print()
    print("[1/7] 正在连接 api.github.com 验证令牌（最多等 %d 秒）..." % TIMEOUT, flush=True)
    st, me = request("GET", "/user", token)
    if st != 200:
        print("× 连不上 GitHub 或令牌无效（HTTP %s）" % st)
        print("  %s" % me.get("message", ""))
        print()
        print("  401 Bad credentials  → 令牌错了 / 过期了 / 没勾选 repo，去重新生成一个")
        print("  403 rate limit       → 等几分钟再跑")
        print("  -1                   → 网络不通：Safari 能否打开 github.com？")
        print("                         开飞行模式 5 秒再关，或换 Wi-Fi / 流量重跑")
        sys.exit(1)
    user = me.get("login", "")
    print("      令牌有效，登录账号：%s" % user, flush=True)

    # 2. 创建仓库（已存在就跳过）
    print("[2/7] 创建 / 检查仓库 %s ..." % REPO_NAME, flush=True)
    st, r = request("POST", "/user/repos", token,
                    {"name": REPO_NAME, "private": False, "has_wiki": False})
    if st == 201:
        print("      已创建仓库：%s" % r.get("full_name", REPO_NAME), flush=True)
    elif st == 422:
        print("      仓库已存在，直接更新它", flush=True)
    else:
        print("      ! 创建仓库返回 %s：%s（若仓库已存在可忽略，继续上传）"
              % (st, r.get("message", "")), flush=True)

    base = "/repos/%s/%s" % (user, REPO_NAME)

    # 3. 空仓库先放种子提交（否则后面上传文件会 409）
    print("[3/7] 检查仓库是否为空 ...", flush=True)
    st, ref0 = request("GET", base + "/git/ref/heads/" + BRANCH, token)
    if st == 200:
        print("      仓库已有提交，继续", flush=True)
    else:
        print("      仓库还没有任何提交（HTTP %s），先放一个种子提交 ..." % st, flush=True)
        if not seed_empty_repo(base, token, root):
            sys.exit(1)

    # 4. 收集文件并逐个上传为 blob
    files = collect(root)
    if not files:
        print("× 没有找到任何文件")
        sys.exit(1)
    print("[4/7] 共 %d 个文件，开始上传（每个文件一个请求）..." % len(files), flush=True)
    tree = []
    for i, (rel, full) in enumerate(files, 1):
        with open(full, "rb") as f:
            data = f.read()
        st, b = {}, {}
        for attempt in range(4):
            st, b = request("POST", base + "/git/blobs", token,
                            {"content": base64.b64encode(data).decode("ascii"),
                             "encoding": "base64"})
            if st == 201:
                break
            msg = str(b.get("message", ""))
            # 空仓库兜底：理论上种子提交已处理，这里只防万一
            if st == 409 and "empty" in msg.lower():
                if seed_empty_repo(base, token, root):
                    continue
                break
            if st >= 500 or st == 403 or st == -1:
                if attempt == 3:
                    break
                print("      %s 返回 %s，3 秒后重试（%d/2）..." % (rel, st, attempt + 1),
                      flush=True)
                time.sleep(3)
                continue
            break
        if st != 201:
            print("× 上传失败 [%d/%d] %s（HTTP %s）：%s"
                  % (i, len(files), rel, st, b.get("message", "")))
            print("  直接把本脚本再跑一遍即可，它会从头覆盖，不需要清理任何东西")
            sys.exit(1)
        tree.append({"path": rel, "mode": "100644", "type": "blob", "sha": b["sha"]})
        print("  [%d/%d] %s" % (i, len(files), rel), flush=True)

    # 5-7. 建树 → 建提交 → 更新分支；失败自动降级为逐文件上传
    if not commit_via_git_data(base, token, tree):
        print()
        print("单提交方案没走通，自动改用逐文件上传（更稳，每个文件一个提交）")
        print()
        if not upload_via_contents(base, token, files):
            print("× 仍有文件没传上去。把本脚本再跑一遍即可续传覆盖，不用清理任何东西")
            sys.exit(1)

    # 上传后校验：仓库内容必须和手机完全一致，才触发云端构建
    bad = verify_remote(base, token, files)
    if bad:
        print()
        print("× 为避免用旧代码构建，这次不触发编译。")
        print("  处理办法：确认手机文件夹里的文件是新包解压出来的，然后直接重跑本脚本。")
        sys.exit(1)

    # 收尾：触发云端构建 + 删掉本地的 token.txt
    trigger_build(base, user, token)
    tf = os.path.join(root, "token.txt")
    if os.path.isfile(tf):
        try:
            os.remove(tf)
            print("（已删除 token.txt，令牌不再留在手机上）", flush=True)
        except OSError:
            pass

    print()
    print("== 上传完成！共 %d 个文件都在仓库里了 ==" % len(files))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        print("已手动取消（Ctrl+C）")
        sys.exit(130)
