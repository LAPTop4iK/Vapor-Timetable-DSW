#!/usr/bin/env python3
# collect_swift_without_headers.py
# python3 scripts/collect_swift_without_headers.py --root . --out combined_swift_no_headers.txt
import argparse
import os
from pathlib import Path

DEFAULT_EXCLUDES = {
    ".git", ".build", "build", "DerivedData", "Pods",
    "Carthage", ".swiftpm", ".xcworkspace"
}

def looks_like_xcode_header(lines):
    """
    Эвристика: первая пачка строк начинается с `//`,
    среди них есть `.swift` или `Created by`, и их <= 15.
    """
    header = []
    for ln in lines:
        if ln.lstrip().startswith("//"):
            header.append(ln)
        else:
            break
    if not header:
        return False, 0
    blob = "".join(header)
    if (".swift" in blob or "Created by" in blob) and len(header) <= 15:
        return True, len(header)
    return False, 0

def strip_top_header(text):
    # Убираем возможный BOM и нормализуем переносы
    if text.startswith("\ufeff"):
        text = text[1:]

    # 1) Блочный комментарий в самом верху: /* ... */
    t = text.lstrip()
    if t.startswith("/*"):
        start_offset = len(text) - len(t)
        end = t.find("*/")
        # Ограничиваем длину поиска, чтобы не сносить весь файл
        if 0 <= end <= 4000:
            block = t[:end+2]
            if ("Created by" in block) or (".swift" in block):
                after = t[end+2:]
                # сносим ведущие пустые строки
                after = after.lstrip("\r\n")
                return after

    # 2) Линейные комментарии вверху: // ...
    lines = text.splitlines(keepends=True)
    is_header, count = looks_like_xcode_header(lines[:20])
    if is_header:
        rest = "".join(lines[count:])
        # сносим пустые строки прямо под шапкой
        rest = rest.lstrip("\r\n")
        return rest

    # Если шапка не распознана — возвращаем как есть
    return text

def should_skip_dir(dirname, user_excludes):
    base = os.path.basename(dirname)
    return base in DEFAULT_EXCLUDES or base in user_excludes or base.endswith(".xcodeproj")

def collect_swift_files(root, user_excludes):
    for dirpath, dirnames, filenames in os.walk(root):
        # фильтруем директории на месте
        dirnames[:] = [d for d in dirnames if not should_skip_dir(os.path.join(dirpath, d), user_excludes)]
        for name in filenames:
            if name.endswith(".swift"):
                yield Path(dirpath) / name

def main():
    ap = argparse.ArgumentParser(description="Собрать текст всех .swift без верхних шапок в один файл.")
    ap.add_argument("--root", default=".", help="Корень проекта (по умолчанию текущая папка).")
    ap.add_argument("--out", default="combined_swift_no_headers.txt", help="Путь к выходному файлу.")
    ap.add_argument("--exclude", action="append", default=[], help="Исключить директории (флаг можно повторять).")
    ap.add_argument("--no-separators", action="store_true", help="Не добавлять разделители с именами файлов.")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out_path = Path(args.out).resolve()

    files = sorted(collect_swift_files(root, set(args.exclude)))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as out:
        for f in files:
            try:
                text = f.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                # fallback если где-то странная кодировка
                text = f.read_text(encoding="utf-8", errors="replace")
            stripped = strip_top_header(text)
            if not args.no_separators:
                rel = f.relative_to(root)
                out.write(f"\n// ===== FILE: {rel} =====\n")
            out.write(stripped.rstrip() + "\n")

    print(f"Готово: {out_path}")

if __name__ == "__main__":
    main()