"""Who is on the Pirates server right now, by pirate, and may a restart go ahead (11-20; player bots 11-22).

A restart kicks everyone. FORCE=1 covers the regular players and the always-on player bots (a player bot logs back in by itself
after a kick, and a kick is never a strike); any other pirate on (claude1, claude2, np11180052 = a test bot run, ~10
min; the host) means wait until it logs off. 18:38 on 11-20 a FORCE restart kicked a bot mid-run because the check only
counted connections.
Player bots are listed in /opt/pirates-online/player-bots.txt, one bot per line: its pirate id, account id and/or login
name, '#' starts a comment. The pbots lane appends a line per new bot, so a new bot needs no code change. The test bots'
and the host's ids never count as player bots, even when listed.
Each live connection on :7100 is traced through astrond's event log for this run (one file per astrond start):
peer address -> client-connected (Client channel) -> accountLogin (user) -> avatarChosen (pirate).
Prints one line per connection, a 'count:' line, then the verdict. Exit 0 = clear (nobody on), 3 = force (only the regular players
and player bots), 4 = wait. The one-restart-an-hour rule is for the regular players: read 'count: regulars N', not the exit code.
Install: /opt/pirates-online/whos-on.py; run: timeout 30 prlimit --as=3000000000 -- python3.9 -I whos-on.py
Sim: WHOS_ON_PEERS (space-separated peer addresses instead of ss), WHOS_ON_LOGS, WHOS_ON_RUN, WHOS_ON_BOTS."""
import glob, json, os, subprocess, sys

LOGS = os.environ.get('WHOS_ON_LOGS', '/opt/pirates-online/pirates-online-classic/astron/logs')
RUN = os.environ.get('WHOS_ON_RUN', '/opt/pirates-online/run')
BOTS = os.environ.get('WHOS_ON_BOTS', '/opt/pirates-online/player-bots.txt')
REGULARS = {100000656: 'Player1', 100000665: 'Player2'}
NAMES = {100000001: 'claude1, a bot run', 100000004: 'claude2, a bot run', 100000596: 'np11180052, a bot run',
         100000170: 'the host'}
# test runs and the host always mean wait (account, pirate and login of claude1, claude2, np11180052; the host's pirate)
NEVER = {100000000, 100000001, 'claude1', 100000003, 100000004, 'claude2', 100000595, 100000596, 'np11180052',
         100000170}

pbots = set()
try:
    for line in open(BOTS, errors='replace'):
        for tok in line.split('#')[0].split():
            key = int(tok) if tok.isdigit() else tok
            if key in NEVER:
                print('note: %s in %s is a test bot or the host, never a player bot; ignored' % (tok, BOTS))
            else:
                pbots.add(key)
except OSError:
    pass

peers = []
if 'WHOS_ON_PEERS' in os.environ:
    peers = os.environ['WHOS_ON_PEERS'].split()
else:
    for line in subprocess.run(['ss', '-tnH', 'state', 'established', '( sport = :7100 )'],
                               capture_output=True, text=True).stdout.splitlines():
        if line.split():
            peers.append(line.split()[-1])

conn, gone, login, avatar = {}, set(), {}, {}
logs = sorted(glob.glob(LOGS + '/events-*.log'))
if peers and logs:
    try:
        started = os.stat('/proc/' + open(RUN + '/astrond.pid').read().strip()).st_mtime
    except OSError:
        started = None
    if started and os.path.getmtime(logs[-1]) < started - 5:
        print('note: the newest event log is older than astrond; the names below may be stale')
    for line in open(logs[-1], errors='replace'):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t, who = e.get('type'), e.get('sender', '')
        if t == 'client-connected':
            conn[e.get('remote_address')] = who
            gone.discard(who)
        elif t in ('client-lost', 'client-ejected'):
            gone.add(who)
        elif t == 'accountLogin':
            login['Client:%s' % e.get('target')] = (e.get('accountId'), e.get('userId'), e.get('_time', '')[11:19])
        elif t == 'avatarChosen':
            avatar[e.get('target')] = e.get('avId')

regulars = bots = others = 0
for peer in peers:
    ch = conn.get(peer)
    acct, user, since = login.get(ch, (None, None, ''))
    av = avatar.get(acct)
    ids = {av, acct, user} - {None}
    if av in REGULARS:
        regulars += 1
        who = '%s (%s)' % (REGULARS[av], av)
    elif ids & pbots and not ids & NEVER:
        bots += 1
        who = 'player bot, pirate %s' % av if av else 'player bot, no pirate chosen yet'
    else:
        others += 1
        who = ('pirate %s, %s' % (av, NAMES.get(av, 'a test pirate')) if av else
               'no pirate chosen yet' if user else 'not logged in yet' if ch else 'not in the event log')
    print('on: %s %s user %s since %s: %s' % (peer, ch or '?', user or '?', since or '?', who))

print('count: regulars %d, player bots %d, others %d' % (regulars, bots, others))
if not peers:
    print('verdict: clear (nobody on); restart goes ahead')
    sys.exit(0)
if not others:
    print('verdict: force (only the regular players: %d, player bots: %d); FORCE=1 restart is OK for a tested fix' % (regulars, bots))
    sys.exit(3)
print('verdict: wait (%d not a boy or player bot); restart after they log off (a bot run takes ~10 min), then FORCE if a boy is on'
      % others)
sys.exit(4)
