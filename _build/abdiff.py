"""Diff the DECISION STREAM of two Strategy Tester passes.

The question this answers is narrow: did the two binaries place the same
orders, at the same modelled times, at the same prices, in the same order?
Nothing here judges whether either result is good. A pass that lost money on
both sides and lost it identically is a PASS for this test.

WHY THE COMPARISON IS ON ORDERS AND NOT ON THE SUMMARY
Two runs can reach the same final balance by different routes, and a summary
line hides that. The tester logs every order and deal it fills, so the deal
stream is the finest-grained record of what the EA actually decided, and it is
the only one that can distinguish "traded the same" from "scored the same".

Serial numbers are normalised away before comparing. They renumber from one on
every pass and are not a decision; a single extra deal early in a run would
otherwise shift every later number and report hundreds of false differences.

Usage:
    python abdiff.py <baseline.log> <current.log>

Both raw tester logs (UTF-16LE, tab-delimited) and the UTF-8 extracts written
by abcompare.ps1 are accepted.
"""
import re
import sys

# The EA's own counters. These are not the decision stream, but a difference
# here localises a divergence to a stage of the funnel, which is the first
# thing worth knowing when the deal streams disagree.
COUNTER_PATTERNS = [
    r'SCALP FUNNEL:.*',
    r'ENTRY GATES:.*',
    r'blocked by:.*',
    r'entries=\d+.*',
    r'risk engine:.*',
    r'final balance.*',
    r'cost model:.*',
]

TRADE_RE = re.compile(
    r'\b(?:deal|order|position)\s+#\d+.*|'
    r'\b(?:market|instant|pending)\s+(?:buy|sell)\b.*',
    re.IGNORECASE)
MODEL_DT_RE = re.compile(r'\b(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})\b')
SERIAL_RE = re.compile(r'#\d+')
def read_log(path):
    """Decode a tester log without being told its encoding.

    Agent logs are UTF-16LE; the extracts abcompare.ps1 writes are UTF-8. A
    wrong guess here does not fail loudly, it produces text full of NULs that
    silently matches nothing - so the BOM and the NUL density are both checked.
    """
    with open(path, 'rb') as fh:
        raw = fh.read()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        text = raw.decode('utf-16', errors='replace')
    else:
        head = raw[:400]
        nulls = sum(1 for i in range(1, len(head), 2) if head[i] == 0)
        if nulls > len(head) / 8:
            text = raw.decode('utf-16-le', errors='replace')
        else:
            text = raw.decode('utf-8-sig', errors='replace')
    return text.replace('\r\n', '\n').split('\n')


def message_of(line):
    """Strip the terminal's own prefix, keeping only what was logged.

    The prefix carries a wall-clock time that differs between two passes by
    construction. Leaving it in would make every line differ and the test
    would always fail.
    """
    if '\t' in line:
        return line.split('\t')[-1].strip()
    # `code 0 HH:MM:SS.mmm  message` when the log is space-aligned.
    return re.sub(r'^\S+\s+\d+\s+(?:\d\d:\d\d:\d\d\.\d+\s+)?', '', line).strip()


def extract(lines):
    """Return (trade stream, counter lines). The stream keeps order."""
    trades, counters = [], []
    for line in lines:
        msg = message_of(line)
        if not msg:
            continue
        hit = TRADE_RE.search(msg)
        if hit:
            dt = MODEL_DT_RE.search(msg)
            body = SERIAL_RE.sub('#', hit.group(0)).strip()
            trades.append(((dt.group(1) if dt else ''), body, msg))
            continue
        for pat in COUNTER_PATTERNS:
            m = re.search(pat, msg)
            if m:
                counters.append(m.group(0).strip())
                break
    return trades, counters
PASS_START_RE = re.compile(r'testing of .*\.ex5 from .* started', re.IGNORECASE)


