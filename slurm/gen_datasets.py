#!/usr/bin/env python3
"""Generate synthetic datasets if the real ones are not available.
Replace with your course datasets in datasets/ if you have them."""
import os, numpy as np
os.makedirs("datasets", exist_ok=True)
rng = np.random.default_rng(42)

def blobs(n, d, k):
    centers = rng.uniform(-10, 10, (k, d))
    lab = rng.integers(0, k, n)
    return centers[lab] + rng.normal(0, 1.0, (n, d))

def write(path, a):
    if os.path.exists(path):
        print("exists, keeping", path); return
    np.savetxt(path, a, delimiter=",", fmt="%.6f")
    print("wrote", path, a.shape)

write("datasets/100000x5.csv", blobs(100000, 5, 10))
write("datasets/mouse_500x2.csv", blobs(500, 2, 3))
