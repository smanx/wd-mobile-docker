#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
一键替换问道手游客户端（安卓 APK / iOS IPA）里的服务端 IP 并重新打包。

用法示例：
  # 处理单个文件（自动识别 apk / ipa）
  python patch_client_ip.py --ip 172.29.220.175 wd.apk
  python patch_client_ip.py --ip 10.0.0.240 wd.ipa

  # 一次处理整个目录里的所有 apk / ipa
  python patch_client_ip.py --ip 172.29.220.175 --dir "Z:/downloads/baiduyun/问道手游app"

  # 安卓必须用等长 IP，iOS 可用任意长度；给安卓单独指定等长地址：
  python patch_client_ip.py --ip 10.0.0.240 --apk-ip 172.29.220.175 --dir ./client

  # 安卓自动重签名（需要 Android SDK build-tools + JDK keytool）
  python patch_client_ip.py --ip 172.29.220.175 --sign yes wd.apk

实现要点（都是实测踩过的坑）：
  1. 安卓 APK 里 IP 是编译进 luac / dex 的连续字符串，新 IP 必须【等长】
     （原包 49.235.188.189 / 172.29.220.175 都是 14 字符）。不等长会破坏
     http://<IP>:81 结构（补 \\0 会把 ":81" 截断）→ 脚本直接拒绝。
  2. 改过 classes.dex 必须重算 DEX 头校验：
     offset 8..12  = adler32(data[12:])
     offset 12..32 = sha1(data[32:])
     否则安卓安装时报 "INSTALL_FAILED_INVALID_APK / bad dex magic"。
  3. iOS IPA 的 key.json / res/PlatformConfig.luac 都是明文文本，可变长，
     主 Mach-O 可执行文件里没有该硬编码 IP；但改完【代码签名失效】，
     必须用 macOS + 有效企业/开发者证书重签才能装到 iOS 设备。
  4. 打包优先用系统 zip 命令做【增量更新】（只替换改动的条目，1.2GB 包几秒完成）；
     没有 zip 时回退到纯 Python 全量重写（保留每个条目的压缩方式/时间戳）。

