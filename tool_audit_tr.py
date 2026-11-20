"""Tarjima auditi: UI matnlarini topadi va lug'at (kDict) bilan solishtirib, tarjima qilinmay qolgan so'zlari bor matnlarni chiqaradi.
Ishlatish: python tool_audit_tr.py [--all]   (natija: audit_tr.txt)"""
import re, sys, glob, os, json

ROOT = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(ROOT, 'lib')

# --- lug'at ---
src = open(os.path.join(LIB, 'l10n_dict.dart'), encoding='utf-8').read()
DICT = {}
for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*\[\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]', src, re.M):
    k = bytes(m.group(1), 'utf-8').decode('unicode_escape', errors='ignore') if '\\' in m.group(1) else m.group(1)
    k = m.group(1).replace('\\"', '"').replace("\\'", "'").replace('\\$', '$').replace('\\n', '\n')
    DICT[k] = (m.group(2), m.group(3))
KEYS = sorted(DICT, key=len, reverse=True)
LET = re.compile(r'\w', re.U)


def translate(s):
    t = s.strip()
    if t in DICT:
        return DICT[t][0]
    out = s
    for k in KEYS:
        if k not in out:
            continue
        pre = r"(?<![\w'’‘ʻʼ])" if re.match(r'[^\W\d_]', k[0], re.U) else ''
        post = r"(?![\w'’‘ʻʼ])" if re.match(r'[^\W\d_]', k[-1], re.U) else ''
        out = re.sub(pre + re.escape(k) + post, lambda _m, k=k: DICT[k][0], out)
    return out


# --- dart satrlarini topish ---
STR = r"""(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")"""
CTX = re.compile(r'(?:\bText|\btr|\bconst Text|\b_Section\(\s*title|\bSnack\w*|\btitle|\blabel|\bhint|\bhintText|\blabelText|\btooltip|\bsubtitle|\bsub|\bmessage|\bhelperText|\bbig|\bcaption|\b_Empty|\bshowMsg|\btoast|\bEmpty\w*)\s*[:(]\s*(?:const\s+)?' + STR)
PLAIN = re.compile(STR)

SKIP_FILES = {'l10n_dict.dart'}
WORD = re.compile(r"[A-Za-zʻ’'‘][A-Za-zʻ’'‘]+", re.U)
# lotincha, lekin tarjimasiz qoladigan so'zlar (nomlar, birliklar, texnik)
IGNORE = {w.lower() for w in '''Oftob Building Telegram Instagram Facebook WhatsApp OK PDF USD UZS RUB EUR TJS KZT KGS API ID URL SMS PIN Email Google Apple Android iOS Web
Excel Word JSON CSV GPS QR Wi Fi PM AM TJM MCHJ XK YaTT Ctrl K Enter min max kg mm cm km USDT HTTP HTTPS SIP VIP KPI CRM ERP MTX Tab Esc Shift Alt
dev Yandex OpenAI Claude GPT AI Bot Chat Pro Plus Lite'''.split()}


def uz_like(w):
    return True


def collect(strict=True):
    found = {}
    for f in glob.glob(os.path.join(LIB, '**', '*.dart'), recursive=True):
        if os.path.basename(f) in SKIP_FILES:
            continue
        text = open(f, encoding='utf-8').read()
        rel = os.path.relpath(f, LIB)
        rx = PLAIN if '--all' in sys.argv else CTX
        for m in rx.finditer(text):
            s = m.group(1) if m.group(1) is not None else m.group(2)
            if s is None:
                continue
            s = s.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n').replace('\\$', '$')
            line = text.count('\n', 0, m.start()) + 1
            found.setdefault(s, []).append(f'{rel}:{line}')
    return found


def leftovers(s):
    t = translate(s)
    t = re.sub(r'\$\{[^}]*\}|\$\w+', ' ', t)  # interpolatsiyalar
    ws = [w for w in WORD.findall(t) if len(w) >= 3 and w.lower() not in IGNORE]
    return t, ws


def main():
    found = collect()
    rows = []
    for s, where in found.items():
        if not re.search(r"[A-Za-z]{3}", s):
            continue
        if re.fullmatch(r"[a-z_0-9:./\-]+", s):  # identifikator / kalit
            continue
        if s.startswith(('http', 'assets/', 'package:', '/')):
            continue
        t, ws = leftovers(s)
        if ws:
            rows.append((s, ws, where[0], len(where)))
    rows.sort(key=lambda r: (r[2].split(':')[0], int(r[2].split(':')[1])))
    with open(os.path.join(ROOT, 'audit_tr.txt'), 'w', encoding='utf-8') as fh:
        for s, ws, w, n in rows:
            fh.write(json.dumps({'s': s, 'left': ws[:6], 'at': w, 'n': n}, ensure_ascii=False) + '\n')
    print('dict', len(DICT), 'topilgan matn', len(found), 'tarjimasiz', len(rows))


main()
