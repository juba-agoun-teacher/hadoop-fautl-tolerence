#!/usr/bin/env python3
"""
generate_ratings.py
-------------------
Génère un fichier ratings.csv synthétique au format MovieLens simplifié.
Format : userId,movieId,rating,timestamp
"""

import random
import time
import csv
import sys

def generate_ratings(output_file="ratings.csv", n=100_000, seed=42):
    random.seed(seed)

    users   = range(1, 1001)       # 1 000 utilisateurs
    movies  = range(1, 5001)       # 5 000 films
    ratings = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]

    base_ts = int(time.time()) - 3 * 365 * 24 * 3600  # ~3 ans en arrière

    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["userId", "movieId", "rating", "timestamp"])
        for _ in range(n):
            writer.writerow([
                random.choice(users),
                random.choice(movies),
                random.choice(ratings),
                base_ts + random.randint(0, 3 * 365 * 24 * 3600),
            ])

    print(f"✅  Fichier généré : {output_file}  ({n} lignes)")

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000
    generate_ratings("ratings.csv", n)
