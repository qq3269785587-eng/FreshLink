"""Serve the existing production build on loopback with the isolated P0 API."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import http.client
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "apps" / "web" / "dist"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIST), **kwargs)

    def proxy(self):
        connection = http.client.HTTPConnection("127.0.0.1", 18080, timeout=60)
        path = "/jeecg-boot" + self.path[len("/jeecgboot"):]
        headers = {k: v for k, v in self.headers.items() if k.lower() not in {"host", "connection", "transfer-encoding"}}
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            connection.request(self.command, path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "content-length"}:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except OSError:
            self.send_error(502, "Isolated P0 backend is unavailable")
        finally:
            connection.close()

    def do_GET(self):
        if urlsplit(self.path).path.startswith("/jeecgboot/"):
            return self.proxy()
        requested = Path(self.translate_path(self.path))
        if not requested.exists() and "." not in requested.name:
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        if urlsplit(self.path).path.startswith("/jeecgboot/"):
            return self.proxy()
        self.send_error(405)

    do_PUT = do_POST
    do_DELETE = do_POST

    def log_message(self, format, *args):
        # Never log request paths, tokens, or login payloads.
        pass


if __name__ == "__main__":
    if not (DIST / "index.html").is_file():
        raise SystemExit("Build the frontend first")
    print("P0 production build: http://127.0.0.1:13101 -> isolated API 18080", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 13101), Handler).serve_forever()
