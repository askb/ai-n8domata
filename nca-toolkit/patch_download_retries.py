# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Anil Belur
"""Patch NCA Toolkit yt-dlp defaults for resilient YouTube downloads."""

from pathlib import Path


def replace_once(text: str, old: str, new: str, path: Path) -> str:
    """Replace one expected upstream snippet or fail the image build."""
    if old not in text:
        raise SystemExit(f"Expected patch target not found in {path}")
    return text.replace(old, new, 1)


def main() -> None:
    """Patch the upstream media download route in place."""
    path = Path("/app/routes/v1/media/download.py")
    text = path.read_text()

    text = replace_once(
        text,
        """                'quiet': True,
                'no_warnings': True,
                'download': data.get('cloud_upload', True)
            }""",
        """                'quiet': True,
                'no_warnings': True,
                'retries': 10,
                'fragment_retries': 10,
                'extractor_retries': 3,
                'retry_sleep_functions': {
                    'http': lambda n: 1,
                    'fragment': lambda n: 1,
                    'extractor': lambda n: 1,
                },
                'download': data.get('cloud_upload', True)
            }""",
        path,
    )

    text = replace_once(
        text,
        """                "rate_limit": {"type": "string"},
                "retries": {"type": "integer"}
            }""",
        """                "rate_limit": {"type": "string"},
                "retries": {"type": "integer"},
                "fragment_retries": {"type": "integer"},
                "extractor_retries": {"type": "integer"}
            }""",
        path,
    )

    text = replace_once(
        text,
        """                if download_options.get('retries'):
                    ydl_opts['retries'] = download_options['retries']""",
        """                if download_options.get('retries'):
                    ydl_opts['retries'] = download_options['retries']
                if download_options.get('fragment_retries'):
                    ydl_opts['fragment_retries'] = download_options['fragment_retries']
                if download_options.get('extractor_retries'):
                    ydl_opts['extractor_retries'] = download_options['extractor_retries']""",
        path,
    )

    compile(text, str(path), "exec")
    path.write_text(text)


if __name__ == "__main__":
    main()
