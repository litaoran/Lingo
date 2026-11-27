#!/usr/bin/env python3
"""Synthesizes Lingo's start/stop sounds into App/Sounds. Standard library only.

Run: python3 scripts/make-sounds.py

Each sound is a few pure tones with smooth envelopes (no clicks), a gentle
pitch glide or note pair, and a short soft echo for warmth. Start sounds rise,
stop sounds fall, so they read as "on" and "off".
"""
import math, os, struct, sys, wave

RATE = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'App', 'Sounds')


def envelope(t, attack, decay):
    """Raised-cosine attack, then exponential decay."""
    if t < attack:
        return 0.5 - 0.5 * math.cos(math.pi * t / attack)
    return math.exp(-(t - attack) / decay)


def glide_tone(f0, f1, glide, duration, attack, decay, harmonics=((1, 1.0), (2, 0.12))):
    """A tone whose pitch slides from f0 to f1 (exponentially) over `glide` seconds."""
    n = int(duration * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        k = min(t / glide, 1.0)
        k = 1 - (1 - k) ** 3                      # ease-out
        f = f0 * (f1 / f0) ** k
        phase += 2 * math.pi * f / RATE           # phase-continuous
        s = sum(a * math.sin(h * phase) for h, a in harmonics)
        out.append(s * envelope(t, attack, decay))
    return out


def note(freq, duration, attack, decay, partials):
    """A plucked note: each partial is (ratio, amplitude, decay multiplier)."""
    n = int(duration * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for ratio, amp, dmul in partials:
            s += amp * math.sin(2 * math.pi * freq * ratio * t) * envelope(t, attack, decay * dmul)
        out.append(s)
    return out


def mix(*tracks):
    """tracks: (offset_seconds, samples)"""
    length = max(int(off * RATE) + len(s) for off, s in tracks)
    out = [0.0] * length
    for off, s in tracks:
        start = int(off * RATE)
        for i, v in enumerate(s):
            out[start + i] += v
    return out


def warm(samples, taps=((0.031, 0.18), (0.053, 0.10), (0.087, 0.05))):
    """Adds a few quiet early echoes so the sound feels less dry."""
    tail = int(max(d for d, _ in taps) * RATE)
    out = samples + [0.0] * tail
    for delay, gain in taps:
        d = int(delay * RATE)
        for i, v in enumerate(samples):
            out[i + d] += v * gain
    return out


def finish(samples, peak):
    """Normalizes to `peak` and fades the last 10 ms to silence."""
    m = max(abs(v) for v in samples) or 1.0
    samples = [v * peak / m for v in samples]
    fade = int(0.010 * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    return samples


def write(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in samples))
    print(f'{name}: {len(samples) / RATE * 1000:.0f} ms')


MARIMBA = ((1, 1.0, 1.0), (4.0, 0.22, 0.25), (9.2, 0.05, 0.12))

sounds = {
    # Soft: a warm, rounded "bloop" that slides up (start) or down (stop).
    'start-soft': finish(warm(glide_tone(523.25, 783.99, 0.07, 0.24, 0.008, 0.075)), 0.42),
    'stop-soft': finish(warm(glide_tone(783.99, 523.25, 0.07, 0.22, 0.008, 0.065)), 0.38),
    # Bubble: a short water-drop blip with a fast glide.
    'start-bubble': finish(warm(glide_tone(380, 1050, 0.045, 0.14, 0.004, 0.040, ((1, 1.0),))), 0.40),
    'stop-bubble': finish(warm(glide_tone(1050, 380, 0.045, 0.14, 0.004, 0.040, ((1, 1.0),))), 0.36),
    # Chime: two soft marimba-like notes, a rising fifth or a falling fifth.
    'start-chime': finish(warm(mix((0.0, note(659.25, 0.30, 0.004, 0.11, MARIMBA)),
                                   (0.075, note(987.77, 0.34, 0.004, 0.13, MARIMBA)))), 0.40),
    'stop-chime': finish(warm(mix((0.0, note(987.77, 0.28, 0.004, 0.10, MARIMBA)),
                                  (0.075, note(659.25, 0.32, 0.004, 0.12, MARIMBA)))), 0.36),
}

os.makedirs(OUT, exist_ok=True)
for name, samples in sounds.items():
    write(name + '.wav', samples)
