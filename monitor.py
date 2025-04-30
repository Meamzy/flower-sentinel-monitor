#!/usr/bin/env python3
import os
from dotenv import load_dotenv
import sqlite3, time, psutil, shutil, datetime, asyncio, glob
from telegram import Bot

# ──── CONFIG ───────────────────────────────────────────────────────────
# Load environment variables from a .env file in the script directory
from pathlib import Path
BASE_DIR = Path(__file__).parent.resolve()
load_dotenv(BASE_DIR / '.env')

BOT_TOKEN = os.getenv('BOT_TOKEN')
CHAT_ID   = os.getenv('CHAT_ID')
DB_PATH   = os.getenv('DB_PATH', str(BASE_DIR / 'metrics.db'))
# ────────────────────────────────────────────────────────────────────────

print(DB_PATH)
# Initialize the Telegram Bot
bot = Bot(token=BOT_TOKEN)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
    CREATE TABLE IF NOT EXISTS samples (
        ts        INTEGER PRIMARY KEY,
        conns     INTEGER,
        cpu_temp  REAL,
        cpu_load  REAL,
        mem_used  REAL
    )""")
    conn.commit()
    return conn


def read_cpu_temp():
    # First try psutil sensors
    temps_by_sensor = psutil.sensors_temperatures() or {}
    if temps_by_sensor:
        # Flatten all temperature entries
        all_temps = []
        for entries in temps_by_sensor.values():
            all_temps.extend([t.current for t in entries])
        if all_temps:
            return sum(all_temps) / len(all_temps)
    # Fallback: read thermal_zone CPU-related entries
    cpu_temps = []
    for zone in glob.glob('/sys/class/thermal/thermal_zone*'):
        try:
            with open(f"{zone}/type") as f:
                ttype = f.read().strip().lower()
            if 'cpu' in ttype:
                with open(f"{zone}/temp") as f:
                    cpu_temps.append(int(f.read().strip()) / 1000.0)
        except Exception:
            continue
    if cpu_temps:
        return sum(cpu_temps) / len(cpu_temps)
    # Last fallback: read first zone
    try:
        first = glob.glob('/sys/class/thermal/thermal_zone*/temp')[0]
        with open(first) as f:
            return int(f.read().strip()) / 1000.0
    except Exception:
        return 0.0


def sample(conn):
    ts = int(time.time())
    # Active TCP connections (ESTABLISHED)
    conns = len([c for c in psutil.net_connections(kind='inet') if c.status == 'ESTABLISHED'])

    # CPU temperature
    cpu_temp = read_cpu_temp()

    # CPU load over 1s
    cpu_load = psutil.cpu_percent(interval=1)
    # RAM usage percent
    mem = psutil.virtual_memory()
    mem_used = mem.percent

    conn.execute(
        "INSERT INTO samples VALUES (?,?,?,?,?)",
        (ts, conns, cpu_temp, cpu_load, mem_used)
    )
    conn.commit()


def report(conn):
    now = int(time.time())
    hour_ago = now - 3600
    c = conn.cursor()
    c.execute("SELECT * FROM samples WHERE ts>=? ORDER BY ts", (hour_ago,))
    rows = c.fetchall()
    if not rows:
        return

    new_conns = rows[-1][1] - rows[0][1]
    temps = [r[2] for r in rows]
    loads = [r[3] for r in rows]
    mems  = [r[4] for r in rows]

    # Disk usage (root partition)
    st = shutil.disk_usage('/')
    total_storage = st.total / (1024 ** 3)
    used_storage  = (st.total - st.free) / (1024 ** 3)

    cores     = psutil.cpu_count()
    total_ram = psutil.virtual_memory().total / (1024 ** 3)

    text = f"""
⚙️ *Server hourly report* ({datetime.datetime.now():%Y-%m-%d %H:%M})

• New connections (last 1 h): `{new_conns:+d}`
• CPU temp: avg `{sum(temps)/len(temps):.1f}°C`, max `{max(temps):.1f}°C`
• CPU load: avg `{sum(loads)/len(loads):.1f}%`, max `{max(loads):.1f}%`  ({cores} cores)
• RAM used: avg `{sum(mems)/len(mems):.1f}%`, max `{max(mems):.1f}%`  ({total_ram:.1f} GB)
• Disk used: `{used_storage:.1f} GB` / `{total_storage:.1f} GB`
"""
    asyncio.run(bot.send_message(chat_id=CHAT_ID, text=text, parse_mode='Markdown'))


if __name__ == '__main__':
    conn = init_db()
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'report':
        report(conn)
    else:
        sample(conn)
    conn.close()

# ──── Example .env file ─────────────────────────────────────────────────
# Place this .env alongside monitor.py or point load_dotenv() to its location
# BOT_TOKEN and CHAT_ID are required; DB_PATH is optional (defaults to monitor directory)
#
# BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
# CHAT_ID=987654321
# DB_PATH=/home/meo/server-monitor/metrics.db
