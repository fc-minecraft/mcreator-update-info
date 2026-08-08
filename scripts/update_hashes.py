import sys
import re
import urllib.request
import hashlib

PLATFORM_KEYS = {
    'WIN': 'SHA256_WIN',
    'WINDOWS': 'SHA256_WIN',
    'MAC64': 'SHA256_MAC64',
    'MAC': 'SHA256_MAC64',
    'MACARM': 'SHA256_MACARM',
    'ARM64': 'SHA256_MACARM',
    'LINUX': 'SHA256_LINUX',
    'LINUX64': 'SHA256_LINUX'
}

def calculate_sha256(url):
    print(f"Downloading & calculating SHA-256 for: {url}")
    hasher = hashlib.sha256()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        while chunk := response.read(65536):
            hasher.update(chunk)
    digest = hasher.hexdigest().lower()
    print(f" -> SHA-256: {digest}")
    return digest

def main():
    filepath = 'update.txt'
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            raw_lines = [line.rstrip('\r\n') for line in f]
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        sys.exit(1)

    urls = {}  # sha_key -> url
    sha_line_indices = {}  # sha_key -> line_index

    for idx, line in enumerate(raw_lines):
        trimmed = line.strip()
        if not trimmed or trimmed.startswith('#') or trimmed.startswith('//'):
            continue
        parts = re.split(r'\s+', trimmed, maxsplit=1)
        if len(parts) == 2:
            key = parts[0].upper()
            val = parts[1].strip()
            if key in PLATFORM_KEYS:
                sha_key = PLATFORM_KEYS[key]
                urls[sha_key] = val
            elif key.startswith('SHA256_'):
                sha_line_indices[key] = idx

    if not urls:
        print("No platform URLs found in update.txt")
        sys.exit(0)

    modified = False
    new_lines = list(raw_lines)

    for sha_key, url in urls.items():
        try:
            computed_sha = calculate_sha256(url)
        except Exception as e:
            print(f"Warning: Failed to process {url}: {e}")
            continue

        target_line = f"{sha_key} {computed_sha}"

        if sha_key in sha_line_indices:
            idx = sha_line_indices[sha_key]
            current_line = new_lines[idx].strip()
            if current_line != target_line:
                print(f"Updating existing {sha_key}: '{current_line}' -> '{target_line}'")
                new_lines[idx] = target_line
                modified = True
            else:
                print(f"Key {sha_key} is up-to-date: {computed_sha}")
        else:
            print(f"Adding missing {sha_key}: {target_line}")
            new_lines.append(target_line)
            modified = True

    if modified:
        with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(new_lines) + '\n')
        print("update.txt was successfully updated!")
        sys.exit(0)
    else:
        print("No changes required. All SHA-256 hashes are up to date.")
        sys.exit(0)

if __name__ == '__main__':
    main()
