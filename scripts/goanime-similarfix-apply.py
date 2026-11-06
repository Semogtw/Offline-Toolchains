import base64, pathlib, sys

def dec(s): return base64.b64decode(s).decode()

OPS = [
    ('replace', 'lib/services/manga/storage/manga_bundled_similar_sql_index.dart', 'Ly8vIEluZGV4ZWQsIFNIQS1ib3VuZCBsb29rdXAgb2YgdXAgdG8gMjQgcHJlY29tcHV0ZWQgbmVpZ2hib3JzIHBlciBtYW5nYS4KLy8vCi8vLyBUaGlzIGlzIGEgc2VwYXJhdGUgY29tcGFjdCBTUUxpdGUgYmVjYXVzZSB0aGUgZXhpc3RpbmcgYXZhaWxhYmlsaXR5IFNRTGl0ZQovLy8gaXMgYWxyZWFkeSBuZWFyIEdpdEh1YidzIHNpbmdsZS1ibG9iIGxpbWl0LiBUaGUgdmVyc2lvbiByZWNvcmRlZCBpbnNpZGUgdGhlCi8vLyBTUUwgaW5kZXggbXVzdCBleGFjdGx5IG1hdGNoIHRoZSBjdXJyZW50bHkgc2VsZWN0ZWQgY2F0YWxvZyByZXZpc2lvbi4=', 'Ly8vIEluZGV4ZWQgbG9va3VwIG9mIHVwIHRvIDI0IHByZWNvbXB1dGVkIG5laWdoYm9ycyBwZXIgbWFuZ2EuCi8vLwovLy8gVGhpcyBpcyBhIHNlcGFyYXRlIGNvbXBhY3QgU1FMaXRlIGJlY2F1c2UgdGhlIGV4aXN0aW5nIGF2YWlsYWJpbGl0eSBTUUxpdGUKLy8vIGlzIGFscmVhZHkgbmVhciBHaXRIdWIncyBzaW5nbGUtYmxvYiBsaW1pdC4gVGhlIGNhdGFsb2cgZGlnZXN0IHJlY29yZGVkCi8vLyBpbnNpZGUgdGhlIFNRTCBpbmRleCBpcyBhZHZpc29yeTogbmVpZ2hib3IgZW5kcG9pbnRzIGFyZSBoeWRyYXRlZCB0aHJvdWdoCi8vLyB0aGUgY3VycmVudGx5IHNlbGVjdGVkIGNhdGFsb2cgYmVmb3JlIGRpc3BsYXksIHNvIGEgY2F0YWxvZyByZXZpc2lvbiB0aGF0Ci8vLyBsZWF2ZXMgd29yayBJRHMgdW50b3VjaGVkIChmb3IgZXhhbXBsZSBhIHNjb3Jlcy1vbmx5IHJlY29tcHV0ZSkgbXVzdCBub3QKLy8vIGRpc2FibGUgdGhlIGJ1bmRsZWQgZ3JhcGgu'),
    ('replace', 'lib/services/manga/storage/manga_bundled_similar_sql_index.dart', 'ICAgICAgaWYgKG1ldGFkYXRhWydzY2hlbWFWZXJzaW9uJ10gIT0gJzEnIHx8CiAgICAgICAgICBtZXRhZGF0YVsnY2F0YWxvZ1NoYTI1NiddICE9IGV4cGVjdGVkRGlnZXN0KSB7CiAgICAgICAgdGhyb3cgY29uc3QgRm9ybWF0RXhjZXB0aW9uKCdTaW1pbGFyaXR5IFNRTC9jYXRhbG9nIFNIQSBtaXNtYXRjaCcpOwogICAgICB9', 'ICAgICAgaWYgKG1ldGFkYXRhWydzY2hlbWFWZXJzaW9uJ10gIT0gJzEnKSB7CiAgICAgICAgdGhyb3cgY29uc3QgRm9ybWF0RXhjZXB0aW9uKCdTaW1pbGFyaXR5IFNRTCBzY2hlbWEgbWlzbWF0Y2gnKTsKICAgICAgfQogICAgICBpZiAobWV0YWRhdGFbJ2NhdGFsb2dTaGEyNTYnXSAhPSBleHBlY3RlZERpZ2VzdCkgewogICAgICAgIC8vIFRoZSBncmFwaCBpcyBrZXllZCBieSBzdGFibGUgd29yayBJRHMgYW5kIGV2ZXJ5IGVuZHBvaW50IGlzCiAgICAgICAgLy8gaHlkcmF0ZWQgdGhyb3VnaCB0aGUgYWN0aXZlIGNhdGFsb2cgYmVmb3JlIGRpc3BsYXksIHNvIGEgZGlnZXN0CiAgICAgICAgLy8gZHJpZnQgKGUuZy4gdGhlIHNjb3Jlcy1vbmx5IGNhdGFsb2cgb2YgMjAyNi0xMS0wNCwgd2hvc2Ugc2lkZWNhcgogICAgICAgIC8vIHdhcyBuZXZlciByZWJhc2VkKSBkZWdyYWRlcyB0byBmZXdlciBjYXJkcywgbmV2ZXIgdG8gd3Jvbmcgb25lcy4KICAgICAgICAvLyBGYWlsIG9wZW4gb24gdGhlIGRpZ2VzdCBvbmx5OyBzY2hlbWEgYW5kIGludGVncml0eSBzdGF5IHN0cmljdC4KICAgICAgICBkZWJ1Z1ByaW50KAogICAgICAgICAgJ1NpbWlsYXIgV29ya3MgU1FMIHdhcyBidWlsdCBmb3IgYSBkaWZmZXJlbnQgY2F0YWxvZyBkaWdlc3Q7ICcKICAgICAgICAgICd1c2luZyB0aGUgYnVuZGxlZCBncmFwaCBhbnl3YXkuJywKICAgICAgICApOwogICAgICB9'),
    ('replace', 'test/services/manga/storage/manga_bundled_similar_sql_index_test.dart', 'ICB0ZXN0KCdpbmNvbXBhdGlibGUgY2F0YWxvZyBTSEEgZmFpbHMgY2xvc2VkJywgKCkgYXN5bmMgewogICAgZmluYWwgcmVhZGVyID0gY3JlYXRlUmVhZGVyKGRpZ2VzdDogJ2InICogNjQpOwogICAgZXhwZWN0KGF3YWl0IHJlYWRlci5uZWlnaGJvcnNGb3JXb3JrcyhbJ3NlZWQnXSksIGlzRW1wdHkpOwogICAgYXdhaXQgcmVhZGVyLmNsb3NlKCk7CiAgfSk7', 'ICB0ZXN0KCdhIGRpZmZlcmVudCBjYXRhbG9nIFNIQSBzdGlsbCBzZXJ2ZXMgdGhlIGJ1bmRsZWQgZ3JhcGgnLCAoKSBhc3luYyB7CiAgICAvLyBUaGUgcmVjb3JkZWQgZGlnZXN0IGlzIGFkdmlzb3J5OiBhIGNhdGFsb2cgcmV2aXNpb24gdGhhdCBrZWVwcyB3b3JrCiAgICAvLyBJRHMgKHNjb3Jlcy1vbmx5IHJlY29tcHV0ZSkgbXVzdCBub3QgZGlzYWJsZSBvZmZsaW5lIFNpbWlsYXIgV29ya3MuCiAgICBmaW5hbCByZWFkZXIgPSBjcmVhdGVSZWFkZXIoZGlnZXN0OiAnYicgKiA2NCk7CiAgICBmaW5hbCBuZWlnaGJvcnMgPSBhd2FpdCByZWFkZXIubmVpZ2hib3JzRm9yV29ya3MoWydzZWVkJ10pOwogICAgZXhwZWN0KG5laWdoYm9yc1snc2VlZCddPy5rZXlzLnRvTGlzdCgpLCBbJ3NlY29uZCcsICdmaXJzdCddKTsKICAgIGF3YWl0IHJlYWRlci5jbG9zZSgpOwogIH0pOw=='),
]

def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    for kind, rel, old, new in OPS:
        p = root / rel
        text = p.read_text()
        if kind == "replace":
            old, new = dec(old), dec(new)
            n = text.count(old)
            if n != 1:
                raise SystemExit(f"ANCHOR FAIL {rel}: found {n} (need 1)")
            text = text.replace(old, new)
        elif kind == "append":
            snippet = dec(old)
            text = text.rstrip("\n") + "\n" + snippet
        else:
            raise SystemExit(f"unknown op {kind}")
        p.write_text(text)
        print(f"applied {kind}: {rel}")
    print("ALL ANCHORS OK")


if __name__ == "__main__":
    main()

