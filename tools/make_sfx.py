"""Synthesise Tumbang Henyo's simple sound effects as 16-bit mono WAVs.

Every sound is built from sines, noise and filters, then normalised to a
peak level picked for its role (UI ticks quiet, impacts loud) so they sit
together at 0 dB in the game. Loops are crossfaded so they repeat seamlessly.
"""
import os
import sys
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


# --- building blocks -----------------------------------------------------------

def T(d):
    return np.arange(int(SR * d)) / SR


def sweep(f0, f1, d, curve="exp"):
    """Sine whose pitch glides from f0 to f1 over d seconds."""
    t = T(d)
    if curve == "exp" and f0 > 0 and f1 > 0:
        f = f0 * (f1 / f0) ** (t / d)
    else:
        f = f0 + (f1 - f0) * t / d
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def tone(f, d, wave="sine", phase=0.0):
    t = T(d)
    p = 2 * np.pi * f * t + phase
    if wave == "sine":
        return np.sin(p)
    if wave == "tri":
        return 2 / np.pi * np.arcsin(np.sin(p))
    if wave == "square":
        # band-limited-ish square: first odd harmonics
        return sum(np.sin(p * k) / k for k in (1, 3, 5, 7, 9)) * 4 / np.pi
    if wave == "saw":
        return sum(np.sin(p * k) / k for k in range(1, 14)) * 2 / np.pi
    raise ValueError(wave)


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def filt(x, kind, f, order=2):
    if kind == "band":
        sos = butter(order, [f[0] / (SR / 2), f[1] / (SR / 2)], btype="band", output="sos")
    else:
        sos = butter(order, f / (SR / 2), btype=kind, output="sos")
    return sosfilt(sos, x)


def sweep_band(x, f0, f1, width=0.6, steps=48):
    """Band-pass noise whose centre glides f0 -> f1 (block-wise)."""
    out = np.zeros_like(x)
    n = len(x)
    edges = np.linspace(0, n, steps + 1).astype(int)
    for i in range(steps):
        c = f0 * (f1 / f0) ** (i / max(steps - 1, 1))
        lo, hi = c * (1 - width / 2), min(c * (1 + width / 2), SR / 2 - 100)
        seg = filt(x, "band", (lo, hi))
        out[edges[i]:edges[i + 1]] = seg[edges[i]:edges[i + 1]]
    return out


def env_exp(d, decay, attack=0.002):
    t = T(d)
    e = np.exp(-t / decay)
    a = np.clip(t / attack, 0, 1) if attack > 0 else 1
    return e * a


def env_ar(d, attack, release):
    t = T(d)
    e = np.ones_like(t)
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    if release > 0:
        e *= np.clip((d - t) / release, 0, 1)
    return e


def env_hump(d, peak=0.4):
    """Rise to a peak (fraction of d), then fall: swells and whooshes."""
    t = T(d) / d
    up = np.clip(t / peak, 0, 1)
    down = np.clip((1 - t) / (1 - peak), 0, 1)
    return np.sin(up * np.pi / 2) ** 2 * np.sin(down * np.pi / 2) ** 2


def pad(x, d):
    n = int(SR * d)
    return np.pad(x, (0, max(0, n - len(x))))[:max(n, len(x))]


def mix(*parts):
    """mix((signal, offset_seconds, gain), ...)"""
    n = max(int(o * SR) + len(s) for s, o, g in parts)
    out = np.zeros(n)
    for s, o, g in parts:
        i = int(o * SR)
        out[i:i + len(s)] += s * g
    return out


def bell(f0, d, partials, decay):
    """Inharmonic struck tone: partials = [(ratio, amp, decay_mult)]."""
    t = T(d)
    out = np.zeros_like(t)
    for r, a, dm in partials:
        out += a * np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay * dm))
    return out