def last_pass(lines, label):
    """Trim a log down to its FINAL tester pass.

    MT5 appends every pass of the day to one file, and a capture that keeps
    more than one turns a comparison into nonsense: the extra passes ran under
    other inputs, so the counters printed below would be a mixture and the
    trade streams would differ for reasons that have nothing to do with the
    two binaries. This is done here as well as at capture time because the
    tool has to be safe to point at a raw daily log.
    """
    marks = [i for i, l in enumerate(lines) if PASS_START_RE.search(message_of(l))]
    if len(marks) <= 1:
        return lines
    print('  NOTE %s contains %d tester passes; using the last one '
          '(from line %d).' % (label, len(marks), marks[-1] + 1))
    return lines[marks[-1]:]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    a_path, b_path = sys.argv[1], sys.argv[2]
    a_lines, b_lines = read_log(a_path), read_log(b_path)
    a_lines = last_pass(a_lines, 'BASELINE')
    b_lines = last_pass(b_lines, 'CURRENT')
    a_tr, a_ct = extract(a_lines)
    b_tr, b_ct = extract(b_lines)

    # A capture holding more than one result is not one pass, whatever the
    # pass markers said. The agent log and the Tester log each span the whole
    # day, so a capture that concatenates them can carry six earlier passes
    # with no marker in the second file to trim on. Refusing here is the
    # difference between a wrong answer and no answer.
    for label, ct in (('BASELINE', a_ct), ('CURRENT', b_ct)):
        n = len([x for x in ct if 'final balance' in x])
        if n > 1:
            print('\nVERDICT: INVALID - the %s capture contains %d final-balance '
                  'lines, so it\n         holds more than one tester pass. '
                  'Re-capture before comparing;\n         anything read from '
                  'this would be a mixture of runs.' % (label, n))
            return 2

    print('BASELINE %s  %d lines, %d trade events'
          % (a_path, len(a_lines), len(a_tr)))
    print('CURRENT  %s  %d lines, %d trade events'
          % (b_path, len(b_lines), len(b_tr)))

    # A pass that logged nothing is not evidence of agreement. Without this
    # guard two empty logs would compare equal and report a clean result.
    if not a_tr and not b_tr:
        print('\nVERDICT: INCONCLUSIVE - neither log contains a single trade '
              'event.\n         Nothing was compared. Check that both passes '
              'actually ran.')
        return 2

    keys_a = [(t[0], t[1]) for t in a_tr]
    keys_b = [(t[0], t[1]) for t in b_tr]

    print('\n--- counters ---')
    for label, ct in (('base', a_ct), ('curr', b_ct)):
        for line in ct:
            print('  %s  %s' % (label, line[:150]))

    print('\n--- decision stream ---')
    if keys_a == keys_b:
        print('  IDENTICAL: %d trade events, same modelled times, same '
              'prices,' % len(keys_a))
        print('             same order.')
        verdict = ('PASS - the two binaries placed the same orders. On this '
                   'period,\n         with fixes 1 and 3 configured off, '
                   'fixes 2 and 4 moved nothing.')
        rc = 0
    else:
        n = min(len(keys_a), len(keys_b))
        first = next((i for i in range(n) if keys_a[i] != keys_b[i]), n)
        print('  DIFFERENT: %d vs %d trade events; first divergence at event '
              '%d' % (len(keys_a), len(keys_b), first + 1))
        lo = max(0, first - 2)
        print('\n  last agreeing events and the divergence:')
        for i in range(lo, min(first + 3, n)):
            mark = '  ' if keys_a[i] == keys_b[i] else '->'
            print('  %s base[%d] %s' % (mark, i + 1, a_tr[i][2][:130]))
            print('  %s curr[%d] %s' % (mark, i + 1, b_tr[i][2][:130]))
        if first >= n:
            longer, name = ((a_tr, 'base') if len(keys_a) > len(keys_b)
                            else (b_tr, 'curr'))
            print('\n  streams agree up to event %d; %s continues:' % (n, name))
            for t in longer[n:n + 4]:
                print('     %s' % t[2][:130])
        verdict = ('FAIL - the decision streams differ. Either a fix claimed '
                   'to be\n         observation-only is not, or the two passes '
                   'were not run under\n         identical conditions. Check '
                   'the input reconciliation first.')
        rc = 1

    print('\nVERDICT: %s' % verdict)
    return rc


if __name__ == '__main__':
    sys.exit(main())
