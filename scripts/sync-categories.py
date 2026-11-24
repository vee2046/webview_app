#!/usr/bin/env python3
"""把 kmlab_site 的**分类与手绘图标**同步到 App 的配置里。

为什么需要这个脚本
------------------
站点的分类不是写死的，而是**关键词规则**驱动的
（`kmlab_site/src/lib/project.ts` → `categoryOf()`）：

    text = title + description
    matched = categories.find(c => c.keywords.some(k => text.includes(k)))
    return matched || categories[last]        // 兜底 = 最后一条（misc）

手绘图标同理（`doodleOf()`，规则在 `site.content.json` 的 `doodles[]`）。

App 之前是**手工**把分类/图标抄进 `config/app.config.json` 的 ——
站点一改（新增「娱乐」分类、新增 `podcast` doodle），App 就对不上了。

本脚本直接跑站点那套规则，把结果写回 App 配置：
  - `app.tabs[]`      ← 站点的 `categories[]`（+ 一个开头的「全部」）
  - `tools[].tab`     ← 关键词匹配到的分类 id
  - `tools[].color`   ← 分类色（CSS 变量 → hex）
  - `tools[].icon`    ← 关键词匹配到的 doodle 名

用法：
    python3 scripts/sync-categories.py            # 同步
    python3 scripts/sync-categories.py --check    # 只检查不改（CI 用）

依赖：kmlab_site 仓库（默认 ../kmlab_site，可用 KMLAB_SITE_DIR 覆盖）。
"""

import argparse
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.environ.get(
    'KMLAB_SITE_DIR', os.path.join(os.path.dirname(ROOT), 'kmlab_site')
)
CONFIG = os.path.join(ROOT, 'config', 'app.config.json')

# 站点的 CSS 颜色变量 → App 配置里用的 hex
COLOR_TOKENS = {
    'var(--crayon-red)': '#d9534f',
    'var(--crayon-blue)': '#3d6b8a',
    'var(--crayon-green)': '#6f9264',
    'var(--crayon-amber)': '#d9a441',
    'var(--crayon-purple)': '#8a6fa3',
}

# 分类页签的图标（站点分类本身没有图标字段，这里由 App 自己定）
TAB_ICONS = {
    'all': 'grid',
    'life': 'cup',
    'productivity': 'check',
    'knowledge': 'book',
    'entertainment': 'podcast',
    'misc': 'box',
}


def load(path):
    with io.open(path, encoding='utf-8') as f:
        return json.load(f)


def category_of(text, categories):
    """复刻 kmlab_site/src/lib/project.ts 的 categoryOf()。"""
    for c in categories:
        for kw in c.get('keywords') or []:
            if kw and kw in text:
                return c
    return categories[-1] if categories else None


def doodle_of(text, doodles, default):
    """复刻 kmlab_site/src/lib/project.ts 的 doodleOf()。"""
    for rule in doodles or []:
        for kw in rule.get('keywords') or []:
            if kw and kw in text:
                return rule['name']
    return default


def hex_of(color):
    if not color:
        return None
    return COLOR_TOKENS.get(color.strip(), color.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='只检查，不写文件')
    args = ap.parse_args()

    content_path = os.path.join(SITE, 'src', 'data', 'site.content.json')
    files_path = os.path.join(SITE, 'public', 'data', 'html_files.json')
    for p in (content_path, files_path, CONFIG):
        if not os.path.exists(p):
            sys.exit('❌ 找不到 %s' % p)

    content = load(content_path)
    site_files = load(files_path)
    categories = content.get('categories') or []
    doodles = content.get('doodles') or []
    doodle_default = content.get('doodleDefault') or 'box'

    with io.open(CONFIG, encoding='utf-8') as f:
        raw = f.read()
    cfg = json.loads(raw)

    # ── 1) app.tabs[] ────────────────────────────────────────────
    tabs = [{
        'id': 'all',
        'title': '全部',
        'icon': TAB_ICONS['all'],
        'color': None,
    }]
    for c in categories:
        tabs.append({
            'id': c['id'],
            'title': c['label'],
            'icon': TAB_ICONS.get(c['id'], 'box'),
            'color': hex_of(c.get('color')),
        })

    # ── 2) 站点条目 → 分类 + 图标 ────────────────────────────────
    by_title = {}
    for item in site_files:
        title = item.get('title') or ''
        desc = item.get('description') or ''
        text = '%s %s' % (title, desc)
        cat = category_of(text, categories)
        by_title[title] = {
            'category': cat['id'] if cat else 'misc',
            'color': hex_of(cat.get('color')) if cat else None,
            'doodle': doodle_of(text, doodles, doodle_default),
        }

    changes = []
    if cfg['app'].get('tabs') != tabs:
        changes.append('app.tabs[]：%d → %d 个分类页签（新增 %s）' % (
            len(cfg['app'].get('tabs') or []),
            len(tabs),
            '、'.join(t['id'] for t in tabs
                     if t['id'] not in [x['id'] for x in (cfg['app'].get('tabs') or [])]),
        ))
        cfg['app']['tabs'] = tabs

    for tool in cfg['tools']:
        info = by_title.get(tool['title'])
        if not info:
            changes.append('⚠️ App 里的「%s」在站点条目里找不到（站点改了标题？）' % tool['title'])
            continue
        if tool.get('tab') != info['category']:
            changes.append('%s：分类 %s → %s' % (tool['id'], tool.get('tab'), info['category']))
            tool['tab'] = info['category']
        if tool.get('icon') != info['doodle']:
            changes.append('%s：图标 %s → %s' % (tool['id'], tool.get('icon'), info['doodle']))
            tool['icon'] = info['doodle']
        if info['color'] and tool.get('color') != info['color']:
            changes.append('%s：颜色 %s → %s' % (tool['id'], tool.get('color'), info['color']))
            tool['color'] = info['color']

    site_only = [t for t in by_title
                 if t not in [x['title'] for x in cfg['tools']]]

    print('站点分类（%d）：%s' % (
        len(categories),
        '、'.join('%s=%s' % (c['id'], c['label']) for c in categories)))
    if site_only:
        print('⚠️ 站点有、App 没有的条目：%s' % '、'.join(site_only))
    if changes:
        print('\n需要同步 %d 处：' % len(changes))
        for c in changes:
            print('  · ' + c)
    else:
        print('\n✅ 分类与图标已经一致，无需同步')

    if args.check:
        return 1 if changes else 0

    if changes:
        with io.open(CONFIG, 'w', encoding='utf-8') as f:
            f.write(json.dumps(cfg, ensure_ascii=False, indent=2) + '\n')
        print('\n✅ 已写回 %s' % CONFIG)
    return 0


if __name__ == '__main__':
    sys.exit(main())
