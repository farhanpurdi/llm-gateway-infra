#!/usr/bin/env python3
"""Compare database data without emitting rows, keys, or spend details."""
import json
import subprocess
import sys

container, user, database = sys.argv[1:]

def query(sql):
    return subprocess.check_output(
        ["docker", "exec", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
         "-U", user, "-d", database, "-tAc", sql], text=True,
    ).strip()

tables = json.loads(query("SELECT coalesce(json_agg(tablename ORDER BY tablename),'[]') FROM pg_tables WHERE schemaname='public'"))
result = {}
for table in tables:
    quoted = '"' + table.replace('"', '""') + '"'
    result[table] = query(
        "SELECT count(*)::text || ':' || md5(coalesce(string_agg(row_to_json(t)::text, E'\\n' ORDER BY row_to_json(t)::text), '')) "
        f"FROM public.{quoted} t"
    )
print(json.dumps(result, sort_keys=True))
