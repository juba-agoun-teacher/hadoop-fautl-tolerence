#!/usr/bin/env python3
"""
mapper_ratings.py  –  Étape MAP (Hadoop Streaming)
---------------------------------------------------
Entrée  : lignes CSV  userId,movieId,rating,timestamp
Sortie  : <rating>\t1
"""
import sys

first_line = True
for line in sys.stdin:
    line = line.strip()
    if first_line:
        first_line = False
        if line.startswith("userId"):   # saute l'en-tête
            continue
    parts = line.split(",")
    if len(parts) < 3:
        continue
    try:
        rating = float(parts[2])
        # Arrondi à 0.5 près pour regrouper les notes
        rating_key = f"{rating:.1f}"
        print(f"{rating_key}\t1")
    except ValueError:
        pass
