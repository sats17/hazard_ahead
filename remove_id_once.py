#!/usr/bin/env python3
# remove_id_once.py
# One-off script: reads 'all_villages_latlon.csv', removes any "id" column, trims whitespace,
# and writes 'all_villages_latlon_noid.csv'.

import csv
import sys

INPUT = "all_villages_latlon.csv"
OUTPUT = "all_villages_latlon_noid.csv"

def clean(s):
    return s.strip() if s is not None else s

def main():
    try:
        with open(INPUT, "r", encoding="utf-8", newline="") as inf:
            sample = inf.read(4096)
            inf.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample)
            except Exception:
                dialect = csv.excel

            reader = csv.reader(inf, dialect)
            try:
                raw_header = next(reader)
            except StopIteration:
                print("Input CSV is empty.", file=sys.stderr)
                return 1

            header = [clean(h) for h in raw_header]
            keep_idxs = [i for i,h in enumerate(header) if h.lower() != "id"]
            if not keep_idxs:
                print("No columns left after removing 'id'. Aborting.", file=sys.stderr)
                return 1
            out_header = [header[i] for i in keep_idxs]

            with open(OUTPUT, "w", encoding="utf-8", newline="") as outf:
                writer = csv.writer(outf, dialect)
                writer.writerow(out_header)
                for row in reader:
                    if len(row) < len(header):
                        row = row + [""] * (len(header)-len(row))
                    elif len(row) > len(header):
                        row = row[:len(header)]
                    cleaned = [clean(row[i]) for i in keep_idxs]
                    writer.writerow(cleaned)

        print(f"Wrote cleaned CSV without id column to: {OUTPUT}")
        return 0
    except FileNotFoundError:
        print(f"Input file not found: {INPUT}", file=sys.stderr)
        return 2
    except Exception as e:
        print("Error:", e, file=sys.stderr)
        return 3

if __name__ == "__main__":
    raise SystemExit(main())
