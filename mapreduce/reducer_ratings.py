#!/usr/bin/env python3
"""
reducer_ratings.py  –  Étape REDUCE (Hadoop Streaming)
-------------------------------------------------------
Entrée  : paires triées  <rating>\t1
Sortie  : <rating>\t<count>
"""
import sys

current_rating = None
current_count  = 0

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) != 2:
        continue
    rating, count = parts[0], int(parts[1])

    if rating == current_rating:
        current_count += count
    else:
        if current_rating is not None:
            print(f"{current_rating}\t{current_count}")
        current_rating = rating
        current_count  = count

if current_rating is not None:
    print(f"{current_rating}\t{current_count}")