只依赖 Python 标准库；签名功能额外需要 Android SDK build-tools 与 JDK keytool。
"""

import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib
from pathlib import Path

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

# 已知的原包硬编码 IP（脚本也会自动推断，这两个只是兜底）
KNOWN_OLD_IPS = (b"49.235.188.189", b"172.29.220.175")

# 安卓：这些路径里含硬编码 IP（教程列出 + 实测确认）
ANDROID_KEY_FILES = (
    "assets/res/PlatformConfig.luac",
)
ANDROID_DEX_RE = re.compile(r"^classes\d*\.dex$")

# iOS：教程明确指出要改的两个文件
IOS_KEY_SUFFIXES = (
    "/key.json",
    "/res/PlatformConfig.luac",
)

# 扫描兜底时跳过的资源文件（大、且不可能含服务端 IP）
SKIP_EXT = (
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".tga", ".dds", ".ktx", ".pvr",
    ".pvr.ccz", ".mp3", ".ogg", ".wav", ".caf", ".mp4", ".mov", ".ttf", ".otf",
    ".atlas", ".pak", ".zip", ".7z", ".so", ".a", ".framework/", ".bundle/",
    ".plist", ".storyboardc/", ".nib", ".car", ".der", ".p12", ".mobileprovision",
)

IPV4_RE = re.compile(
    rb"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"
)


def log(msg=""):
    print(msg, flush=True)


def warn(msg):
    print("[WARN] " + msg, flush=True)


def err(msg):
    print("[ERROR] " + msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# 输入识别与旧 IP 推断
# ---------------------------------------------------------------------------

def detect_kind(path: Path):
    """返回 'android' / 'ios' / None"""
    ext = path.suffix.lower()
    if ext == ".apk":
        return "android"
    if ext == ".ipa":
        return "ios"
    # 扩展名不明时按内容猜
    try:
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
        if any(n.startswith("Payload/") for n in names):
            return "ios"
        if "classes.dex" in names or any(n.endswith(".apk") for n in names):
            return "android"
    except Exception:
        pass
    return None


def collect_candidates(z: zipfile.ZipFile, kind: str, scan_all: bool):
    """
    返回 [(entry_name, data), ...]：所有可能需要改 IP 的条目。
    默认只取已知路径（快）；--scan-all 时额外全量扫描小文件兜底。
    """
    infos = z.infolist()
    picked = {}

    def add(info):
        n = info.filename
        if n in picked:
            return
        if info.file_size > 60 * 1024 * 1024:   # dex 一般不会超过 60MB
            return
        try:
            picked[n] = z.read(info)
        except Exception as e:
            warn(f"读取 {n} 失败: {e}")

    for info in infos:
        n = info.filename
        if kind == "ios":
            if n.endswith(IOS_KEY_SUFFIXES) and n.startswith("Payload/"):
                add(info)
        else:
            if n in ANDROID_KEY_FILES or ANDROID_DEX_RE.match(n):
                add(info)

    if scan_all:
        for info in infos:
            n = info.filename
            low = n.lower()
            if n in picked:
                continue
            if any(low.endswith(x) or low.endswith(x.rstrip("/")) for x in SKIP_EXT):
                continue
            if info.file_size > 20 * 1024 * 1024:
                continue
            add(info)

    return list(picked.items())


def infer_old_ip(candidates, kind):
    """统计候选文件里出现最多的合法 IPv4，作为要被替换的旧 IP。"""
    counts = {}
    for _name, data in candidates:
        for m in IPV4_RE.finditer(data):
            ip = m.group(0)
            if ip in (b"0.0.0.0", b"127.0.0.1", b"255.255.255.255"):
                continue
            counts[ip] = counts.get(ip, 0) + 1
    if not counts:
        return None, 0
    # 原包已知常量优先（避免把版本号 2.13.3.0 这类合法 IPv4 形态误判成服务器 IP）
    for known in KNOWN_OLD_IPS:
        if known in counts:
            return known, counts[known]
    best = max(counts.items(), key=lambda kv: kv[1])
    return best[0], best[1]


# ---------------------------------------------------------------------------
# 替换 + DEX 校验修复
# ---------------------------------------------------------------------------

def fix_dex_checksum(data: bytes) -> bytes:
    """重算 DEX 头的 sha1 与 adler32（改过 classes*.dex 必须调用）。

    顺序很关键：DEX 的 checksum = adler32(data[12:])，而 data[12:32] 是
    signature 字段。必须先写新 sha1，再基于【包含新 sha1 的】data[12:]
    计算 adler32；反过来算会得到错的 checksum，安装时报 bad dex magic。
    """
    buf = bytearray(data)
    if len(buf) < 112 or buf[:4] != b"dex\n":
        return data  # 不是 dex，原样返回
    buf[12:32] = hashlib.sha1(bytes(buf[32:])).digest()          # signature = sha1(data[32:])
    checksum = zlib.adler32(bytes(buf[12:])) & 0xFFFFFFFF          # checksum = adler32(data[12:])
    buf[8:12] = struct.pack("<I", checksum)
    return bytes(buf)


def build_changes(candidates, kind, old_ip: bytes, new_ip: bytes):
    """返回 (changes: dict[name]=bytes, report: list[str])；失败抛 ValueError。"""
    changes = {}
    report = []
    for name, data in candidates:
        n = data.count(old_ip)
        if n == 0:
            continue
        if kind == "android" and len(new_ip) != len(old_ip):
            raise ValueError(
                "安卓 APK 要求等长替换：旧 IP %s(%d字符) / 新 IP %s(%d字符)。\n"
                "  dex/luac 里的 IP 是编译进连续字符串的，补零会把 URL 里的 ':81' 截断。\n"
                "  解决：用一个等长的可达 IP（如 172.29.220.175 / 100.100.100.10），\n"
                "  或者用 --apk-ip 单独给安卓指定等长地址（iOS 不受此限制）。"
                % (old_ip.decode(), len(old_ip), new_ip.decode(), len(new_ip))
            )
        new_data = data.replace(old_ip, new_ip)
        if ANDROID_DEX_RE.match(name):
            new_data = fix_dex_checksum(new_data)
            report.append(f"  {name}: {n} 处 (已重算 DEX adler32/sha1)")
        else:
            report.append(f"  {name}: {n} 处")
        changes[name] = new_data
    return changes, report


# ---------------------------------------------------------------------------
# 重新打包
# ---------------------------------------------------------------------------

def repack_with_zip(src: Path, dst: Path, changes):
    """优先：复制原包 + 系统 zip 增量更新同名条目（快，1.2GB 包几秒）。"""
    if shutil.which("zip") is None:
        return False
    try:
        shutil.copyfile(src, dst)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for name, data in changes.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                # 让 mtime 新于 zip 内条目，确保 zip 一定替换
                os.utime(p, None)
            cmd = ["zip", "-q", str(dst)] + list(changes.keys())
            r = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True)
            if r.returncode != 0:
                warn("zip 增量更新失败，回退纯 Python 重写: " + r.stderr.strip()[:200])
                return False
        return True
    except Exception as e:
        warn("zip 增量更新异常，回退纯 Python 重写: " + str(e))
        return False


def repack_with_python(src: Path, dst: Path, changes):
    """回退：纯 Python 全量重写，保留每个条目的压缩方式/时间戳/权限。"""
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    with zipfile.ZipFile(src) as zin, \
         zipfile.ZipFile(tmp, "w", allowZip64=True) as zout:
        for info in zin.infolist():
            data = changes.get(info.filename)
            if data is None:
                data = zin.read(info)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.internal_attr = info.internal_attr
            zi.create_system = info.create_system
            zi.comment = info.comment
            zi.extra = info.extra
            zout.writestr(zi, data)
    shutil.move(str(tmp), str(dst))


def verify_zip(path: Path, changes, expect_count: int):
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad is not None:
            raise RuntimeError(f"zip 完整性校验失败，损坏条目: {bad}")
        for name, data in changes.items():
            if z.read(name) != data:
                raise RuntimeError(f"条目内容未按预期更新: {name}")
        if len(z.namelist()) != expect_count:
            warn(f"条目数变化: {expect_count} -> {len(z.namelist())}（zip 增量更新有时会重复条目）")


# ---------------------------------------------------------------------------
# 安卓重签名（可选）
# ---------------------------------------------------------------------------

def find_build_tools(explicit=None):
    cands = []
    if explicit:
        cands.append(Path(explicit))
    env = os.environ.get("ANDROID_BUILD_TOOLS")
    if env:
        cands.append(Path(env))
    roots = []
    if os.name == "nt":
        la = os.environ.get("LOCALAPPDATA")
        if la:
            roots.append(Path(la) / "Android" / "Sdk" / "build-tools")
    roots += [Path.home() / "Android" / "Sdk" / "build-tools",
              Path("/opt/android-sdk/build-tools")]
    for r in roots:
        if r.is_dir():
            cands.extend(sorted((p for p in r.iterdir() if p.is_dir()), reverse=True))
    for c in cands:
        if c.is_dir() and ((c / "zipalign").exists() or (c / "zipalign.exe").exists()):
            return c
    return None


def tool_path(bt: Path, name: str):
    for suffix in ("", ".exe", ".bat"):
        p = bt / (name + suffix)
        if p.exists():
            return str(p)
    return None


def sign_apk(apk: Path, args):
    bt = find_build_tools(args.build_tools)
    if not bt:
        raise RuntimeError(
            "找不到 Android SDK build-tools（zipalign/apksigner）。\n"
            "  指定 --build-tools <路径> 或设置环境变量 ANDROID_BUILD_TOOLS。"
        )
    zipalign = tool_path(bt, "zipalign")
    apksigner = tool_path(bt, "apksigner")
    if not zipalign or not apksigner:
        raise RuntimeError(f"build-tools 缺少工具: {bt}")

    ks = Path(args.keystore) if args.keystore else apk.parent / "wd-debug.keystore"
    store = args.storepass or "wd123456"
    key = args.keypass or store
    alias = args.alias or "wdkey"

    if not ks.exists():
        keytool = shutil.which("keytool")
        if not keytool:
            raise RuntimeError("keystore 不存在且找不到 JDK keytool，无法自动生成")
        log(f"  生成 keystore: {ks}")
        subprocess.run([
            keytool, "-genkeypair", "-noprompt",
            "-keystore", str(ks), "-storepass", store, "-keypass", key,
            "-alias", alias, "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "10000", "-dname", "CN=wd, OU=wd, O=wd, L=x, ST=x, C=CN",
        ], check=True, capture_output=True)

    aligned = apk.with_name(apk.stem + ".aligned.apk")
    signed = apk.with_name(apk.stem + ".signed.apk")
    log("  zipalign ...")
    subprocess.run([zipalign, "-f", "-p", "4", str(apk), str(aligned)],
                   check=True, capture_output=True)
    log("  apksigner v1+v2 ...")
    subprocess.run([
        apksigner, "sign",
        "--ks", str(ks), "--ks-key-alias", alias,
        "--ks-pass", f"pass:{store}", "--key-pass", f"pass:{key}",
        "--v1-signing-enabled", "true", "--v2-signing-enabled", "true",
        "--out", str(signed), str(aligned),
    ], check=True, capture_output=True)
    r = subprocess.run([apksigner, "verify", str(signed)], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("apksigner verify 失败: " + r.stderr.strip()[:200])
    shutil.move(str(signed), str(apk))
    aligned.unlink(missing_ok=True)
    log("  签名验证通过 ✓")


# ---------------------------------------------------------------------------
# 单个文件处理
# ---------------------------------------------------------------------------

def process_one(src: Path, args):
    log("\n" + "=" * 70)
    log(f"处理: {src}")
    kind = detect_kind(src)
    if kind is None:
        err("无法识别格式（需要 .apk 或 .ipa）")
        return False
    log(f"  格式: {'安卓 APK' if kind == 'android' else 'iOS IPA'}")

    new_ip = (args.apk_ip if kind == "android" and args.apk_ip else args.ip).encode()
    old_ip = args.old_ip.encode() if args.old_ip else None

    with zipfile.ZipFile(src) as z:
        entry_count = len(z.namelist())
        candidates = collect_candidates(z, kind, args.scan_all)

    if not candidates:
        err("未找到任何候选配置文件")
        return False

    if old_ip is None:
        old_ip, hits = infer_old_ip(candidates, kind)
        if old_ip is None:
            err("无法自动推断旧 IP，请用 --old-ip 指定")
            return False
        log(f"  推断旧 IP: {old_ip.decode()}（候选文件中共出现 {hits} 次）")
    else:
        log(f"  指定旧 IP: {old_ip.decode()}")

    if old_ip == new_ip:
        log(f"  新旧 IP 相同，跳过（{new_ip.decode()}）")
        return True

    log(f"  目标新 IP: {new_ip.decode()}  ({len(old_ip)} -> {len(new_ip)} 字符)")

    try:
        changes, report = build_changes(candidates, kind, old_ip, new_ip)
    except ValueError as e:
        err(str(e))
        return False

    if not changes:
        err(f"没有任何文件包含旧 IP {old_ip.decode()}，请检查 --old-ip")
        return False

    log("  改动明细:")
    for line in report:
        log(line)

    # 输出文件名
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / f"{src.stem}_{new_ip.decode()}{src.suffix}"
    if dst.resolve() == src.resolve():
        err("输出路径与输入相同，请换 --out-dir")
        return False
    log(f"  输出: {dst}")

    if not repack_with_zip(src, dst, changes):
        log("  使用纯 Python 全量重写（较慢，请耐心）...")
        repack_with_python(src, dst, changes)

    try:
        verify_zip(dst, changes, entry_count)
    except Exception as e:
        err("打包后校验失败: " + str(e))
        return False
    log(f"  打包完成: {dst.stat().st_size / 1024 / 1024:.1f} MB, zip 完整性 OK")

    if kind == "android":
        do_sign = args.sign == "yes" or (args.sign == "auto" and find_build_tools(args.build_tools))
        if do_sign:
            try:
                sign_apk(dst, args)
            except Exception as e:
                warn("签名失败（APK 仍可用，但需手动签名）: " + str(e))
                log("  手动签名:\n"
                    f"    zipalign -f -p 4 {dst} aligned.apk\n"
                    f"    apksigner sign --ks <keystore> --out final.apk aligned.apk")
        else:
            warn("未重签名。原 APK 的签名已失效，必须重签才能安装：")
            log("    zipalign -f -p 4 <apk> aligned.apk")
            log("    apksigner sign --ks <keystore> --v1-signing-enabled true "
                "--v2-signing-enabled true --out final.apk aligned.apk")
            log("  （加 --sign yes 让本脚本自动完成，需要 Android SDK build-tools + JDK keytool）")
    else:
        warn("iOS：签名已失效，且本脚本无法在 Windows 上重签。")
        log("  需要在 macOS 上用有效企业/开发者证书重签后才能安装到 iOS 设备：")
        log("    codesign -f -s \"<证书>\" --entitlements <ent.plist> Payload/*.app")
        log("    zip -qr signed.ipa Payload")
        log("  另注意：原包 embedded.mobileprovision 是企业证书且 2024-11-21 已过期，")
        log("  IPA 内不含私钥，必须自备证书；iOS 应用也无法在 Windows/安卓模拟器运行。")

    return True


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="一键替换问道手游客户端（APK/IPA）的服务端 IP 并重新打包",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("files", nargs="*", help="要处理的 .apk / .ipa 文件")
    ap.add_argument("--dir", help="目录：自动处理其中所有 .apk / .ipa")
    ap.add_argument("--ip", required=True, help="新的服务端 IP（iOS 及安卓默认值）")
    ap.add_argument("--apk-ip", help="安卓专用 IP：长度必须与旧 IP 相同（默认同 --ip）")
    ap.add_argument("--old-ip", help="旧 IP（默认自动推断出现次数最多的那个）")
    ap.add_argument("--out-dir", default="client", help="输出目录（默认 client/）")
    ap.add_argument("--scan-all", action="store_true",
                    help="额外全量扫描小文件找硬编码 IP（默认只查教程列出的文件）")
    ap.add_argument("--sign", choices=("auto", "yes", "no"), default="auto",
                    help="安卓重签名：auto=有 build-tools 就签（默认），yes=强制，no=不签")
    ap.add_argument("--build-tools", help="Android SDK build-tools 路径")
    ap.add_argument("--keystore", help="签名 keystore 路径（不存在则自动生成）")
    ap.add_argument("--storepass", help="keystore 密码（默认 wd123456）")
    ap.add_argument("--keypass", help="key 密码（默认同 storepass）")
    ap.add_argument("--alias", help="key alias（默认 wdkey）")
    args = ap.parse_args()

    # 位置参数是用户显式指定的输入，一律保留；
    # 只有 --dir 自动发现的文件才需要排除脚本自己产生的输出（避免反复处理产物）。
    explicit = [Path(p) for p in args.files]
    found = []
    if args.dir:
        d = Path(args.dir)
        if not d.is_dir():
            err(f"--dir 不是目录: {d}")
            return 1
        output_name_re = re.compile(r"_\d+\.\d+\.\d+\.\d+\.(apk|ipa)$")
        for ext in ("*.apk", "*.ipa"):
            for p in sorted(d.glob(ext)):
                if output_name_re.search(p.name) is None:
                    found.append(p)
    # 去重（保序）
    seen, inputs = set(), []
    for p in explicit + found:
        if p not in seen:
            seen.add(p)
            inputs.append(p)

    if not inputs:
        err("没有输入文件。用位置参数传 .apk/.ipa，或用 --dir 指定目录。")
        return 1

    log(f"新 IP: {args.ip}   输出目录: {args.out_dir}   共 {len(inputs)} 个文件")
    ok, fail = 0, 0
    for p in inputs:
        if not p.is_file():
            err(f"文件不存在: {p}")
            fail += 1
            continue
        try:
            if process_one(p, args):
                ok += 1
            else:
                fail += 1
        except Exception as e:
            err(f"{p} 处理异常: {e}")
            fail += 1
    log("\n" + "=" * 70)
    log(f"完成: 成功 {ok} / 失败 {fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
