#!/usr/bin/env python3
"""Generate Omacale's notification sounds (assets/sounds/notification-*.wav).

Why generated rather than borrowed: the freedesktop set (and Omarchy's own
theme sounds, of which there are none) is 2010s GNOME -- long, orchestral,
and mixed for laptop speakers at 40% volume. Omacale's chime is a synthetic
pluck instead: a few hundred milliseconds, no reverb tail to sit on top of
music, and a timbre that reads as "computer, politely".

Design rules, which are the reason this is a script and not four binary files:
  * short. 250-600 ms, decaying from the first millisecond -- a notification
    interrupts, it must not make you wait for it;
  * synthetic. sine/FM, no orchestral sampling, no vibrato (vibrato is what
    makes a chime sound like a doorbell);
  * a tiny downward glissando at the onset (1-2%) is what makes a sine sound
    struck rather than switched on;
  * a soft lowpass keeps the FM partials from hissing on small speakers;
  * peak at -9 dBFS: audible under music, never a jump scare.

`assets/sounds/notification.wav` -- the default chime -- is NOT written here:
it is an adopted reference track (universfield, "Bright notification", see
THIRD_PARTY.md). The candidates below sit beside it, and `soundFile` picks one
by name.

Run: python3 scripts/gen-notification-sound.py
"""
import os
import wave

import numpy as np

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sounds")

CANDIDATES = ("glass", "pulse", "servo", "hal", "bright")


def pluck(freq, dur, decay, *, fm_ratio=0.0, fm_index=0.0, glide=0.015,
          partial=0.0, attack=0.004):
    """One struck note: sine at `freq`, optional FM partial, exponential decay."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    # The onset glissando. 30 ms is short enough to hear as a strike, long
    # enough not to click.
    f = freq * (1.0 + glide * np.exp(-t / 0.03))
    phase = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(phase)
    if partial:
        y += partial * np.sin(2.0 * phase)
    if fm_index:
        env_mod = np.exp(-t / (decay * 0.5))
        phase = phase + fm_index * env_mod * np.sin(2 * np.pi * fm_ratio * freq * t)
        y = np.sin(phase) + (partial * np.sin(2.0 * phase) if partial else 0.0)
    env = np.exp(-t / decay)
    a = max(1, int(attack * SR))
    env[:a] *= np.linspace(0.0, 1.0, a)
    return y * env


def place(track, note, at):
    """Mix `note` into `track` at `at` seconds, clipped to the track."""
    i = int(at * SR)
    j = min(len(track), i + len(note))
    track[i:j] += note[: j - i]


def lowpass(x, cutoff):
    """One-pole lowpass: enough to tame the FM partials, no filter ringing."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for k in range(len(x)):
        acc = (1 - a) * x[k] + a * acc
        y[k] = acc
    return y


def build(name):
    dur = {"glass": 0.62, "pulse": 0.55, "servo": 0.30, "hal": 0.75, "bright": 0.62}[name]
    track = np.zeros(int(SR * dur) + 1)

    if name == "glass":
        # One clean C6, a shimmer an octave up at -14 dB. The most minimal of
        # the four: nothing happens after the strike.
        place(track, pluck(1046.50, 0.62, 0.17, partial=0.18), 0.0)

    elif name == "pulse":
        # Two notes a fifth apart, 75 ms apart, light FM (ratio 2.76 = the
        # metallic one) -- a signal that the machine is done, not a doorbell.
        place(track, pluck(659.25, 0.40, 0.13, fm_ratio=2.76, fm_index=0.55), 0.0)
        place(track, pluck(987.77, 0.45, 0.15, fm_ratio=2.76, fm_index=0.55), 0.075)

    elif name == "servo":
        # A short descending blip: pitch falls 1500 -> 950 Hz in 110 ms. The
        # geekiest of the four, and the least musical.
        n = int(SR * 0.30)
        t = np.arange(n) / SR
        f = 950 + 550 * np.exp(-t / 0.045)
        phase = 2 * np.pi * np.cumsum(f) / SR
        y = 0.7 * np.sin(phase) + 0.3 * np.sin(2 * phase)
        env = np.exp(-t / 0.075)
        a = int(0.003 * SR)
        env[:a] *= np.linspace(0, 1, a)
        track = y * env

    elif name == "bright":
        # Modelled on universfield's "bright notification": a D6 with the very
        # high inharmonic partials of struck glass (4.0x and 8.1x the
        # fundamental, measured off that file) -- bright and metallic, where
        # "glass" is a pure sine.
        place(track, pluck(1176.5, 0.62, 0.24), 0.0)
        place(track, pluck(4717.6, 0.30, 0.09), 0.0)
        place(track, pluck(9547.0, 0.20, 0.05), 0.0)

    else:  # hal
        # A soft G5 with a wide fifth above it and a slow decay: the most
        # elegant one, and the only one that could be called warm.
        place(track, pluck(783.99, 0.75, 0.26, partial=0.12), 0.0)
        place(track, pluck(1174.66, 0.55, 0.20, partial=0.10), 0.055)

    # Gentle top-end roll-off: a bare sine is fine, the 2nd partial above 2 kHz
    # is what sounds cheap on a laptop.
    track = lowpass(track, 5200.0)

    # Peak -9 dBFS, short fade out so the tail can never click.
    track /= max(1e-9, np.max(np.abs(track))) / (10 ** (-9 / 20))
    fade = min(len(track), int(0.02 * SR))
    track[-fade:] *= np.linspace(1.0, 0.0, fade)
    return track


def write_wav(path, mono):
    pcm = np.clip(mono, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as fp:
        fp.setnchannels(1)
        fp.setsampwidth(2)
        fp.setframerate(SR)
        fp.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in CANDIDATES:
        path = os.path.join(OUT, "notification-%s.wav" % name)
        write_wav(path, build(name))
        print("%-28s %6.0f ms" % (path, os.path.getsize(path) / (SR * 2) * 1000))

if __name__ == "__main__":
    main()
