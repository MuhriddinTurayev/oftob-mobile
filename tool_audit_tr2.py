"""Tarjima auditi (2): Dart manbasini to'g'ri tahlil qiladi (izohlar tashlanadi, ${} ichidagi satrlar ham), barcha satr bo'laklarini
lug'at bilan solishtiradi. Natija: audit2.txt  (qator: fayl:satr | matn | qolgan so'zlar)"""
import re, os, glob, sys, json

ROOT = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(ROOT, 'lib')
exec(open(os.path.join(ROOT, 'tool_audit_tr.py'), encoding='utf-8').read().split('# --- dart satrlarini topish ---')[0])  # DICT, translate


def lex(text):
    """[(literal_fragment, line)] — kod ichidagi barcha satr bo'laklari"""
    out = []
    n = len(text)
    i = 0
    line = 1

    def string(i, q, triple, raw):
        nonlocal line
        buf = []
        start_line = line
        while i < n:
            c = text[i]
            if c == '\n':
                line += 1
            if c == '\\' and not raw:
                nx = text[i + 1] if i + 1 < n else ''
                buf.append({'n': '\n', 't': ' ', "'": "'", '"': '"', '\\': '\\', '$': '$'}.get(nx, nx))
                i += 2
                continue
            if triple and text.startswith(q * 3, i):
                i += 3
                break
            if not triple and c == q:
                i += 1
                break
            if c == '$' and not raw and i + 1 < n and text[i + 1] == '{':
                out.append((''.join(buf), start_line)); buf = []
                i = code(i + 2, 1)
                continue
            if c == '$' and not raw and i + 1 < n and (text[i + 1].isalpha() or text[i + 1] == '_'):
                out.append((''.join(buf), start_line)); buf = []
                i += 1
                while i < n and (text[i].isalnum() or text[i] == '_'):
                    i += 1
                continue
            buf.append(c)
            i += 1
        out.append((''.join(buf), start_line))
        return i

    def code(i, depth):
        """depth>0: ${ ... } ichida — mos } gacha"""
        nonlocal line
        while i < n:
            c = text[i]
            if c == '\n':
                line += 1; i += 1; continue
            if text.startswith('//', i):
                while i < n and text[i] != '\n':
                    i += 1
                continue
            if text.startswith('/*', i):
                j = text.find('*/', i + 2)
                j = n if j < 0 else j + 2
                line += text.count('\n', i, j)
                i = j; continue
            if c in '\'"':
                raw = i > 0 and text[i - 1] == 'r' and (i < 2 or not text[i - 2].isalnum())
                if text.startswith(c * 3, i):
                    i = string(i + 3, c, True, raw)
                else:
                    i = string(i + 1, c, False, raw)
                continue
            if depth:
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0:
                        return i + 1
            i += 1
        return i

    code(0, 0)
    return out


WORD = re.compile(r"[A-Za-zʻ’'‘]{3,}")
IGN = {w.lower() for w in '''Oftob Building Telegram Instagram Facebook WhatsApp PDF USD UZS RUB EUR TJS KZT KGS API URL SMS PIN Email Google Apple Android iOS Web
Excel Word JSON CSV GPS QR TJM MCHJ YaTT Ctrl KPI CRM ERP Tab Esc Shift Alt dev Yandex OpenAI Claude ChatGPT Gemini DeepSeek GPT Bot Chat Pro Plus Lite
SMTP TLS SSL Click Payme Uzcard Humo Meta Token Secret Access Page for Developers Verify token Start http https www com org uz html png jpg jpeg webp gif
null true false int bool string map list set num double void var final const await async return Future'''.split()}


def main():
    rows = {}
    for f in glob.glob(os.path.join(LIB, '**', '*.dart'), recursive=True):
        b = os.path.basename(f)
        if b == 'l10n_dict.dart' or '\\platform\\' in f or b.startswith('platform_') or b in ('firebase_config.dart',):
            continue
        text = open(f, encoding='utf-8').read()
        rel = os.path.relpath(f, LIB)
        for s, ln in lex(text):
            if len(s) < 3 or not re.search(r'[A-Za-z]{3}', s):
                continue
            if re.fullmatch(r"[A-Za-z0-9_:./\-#@%?=&+,;]+", s) and ' ' not in s and not s[0].isupper():
                continue  # kalit / identifikator / url
            if re.search(r"[{}();=<>\[\]|]|\\|\.dart|^[a-z]+[A-Z]\w*$", s):
                continue
            t = translate(s)
            ws = [w for w in WORD.findall(t) if w.lower() not in IGN]
            if not ws:
                continue
            rows.setdefault(s, (f'{rel}:{ln}', ws[:5]))
    items = sorted(rows.items(), key=lambda kv: (kv[1][0].split(':')[0], int(kv[1][0].split(':')[1])))
    with open(os.path.join(ROOT, 'audit2.txt'), 'w', encoding='utf-8') as fh:
        for s, (at, ws) in items:
            fh.write(f"{at} | {s.replace(chr(10), '⏎')} | {','.join(ws)}\n")
    print('tarjimasiz:', len(items))


main()