def fade(x, fin=0.002, fout=0.01):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def loopify(x, xfade):
    """Crossfade the tail into the head so the clip loops without a seam."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.linspace(0, 1, n)
    joined = tail * (1 - w) + head * w
    return np.concatenate([body, joined])


def save(name, x, peak_db, loop=False):
    if not loop:
        x = fade(x)
    x = x - np.mean(x) if loop else x
    p = np.max(np.abs(x)) or 1.0
    x = x / p * (10 ** (peak_db / 20))
    data = np.int16(np.clip(x, -1, 1) * 32767)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, data)
    print(f"{name:16s} {len(x) / SR:5.2f}s  peak {peak_db:+.0f} dB{'  (loop)' if loop else ''}")


# --- UI ---------------------------------------------------------------------------

def ui():
    # Hover: a tiny soft tick so it never gets tiring.
    h = tone(1850, 0.04) * env_exp(0.04, 0.008) + 0.3 * tone(3700, 0.04) * env_exp(0.04, 0.004)
    save("ui_hover", h, -20)
    # Click: a round "pop" (pitch drops) with a crisp front.
    c = sweep(1300, 560, 0.07) * env_exp(0.07, 0.022)
    c += 0.35 * filt(noise(0.07), "high", 2500) * env_exp(0.07, 0.004)
    save("ui_click", c, -8)
    # Back: the same pop, lower.
    b = sweep(820, 380, 0.08) * env_exp(0.08, 0.026)
    b += 0.3 * filt(noise(0.08), "high", 1800) * env_exp(0.08, 0.004)
    save("ui_back", b, -9)
    # Tick: sliders and toggles.
    save("ui_tick", tone(2600, 0.025) * env_exp(0.025, 0.006), -14)
    # Error / not allowed: two low buzzes.
    e1 = filt(tone(170, 0.08, "square"), "low", 1600) * env_ar(0.08, 0.004, 0.02)
    save("ui_error", mix((e1, 0, 1), (e1, 0.12, 1)), -13)
    # Pop: tips, cards and popups (a bubbly "bloop").
    p = sweep(380, 980, 0.11) * env_exp(0.11, 0.05, 0.004)
    save("ui_pop", p, -9)
    # Whoosh: the menu camera gliding between panels.
    w = sweep_band(noise(0.5), 350, 1900, 0.8) * env_hump(0.5, 0.45)
    save("ui_whoosh", w, -14)
    # Pause: a soft low "thup".
    save("ui_pause", sweep(320, 140, 0.12) * env_exp(0.12, 0.05), -8)
    # Buy: "ka-ching" (two bright coin strikes and a shimmer).
    coin = [(1, 1, 1), (2.76, 0.5, 0.5), (5.4, 0.25, 0.3)]
    k = mix((bell(1568, 0.5, coin, 0.12), 0, 0.8), (bell(2093, 0.7, coin, 0.18), 0.07, 1.0),
            (filt(noise(0.4), "high", 6000) * env_exp(0.4, 0.1), 0.07, 0.15))
    save("ui_buy", k, -4)
    # Equip: two quick rising plucks.
    eq = mix((tone(660, 0.2, "tri") * env_exp(0.2, 0.05), 0, 1), (tone(990, 0.3, "tri") * env_exp(0.3, 0.08), 0.07, 1))
    save("ui_equip", eq, -8)
    # Join (a student joined the class): a friendly two-note blip.
    j = mix((tone(880, 0.12) * env_exp(0.12, 0.04), 0, 1), (tone(1320, 0.18) * env_exp(0.18, 0.06), 0.08, 1))
    save("join", j, -9)
    # Whistle: the class game starts (a referee-style trill).
    t = T(0.7)
    f = 2900 + 120 * np.sin(2 * np.pi * 32 * t)
    wh = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ar(0.7, 0.02, 0.12)
    wh += 0.25 * filt(noise(0.7), "band", (2400, 3600)) * env_ar(0.7, 0.02, 0.12)
    save("whistle", wh, -11)
    # Achievement: the same E6 -> B6 ding the toast used (now a file).
    a = mix((tone(1318.5, 0.9) * env_exp(0.9, 0.18), 0, 0.5), (tone(2637, 0.9) * env_exp(0.9, 0.18), 0, 0.075),
            (tone(1975.5, 0.8) * env_exp(0.8, 0.18), 0.11, 0.7), (tone(3951, 0.8) * env_exp(0.8, 0.18), 0.11, 0.105))
    save("achievement", a, -6)


# --- Quiz ---------------------------------------------------------------------------

def quiz():
    # The question card swishes up.
    save("quiz_open", sweep_band(noise(0.28), 500, 2600, 0.7) * env_hump(0.28, 0.3), -14)
    # Clock ticks for the last seconds (a woodblock).
    tk = tone(1750, 0.05) * env_exp(0.05, 0.012) + 0.4 * filt(noise(0.05), "band", (1500, 4000)) * env_exp(0.05, 0.003)
    save("tick", tk, -12)
    tku = tone(2350, 0.06) * env_exp(0.06, 0.016) + 0.5 * filt(noise(0.06), "band", (2000, 5000)) * env_exp(0.06, 0.003)
    save("tick_urgent", tku, -6)
    # Time's up: a buzzer.
    bz = (tone(110, 0.55, "saw") + tone(116.5, 0.55, "saw")) * 0.5
    save("timeout", filt(bz, "low", 1800) * env_ar(0.55, 0.01, 0.12), -6)
    # Hint: a sparkle (rising plinks + shimmer).
    notes = [1046.5, 1318.5, 1568, 2093]
    parts = [(tone(f, 0.4) * env_exp(0.4, 0.09), i * 0.045, 1.0) for i, f in enumerate(notes)]
    parts.append((filt(noise(0.5), "high", 7000) * env_hump(0.5, 0.25), 0.0, 0.25))
    save("hint", mix(*parts), -6)
    # Tansan gained: one small coin clink.
    save("coin", bell(2637, 0.25, [(1, 1, 1), (1.5, 0.4, 0.6), (2.76, 0.3, 0.4)], 0.05), -9)


# --- Throw ---------------------------------------------------------------------------

def throw():
    # Charge: a steady hum the game bends in pitch with the power (loop).
    d = 1.0
    t = T(d)
    hum = (np.sin(2 * np.pi * 220 * t) + 0.5 * np.sin(2 * np.pi * 330 * t) + 0.25 * np.sin(2 * np.pi * 440 * t))
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 8 * t)
    save("charge", hum, -14, loop=True)
    # Throw: a quick whoosh.
    save("throw", sweep_band(noise(0.26), 2400, 600, 0.7) * env_hump(0.26, 0.25), -5)
    # Heavy throw (Mama's hangers and walis): lower and longer.
    save("throw_heavy", sweep_band(noise(0.4), 1400, 260, 0.8) * env_hump(0.4, 0.3), -4)
    # Tsinelas slaps the concrete.
    s = filt(noise(0.06), "low", 3200) * env_exp(0.06, 0.01) + 0.8 * sweep(150, 70, 0.06) * env_exp(0.06, 0.02)
    save("slap_ground", s, -6)
    # Lata hit: a tin can clank, then it bounces and rattles.
    can = [(1, 1, 1), (2.52, 0.7, 0.7), (4.13, 0.5, 0.5), (6.69, 0.35, 0.35), (9.4, 0.25, 0.25)]
    hit = bell(520, 0.6, can, 0.16) + 0.6 * filt(noise(0.6), "high", 2500) * env_exp(0.6, 0.006)
    bounce1 = bell(560, 0.3, can, 0.07)
    bounce2 = bell(540, 0.25, can, 0.05)
    rattle = filt(noise(0.35), "band", (1800, 6000)) * env_exp(0.35, 0.08) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 26 * T(0.35))))
    save("lata_hit", mix((hit, 0, 1), (bounce1, 0.17, 0.45), (bounce2, 0.29, 0.3), (rattle, 0.33, 0.18)), -2)
    # Lata stood back up: one soft clink and a thud.
    save("lata_set", mix((bell(600, 0.25, can, 0.05), 0, 0.6), (sweep(160, 90, 0.08) * env_exp(0.08, 0.02), 0, 0.7)), -9)
    # Tsinelas bonks a taya.
    save("bonk", sweep(320, 170, 0.09) * env_exp(0.09, 0.03) + 0.3 * filt(noise(0.09), "low", 2500) * env_exp(0.09, 0.008), -6)
    # Miss: "sablay" (two falling notes, the second sagging).
    n1 = tone(392, 0.2, "tri") * env_ar(0.2, 0.01, 0.05)
    n2 = sweep(311, 262, 0.42, "lin")
    n2 = 2 / np.pi * np.arcsin(n2) * env_ar(0.42, 0.01, 0.2)
    save("miss", mix((n1, 0, 1), (n2, 0.2, 1)), -10)
    # Bullseye: a big slow-mo boom, then a bright chord sting.
    boom = sweep(95, 38, 0.8) * env_exp(0.8, 0.25, 0.004) + 0.5 * filt(noise(0.8), "low", 900) * env_exp(0.8, 0.12)
    chord = sum(tone(f, 1.3) * env_exp(1.3, 0.45, 0.01) for f in (1046.5, 1568, 2093)) / 3
    sparkle = filt(noise(1.0), "high", 7000) * env_hump(1.0, 0.15)
    save("bullseye", mix((boom, 0, 1), (chord, 0.08, 0.55), (sparkle, 0.08, 0.15)), -1)
    # Wind: a soft breathing gust (loop; the game sets its volume by wind strength).
    d = 5.0
    w = filt(noise(d), "low", 700) * 0.7 + 0.3 * filt(noise(d), "band", (900, 1600))
    t = T(d)
    w *= 0.55 + 0.45 * (0.6 * np.sin(2 * np.pi * 0.4 * t) + 0.4 * np.sin(2 * np.pi * 0.2 * t + 1.0))
    save("wind", loopify(w, 1.0), -10, loop=True)


# --- Run --------------------------------------------------------------------------------

def run():
    # Footsteps on concrete: four slightly different scuffs.
    for i, (lo, hi, dec) in enumerate([(300, 2600, 0.022), (350, 3000, 0.018), (260, 2300, 0.026), (320, 2800, 0.02)]):
        st = mix((filt(noise(0.09), "band", (lo, hi)) * env_exp(0.09, dec, 0.003), 0, 1),
                 (sweep(110 + i * 8, 70, 0.06) * env_exp(0.06, 0.015), 0, 0.6))
        save(f"step_{i + 1}", st, -12)
    # Jump: an airy "hup".
    save("jump", sweep_band(noise(0.18), 500, 1600, 0.7) * env_hump(0.18, 0.3), -12)
    # Landing: a thud.
    save("land", mix((sweep(120, 55, 0.12) * env_exp(0.12, 0.04), 0, 1), (filt(noise(0.1), "low", 1200) * env_exp(0.1, 0.015), 0, 0.4)), -7)
    # Out of energy: two tired breaths.
    br = filt(noise(0.28), "band", (700, 2600)) * env_hump(0.28, 0.25)
    save("exhausted", mix((br, 0, 1), (br * 0.8, 0.42, 1)), -12)
    # Taya winding up a throw: the "!" alert.
    al = mix((tone(1400, 0.07, "tri") * env_ar(0.07, 0.003, 0.02), 0, 1), (tone(1900, 0.1, "tri") * env_ar(0.1, 0.003, 0.04), 0.08, 1))
    save("alert", al, -10)
    # Tsinelas hits you: a sharp "PAK!".
    pak = mix((filt(noise(0.12), "high", 1200) * env_exp(0.12, 0.012, 0.0005), 0, 1),
              (sweep(260, 140, 0.08) * env_exp(0.08, 0.02), 0, 0.7))
    save("slap", pak, -2)
    # Tagged: a hit and a falling "wah".
    wah = filt(np.tanh(3 * sweep(420, 140, 0.55)), "low", 1800) * env_ar(0.55, 0.01, 0.2)
    save("tagged", mix((pak, 0, 0.8), (wah, 0.05, 0.7)), -6)
    # Round clear: a short chiptune fanfare.
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = [(filt(tone(f, 0.12, "square"), "low", 4000) * env_ar(0.12, 0.004, 0.04), i * 0.09, 0.6) for i, f in enumerate(notes)]
    hold = sum(filt(tone(f, 0.7, "square"), "low", 3500) for f in (523.25, 659.25, 783.99)) / 3
    parts.append((hold * env_ar(0.7, 0.01, 0.4), 0.38, 0.7))
    parts.append((tone(1046.5, 0.7, "tri") * env_ar(0.7, 0.01, 0.4), 0.38, 0.4))
    save("round_clear", mix(*parts), -7)


# --- Mama's round and the end -------------------------------------------------------------------

def mama():
    # 6:00 PM: a town bell.
    bl = [(0.5, 0.6, 1.6), (1, 1, 1), (1.19, 0.6, 0.8), (1.5, 0.45, 0.7), (2, 0.5, 0.6), (2.5, 0.25, 0.4), (3, 0.2, 0.3)]
    save("bell", bell(330, 3.2, bl, 0.9), -3)
    # Mama arrives: an ominous low stab with a drum hit.
    stab = sum(filt(tone(f, 1.0, "saw"), "low", 1200) for f in (130.8, 155.6, 185.0)) / 3 * env_exp(1.0, 0.35, 0.005)
    drum = mix((sweep(110, 45, 0.6) * env_exp(0.6, 0.18), 0, 1), (filt(noise(0.4), "low", 600) * env_exp(0.4, 0.06), 0, 0.4))
    save("mama_sting", mix((stab, 0, 1), (drum, 0, 0.9)), -3)
    # Hanger / walis landing: a plasticky clatter.
    parts = []
    tt = 0.0
    for i in range(5):
        parts.append((filt(noise(0.05), "band", (1800, 5500)) * env_exp(0.05, 0.008), tt, 1.0 * 0.7 ** i))
        tt += rng.uniform(0.035, 0.08)
    save("clatter", mix(*parts), -4)
    # PALO! Caught by Mama: a whip crack and a big hit.
    crack = filt(noise(0.03), "high", 3000) * env_exp(0.03, 0.004, 0.0003)
    hitp = mix((filt(noise(0.2), "high", 900) * env_exp(0.2, 0.02), 0, 1), (sweep(200, 60, 0.35) * env_exp(0.35, 0.09), 0, 1))
    save("palo", mix((crack, 0, 1), (hitp, 0.03, 1)), -1)
    # Victory: a longer fanfare.
    seq = [(392, 0.0, 0.12), (523.25, 0.12, 0.12), (659.25, 0.24, 0.12), (783.99, 0.36, 0.3), (659.25, 0.72, 0.12), (783.99, 0.84, 0.12)]
    parts = [(filt(tone(f, d, "square"), "low", 4000) * env_ar(d, 0.004, 0.04), o, 0.55) for f, o, d in seq]
    t = T(1.6)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
    chord = sum(np.sin(2 * np.pi * np.cumsum(f * vib) / SR) for f in (523.25, 659.25, 783.99, 1046.5)) / 4
    parts.append((chord * env_ar(1.6, 0.02, 0.9), 0.98, 0.9))
    save("victory", mix(*parts), -5)
    # Game over: a slow sad slide down.
    seq = [(392, 0.0), (370, 0.32), (349.2, 0.64)]
    parts = [(tone(f, 0.3, "tri") * env_ar(0.3, 0.01, 0.08), o, 1) for f, o in seq]
    t = T(1.3)
    last = np.sin(2 * np.pi * np.cumsum(329.6 * (1 + 0.012 * np.sin(2 * np.pi * 6 * t))) / SR)
    parts.append(((2 / np.pi) * np.arcsin(last) * env_ar(1.3, 0.01, 0.7), 0.96, 1))
    save("game_over", mix(*parts), -8)
    # Banner (round titles, "6:00 PM"): a whoosh into a soft thump.
    ws = sweep_band(noise(0.3), 600, 2400, 0.7) * env_hump(0.3, 0.8)
    th = sweep(140, 60, 0.25) * env_exp(0.25, 0.07)
    save("banner", mix((ws, 0, 0.7), (th, 0.26, 1)), -8)


# --- Ambience ---------------------------------------------------------------------------

def ambience():
    # Crickets at dusk (loop): a few crickets chirping out of step.
    d = 8.0
    t = T(d)
    out = np.zeros_like(t)
    for carrier, rate, gap, amp in [(4300, 32, 0.55, 1.0), (4750, 28, 0.8, 0.7), (5150, 36, 0.95, 0.5)]:
        start = rng.uniform(0, gap)
        while start < d:
            pulses = rng.integers(3, 5)
            for k in range(pulses):
                s = start + k / rate
                n = int(0.018 * SR)
                i = int(s * SR)
                if i + n >= len(out):
                    break
                seg = np.sin(2 * np.pi * carrier * t[:n]) * np.sin(np.pi * np.arange(n) / n) ** 2
                out[i:i + n] += seg * amp * rng.uniform(0.7, 1.0)
            start += gap * rng.uniform(0.8, 1.25)
    out += 0.05 * filt(noise(d), "low", 400) # soft night air under them
    save("crickets", loopify(out, 1.5), -16, loop=True)


ui()
quiz()
throw()
run()
mama()
ambience()
